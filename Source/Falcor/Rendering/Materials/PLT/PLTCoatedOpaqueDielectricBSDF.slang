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
__exported import Rendering.Materials.PLT.Interference;
import Rendering.PLT;
import Scene.Scene;
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTCoatedOpaqueDielectricBxDF
{
    typedef FractalSurface SurfaceType;

    float3 albedo;
    SurfaceType gfs;
    float extEta;
    float coatIOR;
    float tau;

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }
    float3 refractCoat(const float3 wi, const float eta, const float cosThetaT) {
        const float scale = cosThetaT < 0 ? 1/eta : eta;
        return float3(-scale*wi.xy, cosThetaT);
    }

    bool hasCoating() { return tau>.0f; }
    float coatEta() {
        static float minTau = .05;
        return lerp(extEta, coatIOR, clamp(tau,0,minTau)/minTau);
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool isReflection = toLight.z * toEye.z > 0.0f;
        const bool isScatter = (lobe&(uint)LobeType::ScatterReflection)!=0;
        const bool isDirect = (lobe&(uint)LobeType::DeltaReflection)!=0;

        const float coatior = coatEta();
        const float eta1 = coatior / extEta;

        float cosThetaTin;
        evalFresnelDielectric(eta1,toLight.z,cosThetaTin);
        const float3 wiIn = -refractCoat(toLight,eta1,cosThetaTin);
        float3 woIn = reflect(wiIn);
        if (!isDirect) {
            float cosThetaTout;
            evalFresnelDielectric(eta1,toEye.z,cosThetaTout);
            woIn = -refractCoat(toEye,eta1,cosThetaTout);
        }
        if (!isReflection || (!isScatter && !isDirect) || wiIn.z<=.0f || woIn.z<=.0f) {
            beam.setZero();
            return;
        }

        const hwss_t k = M_2PI / (1e-3f*beam.wavelengths);       // um^(-1)
        const hwss_t a = gfs.alpha(wiIn, woIn, k);
        const hwss_t m00 = SpectrumUtils.rgbToSpectrum(albedo, beam.wavelengths);

        const float3 h = wiIn + woIn;
        const float3 m = normalize(h);
        const float LdotH = max(0, dot(wiIn, m));

        const float3 Z = beam.toLocal(float3(0,0,1));
        const hwss_t mutual_coh = beam.mutualCoherence(k, tau*Z);   // in micron
        const hwss_t phases = phaseShift(coatior, 2.f*tau/wiIn.z, k);

        const float4x4 MiT = MuellerFresnelTDielectric(toLight.z, eta1);
        const float4x4 MoT = MuellerFresnelTDielectric(-woIn.z, eta1);
        const float4x4 M = mul(MiT, MoT);

        for (int j = 0; j < beam.hwss_comps; ++j) {
            const float4 SP = beam.getSP(j);

            float4 newSP = m00[j] * mul(M, SP);
            float4 SPreflcoat;
            if (isScatter) {
                const float4x4 MiR = MuellerFresnelRDielectric(LdotH, eta1);
                const float D = gfs.eval(k[j], h);
                newSP *= (1 - a[j]) * abs(toLight.z) * D;
                SPreflcoat = (1 - a[j]) * abs(toLight.z) * D * mul(MiR, SP);
            }
            else {
                const float4x4 MiR = MuellerFresnelRDielectric(toLight.z, eta1);
                newSP *= a[j];
                SPreflcoat = a[j] * mul(MiR, SP);
            }

            newSP = interfere(newSP, SPreflcoat, phases[j], phases[j], mutual_coh[j]);

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
        if (!hasReflection || (!hasDirect && !hasScatter) || wiLocal.z<=.0f) return false;

        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float eta1 = coatEta() / extEta;

        float cosThetaT;
        const float Fd = evalFresnelDielectric(eta1,wiLocal.z,cosThetaT);

        // Reflect of coat?
        const bool isReflCoat = Fd == .1f || sampleNext1D(sg)<Fd;
        weight = 1.f;
        pdf = isReflCoat ? Fd : 1.f-Fd;
        if (isReflCoat) {
            wo = reflect(wiLocal);
            lobe = (uint)LobeType::DeltaReflection;
            return true;
        }

        // Enter coat

        const float3 wiIn = -refractCoat(wiLocal,eta1,cosThetaT);
        if (wiIn.z==.0f)
            return false;

        weight = SpectrumUtils.rgbToSpectrum(albedo, wavelength);

        const hwss_t a = gfs.alpha(wiIn, k);
        const float pdfDirect = hasDirect && hasScatter ? a.x : hasDirect ? 1.f : .0f;
        const bool isDirect = pdfDirect==1.f || sampleNext1D(sg)<pdfDirect;
        if (hasDirect && hasScatter)
            pdf *= isDirect ? pdfDirect : 1.f-pdfDirect;

        if (isDirect) {
            wo = reflect(wiLocal);
            lobe = (uint)LobeType::DeltaReflection;
        }
        else {
            float surfPdf;
            float3 woIn = gfs.sample(wiIn, sg, k.x, surfPdf);
            pdf *= surfPdf;

            float cosThetaT1;
            evalFresnelDielectric(eta1,-woIn.z,cosThetaT1);

            wo = refractCoat(-woIn,eta1,cosThetaT1);
            lobe = (uint)LobeType::ScatterReflection;
        }

        return wiLocal.z*wo.z > .0f;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        if (wiLocal.z<=.0f || woLocal.z<=.0f)
            return .0f;

        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float eta1 = coatEta() / extEta;

        float cosThetaT, cosThetaT1;
        const float Fd = evalFresnelDielectric(eta1,wiLocal.z,cosThetaT);
        evalFresnelDielectric(eta1,woLocal.z,cosThetaT1);

        const float3 wiIn = -refractCoat(wiLocal,eta1,cosThetaT);
        const float3 woIn = -refractCoat(woLocal,eta1,cosThetaT1);
        const hwss_t a = gfs.alpha(wiIn, k);

        // PDF of non-direct, coat-penetrating lobe
        return wiIn.z*woIn.z==.0f ? .0f :
                                    (1.f-a.x) * (1.f-Fd) * gfs.pdf(wiIn, woIn, k.x);
    }

    hwss_t lambdaPdf(const float3 toLight, const float3 toEye, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        const bool isScatter = (lobe&(uint)LobeType::NonDelta)!=0;
        const hwss_t k = M_2PI / (1e-3f*wavelengths);       // um^(-1)
        const float eta1 = coatEta() / extEta;

        if (isScatter) {
            float cosThetaT, cosThetaT1;
            evalFresnelDielectric(eta1,toEye.z,cosThetaT);
            evalFresnelDielectric(eta1,toLight.z,cosThetaT1);

            const float3 wiIn = -refractCoat(toEye,eta1,cosThetaT);
            const float3 woIn = -refractCoat(toLight,eta1,cosThetaT1);

            hwss_t ret = .0f;
            for (int j = 0; j < hwss_samples; ++j) {
                ret[j] = gfs.pdf(wiIn, woIn, k[j]);
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

struct PLTCoatedOpaqueDielectricBSDF : IMaterialInstance
{
    PLTCoatedOpaqueDielectricBxDF bxdf;

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

        // TODO: Better albedo approximation
        p.albedo = bxdf.albedo;
        p.roughness = bxdf.gfs.roughness;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        if (bxdf.gfs.isDeltaOnly())
            return (uint)LobeType::DeltaReflection;
        return (uint)LobeType::DeltaReflection | (uint)LobeType::ScatterReflection;
    }
};
