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
__exported import Rendering.Materials.PLT.Birefringence;
import Rendering.PLT;
import Utils.Color.ColorHelpers;
import Utils.Color.SpectrumUtils;
import Utils.HWSS;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTThinDielectricBxDF
{
    static const float etaExt = 1.f;
    float2 opticAxis_xy = {.15,.04};
    float etaAvg;
    float tau;
    float birefringence;

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }
    float3 opticAxis() {
        const float2 xy = opticAxis_xy;
        const float opticAxisZ = sqrt(max(.0f,1.f-dot(xy,xy)));
        return float3(xy,opticAxisZ);
    }

    void handle_birefringence(inout PLTBeam beam, const float3 wi, hwss_t k, bool refl) {
        const float3 OA = opticAxis();
        const float phii = atan2(wi.y,wi.x);
        const float phiA = atan2(OA.y, OA.x)-phii;

        const float3 I = float3(0,abs(wi.z),sqrt(1.f-sqr(wi.z)));
        float3 A = float3(cos(phiA),0,sin(phiA));
        A *= sqrt(1-sqr(OA.z));
        A.y = sign(wi.z) * OA.z;
        const float3 A2 = float3(A.x,-A.y,A.z);
        const float3 Z = beam.toLocal(float3(cos(phii),sin(phii),0));

        const float ei = etaExt;
        const float eo = etaAvg - .5f*birefringence;
        const float ee = etaAvg + .5f*birefringence;
        const float tauum = tau * 1e+3; // in micron

        // Downwards and upwards propagating ordinary and extraordinary vectors in the slab
        float3 Io, Io2, Ie, Ie2;
        // Effeective refractive indices of the extraordinary vectors
        float e_eff, e_eff2;
        Birefringence.vectors_in_slab(I, ei,eo,ee, A, Io, Io2, Ie, Ie2, e_eff, e_eff2);

        // Fresnel coefficients
        float rss, rsp, tso, tse, rps, rpp, tpo, tpe;
        float roo, roe, tos, top, reo, ree, tes, tep;
        Birefringence.fresnel_iso_aniso(I.y,I.z, ei,eo,ee, A,  rss, rsp, tso, tse, rps, rpp, tpo, tpe);
        Birefringence.fresnel_aniso_iso(I.y,I.z, ei,eo,ee, A2, roo, roe, tos, top, reo, ree, tes, tep);
        const float ss = tso*tos + tse*tes;
        const float sp = tso*top + tse*tep;
        const float ps = tpo*tos + tpe*tes;
        const float pp = tpo*top + tpe*tep;

        // Offsets
        const float Ioz =  abs(tauum / Io.y)  * Io.z;
        const float Iez =  abs(tauum / Ie.y)  * Ie.z;
        // OPLs
        const float OPLo = abs(tauum / Io.y)  * eo;
        const float OPLe = abs(tauum / Ie.y)  * e_eff;

        const float oez = Ioz-Iez;

        const hwss_t mutual_coh = beam.mutualCoherence(k, oez*Z);   // in micron
        const hwss_t t = mutual_coh * 2.f*sin(-k*(ei*oez*I.z+OPLo-OPLe));    // Interference term, modulated by mutual coherence

        const hwss_t Lx = .5f * (beam.L + beam.L1);
        const hwss_t Ly = .5f * (beam.L - beam.L1);
        const hwss_t sqrtLxLy = sqrt(Lx * Ly);

        const hwss_t nLx = max(.0f, sqr(ss) * Lx + sqr(ps) * Ly + ss * ps * t * sqrtLxLy);
        const hwss_t nLy = max(.0f, sqr(sp) * Lx + sqr(pp) * Ly + sp * pp * t * sqrtLxLy);

        const hwss_t newL = nLx + nLy;
        const hwss_t SPnormalizer = all(beam.L>1e-6f && isfinite(newL)) ? newL / beam.L : hwss_t(.0f);
        beam.L   = all(isfinite(newL)) ? newL : hwss_t(.0f);
        beam.L1  = all(isfinite(newL)) ? nLx - nLy : hwss_t(.0f);
        beam.L2 *= SPnormalizer;
        beam.L3 *= SPnormalizer;
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const float eta = etaAvg/etaExt;

        const bool isReflection = toLight.z * toEye.z > 0.0f;
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const bool hasTransmission = (lobe&(uint)LobeType::Transmission)!=0;
        const bool hasReflection = (lobe&(uint)LobeType::Reflection)!=0;
        if ((isReflection && eta == 1.0f) || toLight.z * toEye.z == 0 || !isDirect || (!hasTransmission && !isReflection) || (!hasReflection && isReflection)) {
            beam.setZero();
            return;
        }

        const hwss_t k = M_2PI / (1e-3f*beam.wavelengths);       // um^(-1)
        const float costheta_i = abs(toLight.z);

        // Account for all internal reflections
        const float4x4 R = MuellerFresnelRDielectric(costheta_i, eta),
            iR = invOneMinusMuellerFresnelRDielectric(costheta_i, eta),
            T = MuellerFresnelTDielectric(costheta_i, eta);
        const float4x4 M = isReflection ?
                (iR[0][0]>0 ? (R + mul(mul(T, R), mul(iR, T))) : R) :
                (iR[0][0]>0 ? mul(T, mul(iR, T))               : mul(T,T));

        // Birefringence
        if (birefringence>.0f && !isReflection)
            handle_birefringence(beam, toLight, k, isReflection);
        for (int j = 0; j < beam.hwss_comps; ++j)
            beam.setSP(j, mul(M, beam.getSP(j)));
    }

    float3kpdv partialDerivatives(const float3pdv wi, const float3pdv n, const uint lobe, float wavelength)
    {
        const bool isReflection = (lobe&(uint)LobeType::Reflection)!=0;
        const bool isTransmission = (lobe&(uint)LobeType::Transmission)!=0;
        if (isTransmission) {
            float3pdv wo = wi;
            wo.flip();
            return { wo.v, wo.ddu, wo.ddv, float3(.0f) };
        }
        else
            return reflectDerivatives(wi,n);
    }

    bool sample<S : ISampleGenerator>(float3 wiLocal, out float3 wo, out float pdf, out float weight, out uint lobe, inout S sg, const float wavelength, const uint lobeMask = (uint)LobeType::All)
    {
        const bool hasReflection   = (lobeMask&(uint)LobeType::Reflection)!=0;
        const bool hasTransmission = (lobeMask&(uint)LobeType::Transmission)!=0;

        if (!hasReflection && !hasTransmission)
            return false;

        const float eta = etaAvg/etaExt;
        const float Fd = evalFresnelDielectric(eta,abs(wiLocal.z));
        const bool isReflection = hasReflection ? Fd>0 && sampleNext1D(sg) <= Fd : false;

        wo   = isReflection ? reflect(wiLocal) : -wiLocal;
        weight = 1.f;
        pdf  = hasReflection && hasTransmission ?
               (isReflection ? Fd : 1.f-Fd) : 1.f;
        lobe = isReflection ? (uint)LobeType::DeltaReflection : (uint)LobeType::DeltaTransmission;

        return true;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        // No non-delta lobes
        return .0f;
    }

    hwss_t lambdaPdf(const float3 wiLocal, const float3 woLocal, const uint lobe, const PLTBeam beam, const hwss_t wavelengths)
    {
        // No wavelength-dependant sampling
        return 1.f;
    }

    float2x2 coherenceTransform(const float3 wiLocal, const float3 woLocal, const uint lobe) {
        return ident2();
    }
};

struct PLTThinDielectricBSDF : IMaterialInstance
{
    PLTThinDielectricBxDF bxdf;

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
        BSDFProperties p = { };
        p.flags = (uint)BSDFProperties.Flags::IsTransmissive | (uint)BSDFProperties.Flags::CanManifoldWalkReflective | (uint)BSDFProperties.Flags::CanManifoldWalkTransmissive;

        p.albedo = 1.f;
        p.roughness = .0f;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return (uint)LobeType::DeltaReflection | (uint)LobeType::DeltaTransmission;
    }
};
