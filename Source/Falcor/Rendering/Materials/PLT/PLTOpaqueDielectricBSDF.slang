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
import Utils.Color.ColorHelpers;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import Utils.Math.MathHelpers;
import Rendering.Materials.Fresnel;
__exported import Utils.Sampling.SampleGeneratorInterface;

struct PLTOpaqueDielectricBxDF
{
    typedef FractalSurface SurfaceType;

    float3 albedo = float3(1.f);
    FractalSurface gfs;

    static const float meank = M_2PI / (SpectrumUtils.meanWavelength*1e-3f);

    float3 reflect(const float3 wi) {
        return float3(-wi.x, -wi.y, wi.z);
    }

    void eval(const float3 toLight, const float3 toEye, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0)
    {
        const bool hasReflection = (lobe & (uint)LobeType::Reflection) != 0;
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const bool isScatter = (lobe&(uint)LobeType::NonDelta)!=0;
        if ((!isScatter && !isDirect) || !hasReflection) {
            beam.setZero();
            return;
        }

        const hwss_t m00 = SpectrumUtils.rgbToSpectrum(albedo, beam.wavelengths);
        const float a = gfs.alpha(toLight, toEye, meank);

        float M = a;
        if (isScatter) {
            const float3 h = toLight + toEye;
            const float D = gfs.eval(meank, h);

            M = (1 - a) * abs(toLight.z) * D;
        }

        for (int j = 0; j < beam.hwss_comps; ++j) {
            const float4 SP = beam.getSP(j);
            beam.setSP(j, M * m00[j] * SP);
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
        const bool hasScatter      = (lobeMask&(uint)LobeType::NonDelta)!=0;
        if (!hasReflection || (!hasDirect && !hasScatter)) return false;

        const float a = gfs.alpha(wiLocal, meank);
        const float m00 = SpectrumUtils.rgbToSpectrum(albedo, wavelength);

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
            wo = gfs.sample(wiLocal, sg, meank, surfPdf);
            pdf *= surfPdf;
            lobe = (uint)LobeType::ScatterReflection;
        }

        return true;
    }

    float pdf(const float3 wiLocal, const float3 woLocal, const float wavelength)
    {
        const float a = gfs.alpha(wiLocal, meank);

        const float pdfDirect = a.x;
        return (1-pdfDirect) * gfs.pdf(wiLocal, woLocal, meank);
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
        const bool isDirect = (lobe&(uint)LobeType::Delta)!=0;
        const float cosTheta = sqrt(max(1e-2f, abs(woLocal.z)));
        return isDirect ? ident2() :
               float2x2(cosTheta, .0f,
                        .0f, 1.f/cosTheta);
    }
};

struct PLTOpaqueDielectricBSDF : IMaterialInstance
{
    PLTOpaqueDielectricBxDF bxdf;

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

        p.albedo = bxdf.albedo;
        p.roughness = bxdf.gfs.roughness;

        return p;
    }

    uint getLobes(const ShadingData sd)
    {
        return bxdf.gfs.isDeltaOnly() ? (uint)LobeType::DeltaReflection :
            (uint)LobeType::DeltaReflection | (uint)LobeType::ScatterReflection;
    }
};
