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

#include "LightSampling.slangh"


/** Path measurement */

void forwardHWSSMis(const IMaterialInstance bsdf,
                    const ShadingData sd,
                    const float3 wo,
                    const uint sampledBsdfLobe,
                    inout PLTBeam beam) {
    if (mHWSSDoMIS) {
        const hwss_t pdfs = bsdf.lambdaPdf(sd, wo, sampledBsdfLobe, beam, beam.wavelengths);
        beam.spectralPDFs *= pdfs;
    }
}

void forwardUnwindStep(const TriangleHit triangleHit,
                       const VertexData v,
                       const float3 wo,
                       const uint sampledBsdfLobe,
                       inout PLTBeam beam) {
    let lod = ExplicitLodTextureSampler(0.f);
    const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -beam.r, lod);

    // Propagate
    beam.propagate(sd.posW);

    // BSDF
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    bsdf.eval(sd, wo, sampledBsdfLobe, beam);

    // Spectral MIS
    forwardHWSSMis(bsdf, sd, wo, sampledBsdfLobe, beam);
}
// Replay path and evaluate contributions
void forwardUnwind(const int bounceIdx, const uint2 pixel, inout PLTBeam beam) {
    for (int p=bounceIdx-1; p>=0; --p) {
        const BounceData bounce = readBounce(p, pixel);

        const TriangleHit triangleHit = TriangleHit(bounce.hit);
        const VertexData v = gScene.getVertexData(triangleHit);

        const float3 wo = bounce.wi;

        forwardUnwindStep(triangleHit, v, wo, bounce.sampledBsdfLobe, beam);
    }
}
void manifoldForwardUnwind(const ManifoldSampleData result,
                           const float3 origin,
                           inout PLTBeam beam) {
    for (int idx=result.hitCount-1; idx>=0; --idx) {
        const TriangleHit triangleHit = TriangleHit(result.hits[idx].hit);
        VertexData v = gScene.getVertexData(triangleHit);
        v.posW = result.hits[idx].posW;

        const float3 p2 = idx==0 ? origin : result.hits[idx-1].posW;
        const float3 wo = normalize(p2 - v.posW);

        forwardUnwindStep(triangleHit, v, wo, result.hits[idx].lobe, beam);
    }
}

// Measure beam at sensor
void measure(inout PLTSolve solveData, const int bounceIdx, float pathContribution, inout PLTBeam beam) {
    if (!kUseDirectLights && bounceIdx<=1)
        return;

    const float k = M_2PI / (1e-3f * beam.wavelengths.x);

#if DO_DEBUG_VIEW==1
    // Write coherence debug values before propagation to camera
    writeDebugOutputCC2(DebugViewType::coherence_area, solveData, sqrt(beam.coherenceArea(k))/150.f);
    writeDebugOutputCC(DebugViewType::coherence_anisotropy, solveData, beam.coherenceAnisotropy(k));
#endif

    // Propagate to camera
    beam.propagate(gScene.camera.data.posW);

    // Camera polarizer
    const float polarizationIntensity = gScene.camera.data.polarizer;
    const float polarizationTheta = gScene.camera.data.polarizerTheta;
    if (polarizationIntensity>.0f) {
        // Rotate to camera frame
        const float3 cameraW = normalize(gScene.camera.data.cameraW);
        const float3 cameraU = normalize(gScene.camera.data.cameraU);
        beam.rotateFrame(cameraU,-cameraW);

        // Polarize
        const float4x4 P = (1.f-polarizationIntensity) * ident4() +
                            polarizationIntensity * MuellerPolarizer(polarizationTheta);
        for (int j = 0; j < beam.hwss_comps; ++j)
            beam.setSP(j, mul(P, beam.getSP(j)));
    }

    // TODO: Camera/lens effects

    if (mHWSSDoMIS) {
        // MIS spectral contributions
        const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
        pathContribution *= sum>FLT_EPSILON ? beam.spectralPDFs[0]/sum : .0f;
    }
    else
        pathContribution *= 1.f / float(beam.hwss_comps);

    const hwss_t Li = beam.L;
    const float3 Lrgb = max(float3(.0f), SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps) * pathContribution);

    if (all(isfinite(Lrgb)))
        solveData.Lrgb += Lrgb;

#if DO_DEBUG_VIEW==1
    // Write debug views
    markDebug(solveData, bounceIdx, beam);
#endif
}


/** Emissive contributions */

void evalEmissive(inout PLTSolve solveData,
                  const int bounceIdx,
                  const BounceData bounce,
                  const uint2 pixel,
                  const IMaterialInstance bsdf,
                  const BSDFProperties bsdfProp,
                  const ShadingData sd,
                  const TriangleHit triangleHit,
                  bool importanceSampleSpectrum) {
    // Emissive geometry
    // Only direct-sample lights if we do not use MIS or no NEE was performed
    const bool didNEE = wasNEEAvailable(bounceIdx, bounce.flags);
    if (kUseEmissiveLights && bsdfProp.isEmissive && (kDoMIS || !didNEE)) {
        // MIS?
        const bool needMIS = kDoMIS && didNEE;

        // Compute MIS weight
        TriangleLightHit hit;
        hit.triangleIndex = gScene.lightCollection.getTriangleIndex(triangleHit.instanceID, triangleHit.primitiveIndex);
        hit.posW = sd.posW;
        hit.normalW = sd.frontFacing ? sd.faceN : -sd.faceN;
        const float lightPdf = getEmissiveSelectionProbability() * emissiveSampler.evalPdf(solveData.pathOrigin, solveData.pathNormal, false, hit);
        const float misWeight = needMIS ? MISWeight(bounce.lastNonDeltaPdf, lightPdf) : 1.f;

        // Emitted intensity
        hwss_t sampledWavelengths;
        hwss_t Le = gScene.sampleSpectrum(bsdfProp.emissionSpectralId, solveData.wavelength, solveData.sg, importanceSampleSpectrum, sampledWavelengths);
        Le *= misWeight * SpectrumUtils.rgbToSpectrum(bsdfProp.emissionRGB, sampledWavelengths);

        if (any(Le > .0f)) {
            // Source emitted beam and forward unwind
            const float dist = length(solveData.pathOrigin - sd.posW);
            PLTBeam beam = pltSourceBeamArea(sd.posW,
                                             bounce.wi,
                                             kSourcingAreaFromEmissiveGeometry,
                                             dist,
                                             Le,
                                             sampledWavelengths,
                                             kSourcingMaxBeamOmega,
                                             kForceFullyCoherent);

            if (!mHWSSDoMIS && bounce.flags.dispersiveDeltaSegment)
                beam.collapseToHeroWavelengthOnly();

            forwardUnwind(bounceIdx, pixel, beam);
            measure(solveData, bounceIdx, bounce.pathContribution, beam);
        }
    }
}


/** Next-event estimation */

bool wasNEEAvailable(const int bounceIdx, const RayFlags pathFlags) {
    return
        kDoNEE && bounceIdx>0 &&
        (!pathFlags.lastBounceWasDelta ||
         (kDoMSonNEE && pathFlags.MSCompatibleBounces<=kMNEEMaxMSOccluders && bounceIdx>1));
}

float MISWeight(float p0, float p1, float n0=1.f, float n1=1.f) {
    // Balance heuristic
    float q0 = n0 * p0;
    float q1 = n1 * p1;
    return q0 / (q0 + q1);
}

void evalNEE(inout PLTSolve solveData,
             const int bounceIdx,
             const BounceData bounce,
             const uint2 pixel,
             const VertexData V,
             const uint materialID,
             const IMaterialInstance bsdf,
             inout PLTBeam beam,
             const bool NEEEvalCurrentVertex) {
    if (NEEEvalCurrentVertex) {
        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData forwardSd = gScene.materials.prepareShadingData(V, materialID, -beam.r, lod);

        // Propagate beam from source and evaluate non-delta BSDF interaction
        beam.propagate(forwardSd.posW);
        bsdf.eval(forwardSd, bounce.wi, (uint)LobeType::NonDelta, beam);

        // Spectral MIS
        forwardHWSSMis(bsdf, forwardSd, bounce.wi, (uint)LobeType::NonDelta, beam);
    }

    // Forward unwind beam
    forwardUnwind(bounceIdx, pixel, beam);
    measure(solveData, bounceIdx, bounce.pathContribution, beam);
}

void NEE(inout PLTSolve solveData,
         const int bounceIdx,
         const BounceData bounce,
         const uint2 pixel,
         const TriangleHit triangleHit,
         const ShadingData sd,
         const VertexData V,
         const IMaterialInstance bsdf,
         const BSDFProperties bsdfProp) {
    const uint lobes = bsdf.getLobes(sd);

    const bool allowMSOnCurrentVertex = kDoMSonNEE && bounceIdx>0 && !bounce.flags.lastBounceWasDelta && bsdfProp.canManifoldWalkReflective;
    // NEE on non-delta lobes, or manifold walk on a delta lobe
    const bool sampleReflection = (lobes & (uint)LobeType::NonDeltaReflection)!=0 || allowMSOnCurrentVertex;
    const bool sampleTransmission = (lobes & (uint)LobeType::NonDeltaTransmission)!=0;

    if (!sampleReflection && !sampleTransmission)
        return;

    // Sample a light.
    LightSample ls;
    const bool importanceSampleSpectrum = kImportanceSampleEmissiveSpectra;
    const bool valid = generateLightSample(sd, sampleReflection, sampleTransmission, solveData.sg, solveData.tilesg, solveData.wavelength, importanceSampleSpectrum, ls);
    if (!valid || !any(ls.beam.L>.0f))
        return;

    // Update HWSS component count of sourced beam
    if (!mHWSSDoMIS && bounce.flags.dispersiveDeltaSegment)
        ls.beam.collapseToHeroWavelengthOnly();

    // Do we do MIS?
    bool doMis = kDoMIS && ls.lightType!=(uint)SampledLightType::Analytic;
    // Do we need to eval current vertex on forward unwind? (Manifold sampling might involve current vertex)
    bool evalCurrentVertex = true;

    // Check visibility, or do MNEE
    const int maxMSBounces = int(mMaxBounces)-bounceIdx;
    let visRayDesc = ls.getVisibilityRay();
    if (!kDoMSonNEE || maxMSBounces<=0) {
        if (!visibilityRay(visRayDesc))
            return;

        // MIS?
        if (doMis) {
            const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, bsdfPdf));
        }
    } else {
        /** Manifold sampling on NEE
        */

        const float3 lightDir = -ls.beam.r;
        float MISBsdfPdf;

        ManifoldSampleData msresult = ManifoldSampleData(ls.beam.wavelengths.x);

        // Are we doing MS on this vertex (e.g., delta lobe) as well? (Never on initial bounce)
        const bool isReflection = dot(sd.N, lightDir)*dot(sd.N, sd.V) > .0f;
        const bool currentVertexMS = isReflection && allowMSOnCurrentVertex;

        if (currentVertexMS) {
            if (!manifoldSampleVertex(bounce.hit, triangleHit, sd, bsdf, lightDir, solveData.sg, msresult) ||
                (msresult.hits[0].lobe&(uint)LobeType::Reflection)==0)
                return;
        }

        // Do MS
        const float3 origin = !currentVertexMS ? V.posW : solveData.pathOrigin;
        const bool mneeOk = manifoldNEESample(visRayDesc, origin,
                            ls.beam.posW, lightDir, ls.beam.distant,
                            maxMSBounces, solveData.sg,
                            msresult);

#if DO_DEBUG_VIEW==1
        // MNEE debug views
        writeDebugOutputCC(DebugViewType::mnee_iterations, solveData,
                           msresult.iterations/float(kMNEEMaxIterations));
        if (msresult.hitCount>0 && mneeOk)
            writeDebugOutput(DebugViewType::mnee_bounces, solveData,
                             msresult.hitCount==0 ? float3(.0f) :
                             msresult.hitCount==1 ? float3(0,0.3,1) : float3(1,0,0));
#endif

        if (!mneeOk || msresult.pdf<1e-6f)
            return;

        // If hitcount is 0, then this is a simple NEE, otherwise need to evaluate the found connections.
        if (msresult.hitCount > 0) {
            // If the MS path is dispersive, reduce to single-wavelength beam
            if (!mHWSSDoMIS && msresult.dispersive)
                ls.beam.collapseToHeroWavelengthOnly();
            if (!ls.beam.distant) {
                ls.dir = msresult.woLastHitToLight;
                // Rotate beam towards the new last interaction point
                ls.beam.r = -msresult.woLastHitToLight;
                ls.beam.t = perp_stark(ls.beam.r);
            }

            // MS pdf
            ls.beam.scale(1.f / msresult.pdf);
            // Evaluate MS path
            manifoldForwardUnwind(msresult, origin, ls.beam);

            // Special care when MS is done for this vertex
            if (currentVertexMS) {
                evalCurrentVertex = false;
                MISBsdfPdf = bounce.lastNonDeltaPdf;
            }
        }

        // MIS
        if (doMis) {
            // MIS BSDF pdf for MS that involves the current vertex was computed above
            if (msresult.hitCount==0 || !currentVertexMS)
                MISBsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, MISBsdfPdf * msresult.pdf));
        }
    }

    // Finally, evaluate NEE contributions
    evalNEE(solveData, bounceIdx, bounce, pixel, V, sd.materialID, bsdf, ls.beam, evalCurrentVertex);
}


/** Miss */

void onMiss(inout PLTSolve solveData,
            const int bounceIdx,
            const BounceData bounce,
            const uint2 pixel) {
    const float3 wo = bounce.wi;
    // Only direct-sample lights if we do not use MIS or no NEE was performed
    const bool didNEE = wasNEEAvailable(bounceIdx, bounce.flags);
    if (kUseEnvLight && (kDoMIS || !didNEE)) {
        // MIS?
        const bool needMIS = kDoMIS && didNEE;
        const float lightPdf = getEnvMapSelectionProbability() * envMapSampler.evalPdf(-wo);
        const float misWeight = needMIS ? MISWeight(bounce.lastNonDeltaPdf, lightPdf) : 1.f;

        // TODO: importance sample envmap wavelengths?
        const hwss_t wavelengths = SpectrumSampler.hwssWavelengths(solveData.wavelength);
        const hwss_t Le = misWeight * SpectrumUtils.rgbToSpectrum(gScene.envMap.eval(-wo), wavelengths);
        PLTBeam beam = pltSourceBeamDistant(wo, kSourcingMaxBeamOmega, Le, wavelengths, kSourcingMaxBeamOmega, kForceFullyCoherent);

        if (!mHWSSDoMIS && bounce.flags.dispersiveDeltaSegment)
            beam.collapseToHeroWavelengthOnly();

        // Forward unwind beam
        forwardUnwind(bounceIdx, pixel, beam);
        measure(solveData, bounceIdx, bounce.pathContribution, beam);
    }
}


/** Solve */

[shader("raygeneration")]
void main() {
    const uint2 rayIdx = DispatchRaysIndex().xy;
    const uint2 pixel = rayIdx + kTile * mTileSize;
    const uint2 frameDim = kOutputSize;
    if (any(pixel>=frameDim))
        return;


    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);
    // To reduce divergence, we use an SG with a per-tile seed for NEE
    SampleGenerator tilesg = SampleGenerator(kTile, gFrameCount<<2);

    // First we do with the SG is draw the sampling wavelength, as we require it to be the same between sample and solve pass.
    const float samplingWavelength = SpectrumSampler.sampleOne(sampleNext1D(sg));


    // Evaluate all bounces
    PLTSolve solveData = PLTSolve(sg, tilesg, samplingWavelength);
    for (int p=0;;++p) {
        const BounceData bounce = readBounce(p, pixel);

        // Miss?
        if (bounce.flags.miss) {
            onMiss(solveData, p, bounce, pixel);
            break;
        }

        // Process hit data
        const TriangleHit triangleHit = TriangleHit(bounce.hit);
        const VertexData v = gScene.getVertexData(triangleHit);
        const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);

        const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, bounce.wi, lod);
        let bsdf = gScene.materials.getMaterialInstance(sd, lod);
        const BSDFProperties bsdfProp = bsdf.getProperties(sd);

        // NEE
        if (kDoNEE) {
            NEE(solveData, p, bounce, pixel, triangleHit, sd, v, bsdf, bsdfProp);
        }

        // Emissive material?
        const bool importanceSampleSpectrum = kImportanceSampleEmissiveSpectra;
        evalEmissive(solveData, p, bounce, pixel, bsdf, bsdfProp, sd, triangleHit, importanceSampleSpectrum);


        // Geometry debug info
#if DO_DEBUG_VIEW==1
        if (p == 0) {
            writeDebugOutput(DebugViewType::normals, solveData, sd.N);
            writeDebugOutput(DebugViewType::albedo, solveData, bsdfProp.albedo);
            writeDebugOutput(DebugViewType::roughness, solveData, bsdfProp.roughness);
            writeDebugOutput(DebugViewType::UVs, solveData, float3(sd.uv.x,0,sd.uv.y));
        }
#endif


        if (bounce.flags.terminated || p==mMaxBounces)
            break;
        solveData.pathOrigin = v.posW;
        solveData.pathNormal = sd.N;
    }


    gOutputColor[pixel] = float4(solveData.Lrgb, 1.f);


#if DO_DEBUG_VIEW==1
    gOutputColor[pixel] = float4(lerp(gOutputColor[pixel].rgb,
                                      solveData.debugOutput.a>.0f ? solveData.debugOutput.rgb/solveData.debugOutput.a : float3(.0f),
                                      kDebugViewIntensity),
                                 1.f);
#endif
}
