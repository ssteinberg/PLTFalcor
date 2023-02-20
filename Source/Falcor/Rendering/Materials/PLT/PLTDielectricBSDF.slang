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
__exported import Rendering.Materials.PLT.GaussianSurface;
__exported import Rendering.Materials.PLT.Mueller;
import Rendering.PLT;
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTDielectricBxDF
{
    typedef GaussianSurface SurfaceType;

    float3 specular = float3(1.f);
    float3 transmission = float3(1.f);
    GaussianSurface gfs;
    float etaInt, etaExt;
    float dispersionB;

    hwss_t indexOfRefraction(hwss_t k) {
        const hwss_t iors = hwss_t(etaInt) + dispersionB*sqr(k*M_1_2PI);
        return iors/etaExt;
    }
    float indexOfRefraction(float k) {
        const float iors = etaInt + dispersionB*sqr(k*M_1_2PI);
        return iors/etaExt;
    }

    bool isDispersive() { return dispersionB!=.0f; }

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }
    float3 refract(const float3 wi, const float cosThetaT, const float eta) {
        const float scale = cosThetaT < 0 ? 1/eta : eta;
        return float3(-scale*wi.xy, cosThetaT);
    }
    inline float3 scattered_wo(const float3 wo, const float eta) {
        const float scale = wo.z > 0 ? 1/eta : eta;
        const float2 xy = wo.xy * scale;
        const float l2 = dot(xy,xy);

        return l2>1 ? float3(.0f) : float3(xy, -sign(wo.z)*sqrt(max(0,1-l2)));
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool isReflection = toLight.z*toEye.z > .0f;
        const bool isScatter = (lobe&(uint)LobeType::NonDelta)!=0;
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const bool hasTransmission = (lobe&(uint)LobeType::Transmission)!=0;
        const bool hasReflection = (lobe & (uint)LobeType::Reflection) != 0;
        if (toLight.z*toEye.z == 0 || (!isScatter && !isDirect) || (!hasTransmission && !isReflection) || (!hasReflection && isReflection)) {
            beam.setZero();
            return;
        }

        const hwss_t k = M_2PI / (1e-3f*beam.wavelengths);       // um^(-1)
        const hwss_t m00 = isReflection ? SpectrumUtils.rgbToSpectrum(specular, beam.wavelengths) : SpectrumUtils.rgbToSpectrum(transmission, beam.wavelengths);

        const hwss_t eta = indexOfRefraction(k);
        const hwss_t relEta2 = sqr(toEye.z>.0f ? eta : 1.f/eta);
        const float3 toEyeUp = isReflection ? toEye : scattered_wo(toEye, eta.x);
        const float3 toLightBeam = beam.toLocal(toLight);

        const hwss_t a = gfs.alpha(toLight, toEyeUp, k);

        if (isScatter) {
            const float3 h = toLight + toEyeUp;
            const float3 m = normalize(h);
            const float LdotH = max(0, dot(toLight, m));

            const float2x2 Q = beam.Q();
            const float2x2 invTheta = beam.invTheta(1.f);

            for (int j = 0; j < beam.hwss_comps; ++j) {
                const float4 SP = beam.getSP(j);
                const float J = isReflection ? 1.f : relEta2[j];
                const float D = gfs.eval(k[j], invTheta, Q, h);
                const float4x4 M1 = MuellerFresnelDielectric(sign(toLight.z)*LdotH, eta[j], isReflection);

                const float4 newSP = m00[j] * (1 - a[j]) * J * abs(toLight.z) * D * mul(M1, SP);
                beam.setSP(j, newSP);
            }
        } else {
            for (int j = 0; j < beam.hwss_comps; ++j) {
                const float4 SP = beam.getSP(j);
                const float J = isReflection ? 1.f : relEta2[j];
                const float4x4 M0 = MuellerFresnelDielectric(toLight.z, eta[j], isReflection);

                float coh = 1.f;
                if (!isReflection) {
                    float cosThetaT;
                    const float Fd = evalFresnelDielectric(eta[j],toEye.z,cosThetaT);
                    const float3 lobeWo = beam.toLocal(refract(toEye, cosThetaT, eta[j]));
                    // HWSS component 0 is assumed to be the sampled lobe, skip computing mutual coherent. This avoid numerics with very-coherent light..
                    coh = j==0 ? 1.f : beam.mutualCoherenceAngular(lobeWo, toLightBeam);
                }

                const float4 newSP = m00[j] * a[j] * coh * J * mul(M0, SP);
                beam.setSP(j, newSP);
            }
        }
    }

    float3kpdv partialDerivatives(const float3pdv wi, const float3pdv n, const uint lobe, float wavelength)
    {
        const bool isReflection = (lobe&(uint)LobeType::Reflection)!=0;
        const bool isTransmission = (lobe&(uint)LobeType::Transmission)!=0;

        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float eta = indexOfRefraction(k);

        if (isTransmission) {
            // eta = etaA + dispersionB / lamda^2
            // const float lambda  = wavelength;
            // const float lambda3 = sqr(lambda) * lambda;
            // const float dEta_dLambda    = -2.f * dispersionB / lambda3;
            // const float dInvEta_dLambda = -dEta_dLambda / sqr(eta);
            return refractDerivatives(wi, n, eta);//, dEta_dLambda, dInvEta_dLambda);
        }
        else
            return reflectDerivatives(wi,n);
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint lobe, inout S sg, const float wavelength, const uint lobeMask = (uint)LobeType::All)
    {
        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float a = gfs.alpha(wiLocal, k);
        const float eta = indexOfRefraction(k);

        const bool hasReflection   = (lobeMask&(uint)LobeType::Reflection)!=0;
        const bool hasTransmission = (lobeMask&(uint)LobeType::Transmission)!=0;
        const bool hasDirect       = (lobeMask&(uint)LobeType::Delta)!=0;
        const bool hasScatter      = (lobeMask&(uint)LobeType::NonDelta)!=0;

        if ((!hasReflection && !hasTransmission) ||
            (!hasDirect && !hasScatter))
            return false;

        const float pdfDirect = hasDirect && hasScatter ? a.x : hasDirect ? 1.f : .0f;
        bool isReflection;
        const bool isDirect = pdfDirect==1.f || sampleNext1D(sg)<pdfDirect;
        pdf = (hasDirect && hasScatter) ? (isDirect ? pdfDirect : 1.f-pdfDirect) : 1.f;

        if (isDirect) {
            float cosThetaT;
            const float Fd = evalFresnelDielectric(eta.x,wiLocal.z,cosThetaT);
            isReflection = hasReflection ? Fd>0 && sampleNext1D(sg) <= Fd : false;

            wo = isReflection ? reflect(wiLocal) : refract(wiLocal,cosThetaT,eta.x);
            pdf *= (hasReflection && hasTransmission) ? (isReflection ? Fd : 1.f-Fd) : 1.f;
            lobe = isReflection ? (uint)LobeType::DeltaReflection :
                (uint)(isDispersive() ? LobeType::DispersiveDeltaTransmission : LobeType::DeltaTransmission);
        } else {
            float surfPdf;
            wo = gfs.sample(wiLocal, sg, k.x, surfPdf);
            pdf *= surfPdf;

            const float3 h = wiLocal + wo;
            const float3 m = normalize(h);
            const float F = evalFresnelDielectric(eta.x,sign(wiLocal.z)*dot(wiLocal,m));

            isReflection = hasReflection ? F>0 && sampleNext1D(sg) <= F : false;
            if (!isReflection)
                wo = scattered_wo(wo,eta.x);

            pdf *= (hasReflection && hasTransmission) ? (isReflection ? F : 1.f-F) : 1.f;
            lobe = isReflection ? (uint)LobeType::ScatterReflection : (uint)LobeType::ScatterTransmission;
        }
        const float m00 = isReflection ? SpectrumUtils.rgbToSpectrum(specular, wavelength) : SpectrumUtils.rgbToSpectrum(transmission, wavelength);
        weight = m00;

        return
            ( isReflection && wiLocal.z*wo.z<=0.0f ? false :
             !isReflection && wiLocal.z*wo.z>=0.0f ? false :
              true);
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float a = gfs.alpha(wiLocal, k);
        const float eta = indexOfRefraction(k);
        const float pdfDirect = a.x;

        const bool isReflection = wiLocal.z * woLocal.z > 0.0f;
        const float3 wo = isReflection ? woLocal : scattered_wo(woLocal,eta.x);
        const float3 h = wiLocal + wo;
        const float3 m = normalize(h);
        const float F = evalFresnelDielectric(eta.x,sign(wiLocal.z)*dot(wiLocal,m));
        const float pdfF = isReflection ? F : 1.f-F;

        // PDF of non-direct, reflected/transmitted lobe
        return (1.f-pdfDirect) * pdfF * gfs.pdf(wiLocal, wo, k.x);
    }

    float weight(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        const bool isReflection = wiLocal.z * woLocal.z > 0.0f;
        const float m00 = isReflection ? SpectrumUtils.rgbToSpectrum(specular, wavelength) : SpectrumUtils.rgbToSpectrum(transmission, wavelength);
        return m00;
    }

    hwss_t lambdaPdf(const float3 toLight, const float3 toEye, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        const bool isReflection = toLight.z*toEye.z > .0f;
        const bool isScatter = (lobe&(uint)LobeType::NonDelta)!=0;
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;

        const hwss_t k = M_2PI / (1e-3f*wavelengths);       // um^(-1)
        const hwss_t eta = indexOfRefraction(k);
        const float3 toLightBeam = beam.toLocal(toLight);

        if (isDirect && !isReflection) {
            hwss_t ret = .0f;
            for (int j = 0; j < hwss_samples; ++j) {
                float cosThetaT;
                const float Fd = evalFresnelDielectric(eta[j],toEye.z,cosThetaT);
                const float3 lobeWo = beam.toLocal(refract(toEye, cosThetaT, eta[j]));
                ret[j] = j==0 ? 1.f : beam.mutualCoherenceAngular(lobeWo, toLightBeam);
            }
            return ret;
        }

        if (isScatter) {
            hwss_t ret = .0f;
            for (int j = 0; j < hwss_samples; ++j) {
                const float3 wo = isReflection ? toLight : scattered_wo(toLight,eta[j]);
                ret[j] = gfs.pdf(toEye, wo, k[j]);
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

struct PLTDielectricBSDF : IMaterialInstance
{
    PLTDielectricBxDF bxdf;

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
        const bool forceReflection = dot(sd.V, woHint)>.0f;
        const bool forceTransmission = dot(sd.V, woHint)<.0f;
        const uint lobes = (forceReflection ? (uint)LobeType::Reflection :
                            forceTransmission ? (uint)LobeType::Transmission :
                            (uint)LobeType::All) & lobeMask;

        bool valid = bxdf.sample(sd.toLocal(sd.V), result.wo, result.pdf, result.weight, result.lobe, sg, wavelength, lobes);
        result.wo = sd.fromLocal(result.wo);
        return valid;
    }

    float pdf(const ShadingData sd, const float3 toLight, const float wavelength)
    {
        return bxdf.pdf(sd.toLocal(toLight), sd.toLocal(sd.V), wavelength);
    }

    hwss_t lambdaPdf(const ShadingData sd, const float3 wo, const uint lobe, PLTBeam beam, const hwss_t wavelengths)
    {
        beam.r = sd.toLocal(beam.r);
        beam.t = sd.toLocal(beam.t);

        const hwss_t ret = bxdf.lambdaPdf(sd.toLocal(sd.V), sd.toLocal(wo), lobe, beam, wavelengths);

        return ret;
    }

    BSDFProperties getProperties(const ShadingData sd)
    {
        BSDFProperties p = {};
        p.flags = (uint)BSDFProperties.Flags::IsTransmissive |
                   (bxdf.gfs.q<QcutoffForMS ? (uint)BSDFProperties.Flags::CanManifoldWalkTransmissive : 0);

        // Approximate reflectivity at normal incidence and mean wavelength
        const float ior = bxdf.indexOfRefraction(M_2PI/(SpectrumUtils.meanWavelength*1e-3f));

        p.albedo = bxdf.specular * evalFresnelDielectric(ior, 1.f);
        p.roughness = bxdf.gfs.roughness;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        const uint deltaTransmission = (uint)(bxdf.isDispersive() ? LobeType::DispersiveDeltaTransmission : LobeType::DeltaTransmission);
        const uint scatterTransmission = (uint)LobeType::ScatterTransmission;

        return bxdf.gfs.isDeltaOnly() ?
            (uint)LobeType::DeltaReflection | deltaTransmission :
            (uint)LobeType::DeltaReflection | deltaTransmission | (uint)LobeType::ScatterReflection | scatterTransmission;
    }
};
