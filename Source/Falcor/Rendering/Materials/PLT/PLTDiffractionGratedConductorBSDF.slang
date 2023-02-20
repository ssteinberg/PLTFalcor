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
import Scene.Scene;
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
import Rendering.Materials.PLT.DiffractionGrating;
__exported import Rendering.Materials.PLT.PLTConductorBSDF;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTDiffractionGratedConductorBxDF
{
    PLTConductorBxDF base;
    DiffractionGrating grating;

    float3 reflect(const float3 wi) {
        return float3(-wi.xy, wi.z);
    }

    void encodeLobeType(int2 lobe, inout uint bsdfLobe) {
        const int2 sign = lobe<0 ? int2(0) : int2(1);
        lobe = min(abs(lobe), int2(7));

        bsdfLobe &= ~(uint)LobeType::MaterialSpecifc;
        bsdfLobe += ((lobe.y<<3) + lobe.x + (sign.y<<7) + (sign.x<<6))<<LobeTypeMaterialSpecificOffset;
    }
    int2 decodeLobeType(const uint bsdfLobe) {
        const int x = (int)bsdfLobe>>LobeTypeMaterialSpecificOffset;
        int2 lobe = int2(x&0x7, (x>>3)&0x7);
        lobe *= 2*int2((x>>6)&0x1,(x>>7)&0x1) - int2(1);
        return lobe;
    }

    void eval(const float3 toLight, const float3 toEye, const uint bsdfLobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool isDirect = (bsdfLobe&(uint)LobeType::Delta) != 0;

        const hwss_t lambdas = 1e-3f*beam.wavelengths;       // um
        const hwss_t k = M_2PI / lambdas;
        const hwss_t a = grating.alpha(toLight, k);
        const int2 lobe = decodeLobeType(bsdfLobe);
        const float3 toLightBeam = beam.toLocal(toLight);

        if (all(lobe==0) && any(a>.0f)) {
            // Evaluate base lobes
            base.eval(toLight, toEye, bsdfLobe, beam, flags);
            beam.scale(a);
        }
        else if (any(lobe!=0) && any(a<1.f) && isDirect) {
            const hwss_t m00 = SpectrumUtils.rgbToSpectrum(base.specular, beam.wavelengths);
            const hwss_t iorN = gScene.evalSpectrum(base.etaN, beam.wavelengths);
            const hwss_t iorK = gScene.evalSpectrum(base.etaK, beam.wavelengths);

            for (int j = 0; j < beam.hwss_comps; ++j) {
                const float2 ior = float2(iorN[j],iorK[j]) / base.extEta;
                const float4x4 M0 = MuellerFresnelRConductor(toLight.z, ior);

                // Evaluate diffraction lobes
                const float3 lobeWi = beam.toLocal(grating.diffract(toEye, lobe, lambdas[j]));
                // HWSS component 0 is assumed to be the sampled lobe, skip computing mutual coherent. This avoid numerics with very-coherent light..
                const float coh = j==0 ? 1.f : beam.mutualCoherenceAngular(lobeWi, toLightBeam);
                const float intensity = grating.lobeIntensity(lobe, toLight, lambdas[j]);

                beam.setSP(j, m00[j] * (1-a[j]) * coh * intensity * mul(M0, beam.getSP(j)));
            }
        }
        else {
            beam.setZero();
        }
    }

    float3kpdv partialDerivatives(const float3pdv wi, const DifferentialShadingGeometry dsg, const uint bsdfLobe, float wavelength)
    {
        const int2 lobe = decodeLobeType(bsdfLobe);
        if (all(lobe==0))
            return base.partialDerivatives(wi, dsg.n, bsdfLobe, wavelength);
        return grating.partialDerivatives(dsg, wi, lobe, wavelength);
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint bsdfLobe, inout S sg, const float wavelength, const uint lobeMask, const float3 woHint = .0f)
    {
        const bool hasReflection   = (lobeMask&(uint)LobeType::Reflection)!=0;
        const bool hasDirect       = (lobeMask&(uint)LobeType::Delta)!=0;
        const bool hasScatter      = (lobeMask&(uint)LobeType::NonDelta)!=0;
        if (!hasReflection || (!hasDirect && !hasScatter)) return false;

        const float lambdas = 1e-3f*wavelength;       // um
        const float k = M_2PI / lambdas;
        const float a = grating.alpha(wiLocal, k);

        const bool hasHint = hasDirect && any(woHint!=.0f);
        int2 lobe = 0;
        if (hasHint && a.x<1.f) {
            // Find closest lobe
            lobe = grating.closestLobeHint(wiLocal, woHint, a.x, lambdas.x);
        }

        bool isDirect = hasDirect;
        if (hasHint) {
            isDirect = all(lobe==0);
            pdf = 1.f;
        }
        else if (hasDirect && hasScatter) {
            const float pdfDirect = a;
            isDirect = pdfDirect==1.f || sampleNext1D(sg)<pdfDirect;
            pdf = isDirect ? pdfDirect : 1.f-pdfDirect;
        }

        if (isDirect) {
            lobe = 0;
            float basePdf;
            base.sample(wiLocal, wo, basePdf, weight, bsdfLobe, sg, wavelength, lobeMask);

            pdf *= basePdf;

            return true;
        }

        weight = base.weight(wiLocal, wo, wavelength);

        float2 lobePdf = 1.f;
        if (!hasHint) {
            lobe = grating.sampleLobe(wiLocal, wo, lobePdf, lambdas.x, sg);
        }

        wo = grating.diffract(wiLocal,lobe,lambdas.x);
        bsdfLobe = (uint)LobeType::DispersiveDeltaReflection;
        encodeLobeType(lobe, bsdfLobe);
        pdf *= lobePdf.x*lobePdf.y;

        return true;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        const float k = M_2PI / (1e-3f*wavelength);       // um^(-1)
        const float a = grating.alpha(wiLocal, k);
        const float pdfDirect = a.x;

        // Diffraction has no non-delta lobes, query base
        return base.pdf(wiLocal, woLocal, wavelength) * pdfDirect;
    }

    float weight(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        return base.weight(wiLocal, woLocal, wavelength);
    }

    hwss_t lambdaPdf(const float3 toLight, const float3 toEye, const uint bsdfLobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        const bool isDirect = (bsdfLobe&(uint)LobeType::Delta) != 0;

        const hwss_t lambdas = 1e-3f*wavelengths;       // um
        const hwss_t k = M_2PI / lambdas;
        const hwss_t a = grating.alpha(toLight, k);
        const int2 lobe = decodeLobeType(bsdfLobe);
        const float3 toLightBeam = beam.toLocal(toLight);

        if (any(lobe!=0) && any(a<1.f) && isDirect) {
            hwss_t ret;
            for (int j = 0; j < hwss_samples; ++j) {
                // Evaluate diffraction lobes
                const float3 lobeWi = beam.toLocal(grating.diffract(toEye, lobe, lambdas[j]));
                ret[j] = j==0 ? 1.f : beam.mutualCoherenceAngular(lobeWi, toLightBeam);
            }
            return ret;
        }

        // No wavelength-dependant sampling
        return 1.f;
    }

    float2x2 coherenceTransform(const float3 wiLocal, const float3 woLocal, const uint bsdfLobe) {
        const int2 lobe = decodeLobeType(bsdfLobe);
        if (all(lobe==0))
            return base.coherenceTransform(wiLocal, woLocal, bsdfLobe);
        return ident2();
    }
};

struct PLTDiffractionGratedConductorBSDF : IMaterialInstance
{
    PLTDiffractionGratedConductorBxDF bxdf;

    void eval(const ShadingData sd, const float3 toEye, const uint bsdfLobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        let gratingSd = bxdf.grating.localGratingShadingFrame(sd);
        beam.r = gratingSd.toLocal(beam.r);
        beam.t = gratingSd.toLocal(beam.t);

        const float3 wiLocal = gratingSd.toLocal(sd.V);
        const float3 woLocal = gratingSd.toLocal(toEye);
        // Rotate beam to the exitant frame (BSDF evaluation is done in that frame)
        beam.constructLocalFrame(woLocal);

        bxdf.eval(wiLocal, woLocal, bsdfLobe, beam, flags);

        // Transform coherence on interaction
        beam.transformCoherence(bxdf.coherenceTransform(wiLocal, woLocal, bsdfLobe));

        beam.r = gratingSd.fromLocal(beam.r);
        beam.t = gratingSd.fromLocal(beam.t);
    }

    float3kpdv partialDerivatives(const float3pdv wi, const DifferentialShadingGeometry dsg, const uint bsdfLobe, float wavelength)
    {
        return bxdf.partialDerivatives(wi, dsg, bsdfLobe, wavelength);
    }

    bool sample<S : ISampleGenerator>(const ShadingData sd, inout S sg, out BSDFSample result, const float wavelength, const uint lobeMask = (uint)LobeType::All, const float3 woHint = .0f)
    {
        let gratingSd = bxdf.grating.localGratingShadingFrame(sd);
        bool valid = bxdf.sample(gratingSd.toLocal(sd.V), result.wo, result.pdf, result.weight, result.lobe, sg, wavelength, lobeMask, gratingSd.toLocal(woHint));
        if (valid)
            result.wo = gratingSd.fromLocal(result.wo);
        return valid;
    }

    float pdf(const ShadingData sd, const float3 toLight, const float wavelength)
    {
        let gratingSd = bxdf.grating.localGratingShadingFrame(sd);
        return bxdf.pdf(gratingSd.toLocal(toLight), gratingSd.toLocal(sd.V), wavelength);
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
        p.flags = (uint)BSDFProperties.Flags::CanManifoldWalkReflective;

        // Approximate normal reflectance at 500nm wavelength
        const float iorN = gScene.evalSpectrum(bxdf.base.etaN, SpectrumUtils.meanWavelength);
        const float iorK = gScene.evalSpectrum(bxdf.base.etaK, SpectrumUtils.meanWavelength);
        // Approximate base-to-diffraction energy ratio of the grating at normal incidence and mean wavelength
        const float a = bxdf.grating.alpha(float3(0,0,1), M_2PI/(SpectrumUtils.meanWavelength*1e-3f));

        p.albedo = bxdf.base.specular * evalFresnelConductor(float2(iorN, iorK), 1.f);
        p.roughness = (1-a)*bxdf.base.gfs.roughness;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return (bxdf.base.gfs.isDeltaOnly() ? (uint)LobeType::DeltaReflection : (uint)LobeType::DeltaReflection | (uint)LobeType::ScatterReflection) | (uint)LobeType::DispersiveDeltaReflection;
    }
};
