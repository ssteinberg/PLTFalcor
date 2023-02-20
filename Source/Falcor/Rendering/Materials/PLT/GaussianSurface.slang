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

import Utils.Math.MathHelpers;
import Utils.HWSS;
import Utils.Sampling.SampleGeneratorInterface;

/** This class implements sampling and evaluation of an surface with Gaussian PSD statistics.
*/
struct GaussianSurface
{
    static const float roughnessScaleToSigma2 = 2500.f;
    float sigma2, q;

    float roughnessToSigma2(float PLTroughness) {
        return pow(clamp(1.f - .5f*PLTroughness,.0f,1.f), 28.f) * roughnessScaleToSigma2;
    }
    property roughness : float {
        get {
            return 2.f * (1.f - pow(sigma2/roughnessScaleToSigma2, 1.f/28.f));
        }
    }

    __init(float PSDroughness)
    {
        // Remap to something that feels like "roughness"
        const float s2 = roughnessToSigma2(PSDroughness);
        const float s2max = roughnessToSigma2(0.1f);
        const float s2r0 = roughnessToSigma2(.0f);
        this.q      = lerp(.0f,1.f,(s2r0-s2)/(s2r0-s2max));
        this.sigma2 = min(s2max, s2);
    }

    hwss_t alpha(float3 wi, float3 wo, hwss_t k)
    {
        const hwss_t a = sqr((abs(wi.z)+abs(wo.z)) * q * k);
        return isDeltaOnly() ? hwss_t(1.f) : exp(-a);
    }
    hwss_t alpha(float3 wi, hwss_t k) { return alpha(wi,wi,k); }
    float alpha(float3 wi, float3 wo, float k)
    {
        const float a = sqr((abs(wi.z)+abs(wo.z)) * q * k);
        return isDeltaOnly() ? 1.f : exp(-a);
    }
    float alpha(float3 wi, float k) { return alpha(wi,wi,k); }

    bool isDeltaOnly() { return q==.0f; }

    float3 sample<S : ISampleGenerator>(float3 wi, inout S sg, float k, out float pdf)
    {
        const float w = 1.f/sigma2;

        const float s2    = w/sqr(k);
        const float2 mean = -wi.xy;
        const float2 wo   = sample_boxmueller_truncated(sampleNext2D(sg), mean, s2, pdf);

        const float z = sqrt(max(0.f,1.f-dot(wo,wo)));
        return float3(wo, sign(wi.z)*z);
    }

    float pdf(const float3 wi, const float3 wo, float k)
    {
        const float w = 1.f/sigma2;

        const float s2 = w/sqr(k);
        const float2 mean = -wi.xy;
        return boxmueller_truncated_pdf(wo.xy, mean, s2);
    }

    float eval(float k, float2x2 invTheta, float2x2 Q, float3 h)
    {
        invTheta = mul(Q, mul(invTheta, transpose(Q)));

        const float2x2 S = ident2()/sigma2 + invTheta;

        float d = determinant(S);
        const float2x2 invS = float2x2(S[1][1],-S[0][1],-S[1][0],S[0][0]) / d;

        return
            exp(-.5f*sqr(k) * dot(h.xy,mul(invS,h.xy))) *
            (sqr(k) * M_1_2PI/sqrt(d));
    }
};
