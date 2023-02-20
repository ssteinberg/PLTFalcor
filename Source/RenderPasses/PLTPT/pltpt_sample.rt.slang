/***************************************************************************
 # PLT
 # Copyright (c) 2022-23, Shlomi Steinberg. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/

#include "pltpt.slangh"


/** Path construction */

// Returns reciprocal thp modifier, or .0f for termination
float shouldTerminatePath(inout Path path) {
    const float rrE = 2.f;
    return kDoRussianRoulette ?
        RR(1.f - path.weight, rrE, sampleNext1D(path.sg)) :
        1.f;
}

// BSDF sampling
bool pltSampleBSDF<S: ISampleGenerator>(const ShadingData sd,
                                        const IMaterialInstance bsdf,
                                        inout S sg,
                                        out BSDFSample bsdfSample,
                                        const float wavelength) {
    const bool valid = bsdf.sample(sd, sg, bsdfSample, wavelength);
    if (!valid || bsdfSample.pdf==.0f)
        return false;
    return true;
}

[shader("miss")]
void scatterMiss(inout Path path) {
    const float3 wi = -path.dir;

    path.flagMiss();
    appendBounce(path, wi);
}

[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout Path path, BuiltInTriangleIntersectionAttributes attribs) {
    const uint2 pixel = path.getPixel();

    // Shading data
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;
    const PackedHitInfo hitInfo = triangleHit.pack();

    const VertexData v = gScene.getVertexData(triangleHit);
    const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);

    const float3 wi = -path.dir;
    const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, wi, lod);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);

    if (kAlphaMasking && sd.opacity == .0f) {
        // Alpha mask
        path.origin = sd.computeNewRayOrigin(false);
        return;
    }

    // Done?
    // We still need to eval emissive before ending path.
    const float rcp_thp = shouldTerminatePath(path);
    bool shouldEndPath = path.length==mMaxBounces || (rcp_thp==.0f && path.length>0);

    // BSDF sampling and generate a new ray direction.
    BSDFSample bsdfSample;
    if (!shouldEndPath) {
        shouldEndPath = !pltSampleBSDF(sd, bsdf, path.sg, bsdfSample, path.wavelength);
        const float new_contribution = path.pdf*bsdfSample.pdf*path.thp_modifier*rcp_thp;
        shouldEndPath |= new_contribution < 1e-6f;
    }

    const bool isDelta        = bsdfSample.isLobe(LobeType::Delta);
    const bool isDispersive   = bsdfSample.isLobe(LobeType::DispersiveDelta);
    const bool isReflection   = bsdfSample.isLobe(LobeType::Reflection);
    const bool isMSCompatible = ( isReflection && bsdfProp.canManifoldWalkReflective) ||
                                (!isReflection && bsdfProp.canManifoldWalkTransmissive);

    // Albedo and normal targets output
    if (!isDelta && path.flags.onlyDelta) {
        gOutputAlbedo[pixel] = float4(bsdfProp.albedo, 1.f);
        gOutputNormal[pixel] = float4(mul(float3x3(gScene.camera.data.viewMat), sd.N), 1.f);
    }

    if (shouldEndPath) {
        // Terminate path
        path.endPath();
        appendBounce(path, hitInfo, wi);
        return;
    }

    /** Path bookeeping
    */
    // Update path weight, thp and pdf
    path.weight *= bsdfSample.weight;
    path.thp_modifier *= rcp_thp;
    path.pdf *= bsdfSample.pdf;
    // A dispersive delta lobe means that this path now transports a single wavelength (HWSS off)
    path.flags.dispersiveDeltaSegment |= isDispersive;
    // Store bounce
    appendBounce(path, hitInfo, wi, bsdfSample.lobe);
    ++path.length;
    // Keep track of MIS stuff
    path.lastNonDeltaPdf = !isDelta ? bsdfSample.pdf : path.lastNonDeltaPdf;
    path.flags.MSCompatibleBounces = isMSCompatible ? path.flags.MSCompatibleBounces+1 : 0u;
    path.flags.lastBounceWasDelta = isDelta;
    path.flags.onlyDelta = path.flags.onlyDelta && isDelta;
    path.normal = sd.N;
    // Next ray tracing direction
    path.origin = sd.computeNewRayOrigin(isReflection);
    path.dir = bsdfSample.wo;
}


/** Sample */

[shader("raygeneration")]
void main() {
    const uint2 rayIdx = DispatchRaysIndex().xy;
    const uint2 pixel = rayIdx + kTile * mTileSize;
    const uint2 frameDim = kOutputSize;
    if (any(pixel>=frameDim))
        return;

    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);

    // First we do with the SG is draw the sampling wavelength, as we require it to be the same between sample and solve pass.
    const float samplingWavelength = SpectrumSampler.sampleOne(sampleNext1D(sg));


    gOutputNormal[pixel] = float4(.0f);
    gOutputAlbedo[pixel] = float4(.0f);


    // Sample stage
    // Ray trace a path
    Path path = Path(sg, pixel, frameDim, samplingWavelength);
    for (path.length = 0; path.length<mMaxBounces+1 && path.flags.valid;) {
        RayDesc ray;
        ray.Origin = path.origin;
        ray.Direction = path.dir;
        ray.TMin = 0.f;
        ray.TMax = FLT_MAX;

        TraceRay(
            gScene.rtAccel,
            0,               // rayFlags
            0xff,            // instanceInclusionMask
            0,               // hitIdx
            rayTypeCount,
            0,               // missIdx
            ray,
            path
        );
    }
}
