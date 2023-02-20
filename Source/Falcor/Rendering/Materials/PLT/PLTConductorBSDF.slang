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
__exported import Rendering.Materials.PLT.FractalSurface;
__exported import Rendering.Materials.PLT.Mueller;
import Rendering.PLT;
import Scene.Scene;
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTConductorBxDF
{
    typedef FractalSurface SurfaceType;

    float3 specular;
    SurfaceType gfs;
    uint etaN, etaK;
    float extEta;

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool isScatter = (lobe&(uint)LobeType::ScatterReflection)!=0;
        const bool isDirect = (lobe&(uint)LobeType::DeltaReflection)!=0;
        const bool hasReflection = (lobe & (uint)LobeType::Reflection) != 0;
        if ((!isScatter && !isDirect) || !hasReflection) {
            beam.setZero();
            return;
        }

        const hwss_t k = M_2PI / (1e-3f*beam.wavelengths);       // um^(-1)
        const hwss_t a = gfs.alpha(toLight, toEye, k);
        const hwss_t m00 = SpectrumUtils.rgbToSpectrum(specular, beam.wavelengths);

        const float3 h = toLight + toEye;
        const float3 m = normalize(h);
        const float LdotH = max(.0f, dot(toLight, m));
        const hwss_t iorN = gScene.evalSpectrum(etaN, beam.wavelengths);
        const hwss_t iorK = gScene.evalSpectrum(etaK, beam.wavelengths);

        for (int j = 0; j < beam.hwss_comps; ++j) {
            const float4 SP = beam.getSP(j);
            float4 newSP = .0f;

            const float2 ior = float2(iorN[j],iorK[j]) / extEta;
            if (isScatter) {
                const float4x4 M1 = MuellerFresnelRConductor(LdotH, ior);
                const float D = gfs.eval(k[j], h);
                newSP = (1 - a[j]) * abs(toLight.z) * D * mul(M1, SP);
            }
            else {
                const float4x4 M0 = MuellerFresnelRConductor(toLight.z, ior);
                newSP = a[j] * mul(M0, SP);
            }
            newSP *= m00[j];
            beam.setSP(j, newSP);
        }
    }

    float3kpdv partialDerivatives(const float3pdv wi, const float3pdv n, const uint lobe, float wavelength)
    {
        return reflectDerivatives(wi,n);
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint lobe, inout S sg, const float wavelength, const uint lobeMask)
    {
        const bool hasReflection   = (lobeMask&(uint)LobeType::Reflection)!=0;
        const bool hasDirect       = (lobeMask&(uint)LobeType::Delta)!=0;
        const bool hasScatter      = (lobeMask&(uint)LobeType::NonDelta)!=0;
        if (!hasReflection || (!hasDirect && !hasScatter)) return false;

        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float a = gfs.alpha(wiLocal, k);
        const float m00 = SpectrumUtils.rgbToSpectrum(specular, wavelength);

        pdf = 1.f;
        bool isDirect = hasDirect;
        if (hasDirect && hasScatter) {
            const float pdfDirect = a;
            isDirect = pdfDirect==1.f || sampleNext1D(sg)<pdfDirect;
            pdf = isDirect ? pdfDirect : 1.f-pdfDirect;
        }
        weight = m00;

        if (isDirect) {
            wo = reflect(wiLocal);
            lobe = (uint)LobeType::DeltaReflection;
        }
        else {
            float surfPdf;
            wo = gfs.sample(wiLocal, sg, k.x, surfPdf);
            pdf *= surfPdf;
            lobe = (uint)LobeType::ScatterReflection;
        }

        return true;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float a = gfs.alpha(wiLocal, k);

        const float pdfDirect = a.x;
        return (1-pdfDirect) * gfs.pdf(wiLocal, woLocal, k.x);
    }

    float weight(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        return SpectrumUtils.rgbToSpectrum(specular, wavelength);
    }

    hwss_t lambdaPdf(const float3 toLight, const float3 toEye, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        const bool isScatter = (lobe&(uint)LobeType::NonDelta)!=0;
        const hwss_t k = M_2PI / (1e-3f*wavelengths);       // um^(-1)

        if (isScatter) {
            hwss_t ret = .0f;
            for (int j = 0; j < hwss_samples; ++j) {
                ret[j] = gfs.pdf(toEye, toLight, k[j]);
            }
            return ret;
        }

        // No wavelength-dependant sampling
        return 1.f;
    }

    float2x2 coherenceTransform(const float3 wiLocal, const float3 woLocal, const uint lobe) {
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const float cosTheta = sqrt(max(1e-2f, abs(woLocal.z)));
        return isDirect ? ident2() :
               float2x2(cosTheta, .0f,
                        .0f, 1.f/cosTheta);
    }
};

struct PLTConductorBSDF : IMaterialInstance
{
    PLTConductorBxDF bxdf;

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
        if (bxdf.gfs.q < QcutoffForMS)
            p.flags = (uint)BSDFProperties.Flags::CanManifoldWalkReflective;

        // Approximate normal reflectance at 500nm wavelength
        const float iorN = gScene.evalSpectrum(bxdf.etaN, SpectrumUtils.meanWavelength);
        const float iorK = gScene.evalSpectrum(bxdf.etaK, SpectrumUtils.meanWavelength);

        p.albedo = bxdf.specular * evalFresnelConductor(float2(iorN, iorK), 1.f);
        p.roughness = bxdf.gfs.roughness;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return bxdf.gfs.isDeltaOnly() ? (uint)LobeType::DeltaReflection :
            (uint)LobeType::DeltaReflection | (uint)LobeType::ScatterReflection;
    }
};
