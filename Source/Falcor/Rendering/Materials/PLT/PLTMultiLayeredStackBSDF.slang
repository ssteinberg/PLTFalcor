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
#include "Utils/Math/MathConstants.slangh"

__exported import Rendering.Materials.IMaterialInstance;
__exported import Rendering.Materials.BxDF;
__exported import Rendering.Materials.PLT.Mueller;
import Rendering.PLT;
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTMultiLayeredStackBxDF
{
    float3 albedo = float3(1.f);
    float extEta;
    float2 ior, thickness;
    uint layers;

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }
    // Phase shift between the layers
    float2 phasor(const float cosThetaT, const float thickness, const float eta, const float k) {
        const float d = 2.f*thickness/cosThetaT*k*eta;
        return float2(cos(d),sin(d));
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool isReflection = toLight.z*toEye.z > .0f;
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const bool hasReflection = (lobe & (uint)LobeType::Reflection) != 0;
        if (!isDirect || !isReflection) {
            beam.setZero();
            return;
        }

        const hwss_t k = M_2PI / (1e-3f*beam.wavelengths);       // um^(-1)
        const hwss_t m00 = SpectrumUtils.rgbToSpectrum(albedo, beam.wavelengths);
        const float eta1 = ior.x/extEta;
        const float eta2 = ior.y/ior.x;

        // TODO: polarization
        float2 cosThetaT, r;
        const float Rout = sqrt(evalFresnelDielectric(eta1,toLight.z,cosThetaT.x));
        r.x = sqrt(evalFresnelDielectric(eta2,-cosThetaT.x,cosThetaT.y));
        r.y = sqrt(evalFresnelDielectric(eta2,cosThetaT.y));
        cosThetaT = abs(cosThetaT);

        for (int j = 0; j < beam.hwss_comps; ++j) {
            // Start with base reflectance
            float2 G = c_t(sqrt(m00[j]));
            for (uint l=0; l<layers; ++l) {
                const uint idx = l%2;
                const float2 p = phasor(cosThetaT[idx], thickness[idx], ior[idx], k[j]);
                const float R = l==layers-1 ? Rout : r[idx];

                // Accumulate layer
                G = cmul(G, p);
                G = cdiv(c_t(R) + G, c_t(1.f) + R*G);
            }

            beam.setSP(j, sqr(creal(G)) * beam.getSP(j));
        }
    }

    float3kpdv partialDerivatives(const float3pdv wi, const float3pdv n, const uint lobe, float wavelength)
    {
        return reflectDerivatives(wi,n);
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint lobe, inout S sg, const float wavelength, const uint lobeMask = (uint)LobeType::All)
    {
        const bool hasReflection   = (lobeMask&(uint)LobeType::Reflection)!=0;
        const bool hasDirect       = (lobeMask&(uint)LobeType::Delta)!=0;
        if (!hasReflection || !hasDirect || wiLocal.z<=.0f) return false;

        pdf = 1.f;
        wo = reflect(wiLocal);
        lobe = (uint)LobeType::DeltaReflection;
        weight = SpectrumUtils.rgbToSpectrum(albedo, wavelength);

        return wiLocal.z*wo.z > .0f;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        if (wiLocal.z<=.0f || woLocal.z<=.0f)
            return .0f;

        // No non-delta lobes
        return .0f;
    }

    float weight(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        return SpectrumUtils.rgbToSpectrum(albedo, wavelength);
    }

    hwss_t lambdaPdf(const float3 toLight, const float3 toEye, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        // No wavelength-dependant sampling
        return 1.f;
    }

    float2x2 coherenceTransform(const float3 wiLocal, const float3 woLocal, const uint lobe) {
        return ident2();
    }
};

struct PLTMultiLayeredStackBSDF : IMaterialInstance
{
    PLTMultiLayeredStackBxDF bxdf;

    void eval(const ShadingData sd, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        beam.r = sd.toLocal(beam.r);
        beam.t = sd.toLocal(beam.t);

        const float3 wiLocal = sd.toLocal(sd.V);
        const float3 woLocal = sd.toLocal(toEye);
        // Rotate beam to the exitant frame (BSDF evaluation is done in that frame)
        beam.constructLocalFrame(woLocal);

        bxdf.eval(wiLocal, woLocal, lobe, beam, flags);

        // Transform coherence on interaction
        beam.transformCoherence(bxdf.coherenceTransform(wiLocal, woLocal, lobe));

        beam.r = sd.fromLocal(beam.r);
        beam.t = sd.fromLocal(beam.t);
    }

    float3kpdv partialDerivatives(const float3pdv wi, const DifferentialShadingGeometry dsg, const uint lobe, float wavelength)
    {
        return bxdf.partialDerivatives(wi, dsg.n, lobe, wavelength);
    }

    bool sample<S : ISampleGenerator>(const ShadingData sd, inout S sg, out BSDFSample result, const float wavelength, const uint lobeMask = (uint)LobeType::All, const float3 woHint = .0f)
    {
        bool valid = bxdf.sample(sd.toLocal(sd.V), result.wo, result.pdf, result.weight, result.lobe, sg, wavelength, lobeMask);
        if (valid)
            result.wo = sd.fromLocal(result.wo);
        return valid;
    }

    float pdf(const ShadingData sd, const float3 toLight, const float wavelength)
    {
        return bxdf.pdf(sd.toLocal(toLight), sd.toLocal(sd.V), wavelength);
    }

    hwss_t lambdaPdf(const ShadingData sd, const float3 wo, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        return bxdf.lambdaPdf(sd.toLocal(sd.V), sd.toLocal(wo), lobe, beam, wavelengths);
    }

    BSDFProperties getProperties(const ShadingData sd)
    {
        BSDFProperties p = {};
        p.flags = (uint)BSDFProperties.Flags::CanManifoldWalkReflective;
        p.albedo = bxdf.albedo;
        p.roughness = 0;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return (uint)LobeType::DeltaReflection;
    }
};
