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

import Rendering.PLT;

__exported import Rendering.Materials.IMaterialInstance;
__exported import Rendering.Materials.BxDF;
import Utils.Math.MathHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;

struct PLTDiffuseBxDF
{
    float3 albedo;

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool valid = (lobe&(uint)LobeType::DiffuseReflection)!=0;

        const hwss_t colour = SpectrumUtils.rgbToSpectrum(albedo, beam.wavelengths);
        const hwss_t w = valid ? abs(toLight.z) * M_1_PI * colour : hwss_t(.0f);

        beam.L *= w;
        // Depolarize (ideal diffuse interaction)
        beam.L1 = beam.L2 = beam.L3 = .0f;
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint lobe, inout S sg, const float wavelength, const uint lobeMask) {
        const bool hasDiffuseReflection = (lobeMask&(uint)LobeType::DiffuseReflection)!=0;

        weight = SpectrumUtils.rgbToSpectrum(albedo, wavelength);
        wo = sample_cosine_hemisphere_concentric(sampleNext2D(sg), pdf);
        lobe = (uint)LobeType::DiffuseReflection;

        return hasDiffuseReflection;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        return cosine_hemisphere_concentric_pdf(woLocal);
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
        const float cosTheta = sqrt(max(1e-2f, abs(woLocal.z)));
        return float2x2(cosTheta, .0f,
                        .0f, 1.f/cosTheta);
    }
};

struct PLTDiffuseBSDF : IMaterialInstance
{
    PLTDiffuseBxDF bxdf;
    uint32_t emissionSpectralId;
    float3 emissionRGB;

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
        // Unsupported
        return {};
    }

    bool sample<S : ISampleGenerator>(const ShadingData sd, inout S sg, out BSDFSample result, const float wavelength, const uint lobeMask = (uint)LobeType::All, const float3 woHint = .0f)
    {
        bool valid = bxdf.sample(sd.toLocal(sd.V), result.wo, result.pdf, result.weight, result.lobe, sg, wavelength, lobeMask);
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
        const bool isEmissive = emissionSpectralId != BasicMaterialData::no_spectral_profile;

        BSDFProperties p = {};
        p.emissionSpectralId = emissionSpectralId;
        p.flags = isEmissive ? (uint)BSDFProperties.Flags::IsEmissive : 0;
        p.emissionRGB = isEmissive ? emissionRGB : float3(.0f);

        p.albedo = bxdf.albedo;
        p.roughness = 1.f;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return (uint)LobeType::DiffuseReflection;
    }
};
