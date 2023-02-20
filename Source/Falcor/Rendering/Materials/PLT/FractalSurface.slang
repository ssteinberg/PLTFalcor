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
import Utils.Color.SpectrumUtils;

/** This class implements sampling and evaluation of an surface with Gaussian-Fractal PSD statistics.
*/
struct FractalSurface
{
    float T, gamma = 3.f;


    static const float meank = M_2PI / (SpectrumUtils.meanWavelength*1e-3f);
    float roughnessToT(float alpha)
    {
        static const float maxAlpha = .75f;      // Nothing beyond this makes the slightest of sense
        static const float maxT = 5000.f;       // Equivalent to minimal roughness of about alpha=0.0005

        // Aims to match GGX roughness with gamma=3 at 550nm wavelength, normal incidence.
        const float alpha2 = sqr(clamp(alpha, .0f, maxAlpha));
        return min(maxT, (1-alpha2) / (4.f*sqr(meank)*alpha2));
    }
    float TToRoughness(float T)
    {
        return 1.f/sqrt(1.f + 4.f*sqr(meank)*T);
    }


    property roughness : float {
        get {
            return TToRoughness(T);
        }
    }
    property q : float {
        get {
            static const float roughnessToQscale = 1.f;
            return roughness * roughnessToQscale;
        }
    }

    __init(float PSDroughness, float gamma=3.f)
    {
        this.gamma = max(1.1f,gamma);
        this.T = roughnessToT(PSDroughness);
    }

    hwss_t alpha(float3 wi, float3 wo, hwss_t k)
    {
        const hwss_t a = sqr((abs(wi.z)+abs(wo.z)) * q * k);
        return exp(-a);
    }
    hwss_t alpha(float3 wi, hwss_t k) { return alpha(wi,wi,k); }
    float alpha(float3 wi, float3 wo, float k)
    {
        const float a = sqr((abs(wi.z)+abs(wo.z)) * q * k);
        return exp(-a);
    }
    float alpha(float3 wi, float k) { return alpha(wi,wi,k); }

    bool isDeltaOnly() { return q==.0f; }

    float pGF(const float2 z) {
        const float f = 1.f/pow(1+T*dot(z,z), (gamma+1.f)/2.f);
        return M_1_2PI * (gamma-1) * T * f;
    }

    float3 sample<S : ISampleGenerator>(float3 wi, inout S sg, float k, out float pdf)
    {
        // As in A Two-Scale Microfacet Reflectance Model Combining Reflection and Diffraction
        // HOLZSCHUCH & PACANOWSKI 2017

        const float s = sqrt(max(.0f,1-sqr(wi.z)));
        const float phi_i = s>0 ? atan2(wi.y,wi.x) : .0f;
        const float sqrtT = sqrt(T);

        const float2 u2d1 = sampleNext2D(sg);
        const float2 u2d2 = sampleNext2D(sg);

        const float M = 1.f - pow(1+sqr(k)*T*sqr(1+s), -(gamma-1)/2.f);
        const float f = sqrt(pow(1-M*u2d1.x, -2.f/(gamma-1))-1.f) / sqrtT;

        const float phi_max = f==.0f || s==.0f ?
            M_PI :
            acos(clamp((sqr(f/k)+sqr(s)-1)/(2.f * (f/k) * s), -1.f,1.f));
        const float phi_f = phi_i + (2.f*u2d1.y-1)*phi_max;
        const float2 vf = f * float2(cos(phi_f),sin(phi_f));

        const float2 zeta = vf;
        const float2 wo = zeta/k - float2(wi.x,wi.y);
        const float z = sqrt(max(.0f,1-dot(wo,wo)));

        pdf = M_PI/phi_max * z * pGF(zeta);
        return float3(wo, sign(wi.z)*z);
    }

    float pdf(const float3 wi, const float3 wo, float k)
    {
        return pGF(k*(wi+wo).xy);
    }

    float eval(float k, const float3 h)
    {
        return pGF(k*h.xy);
    }
};
