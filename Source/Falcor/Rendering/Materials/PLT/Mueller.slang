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
import Rendering.Materials.Fresnel;

float4x4 MuellerT(const float3 n1, const float3 t1, const float3 n2, const float3 t2, out float outsint, out float outcost) {
    // CW angle from t1 to t2 on the plane with normal n1
    float theta = atan2(dot(n1,cross(t1,t2)), dot(t1,t2));
    theta = isfinite(theta) ? theta : .0f;

    const float sint  = sin(theta);
    const float cost  = cos(theta);
    const float rx    = 2*sint*cost;
    const float ry    = 1-2*sqr(sint);

    outsint = sint;
    outcost = cost;

    float4x4 T = { };
    T[0][0] = T[3][3] = 1;
    T[1][1] = T[2][2] = rx;
    T[1][2] = -ry;
    T[2][1] = ry;
    return T;
}
float4x4 MuellerT(const float3 n1, const float3 t1, const float3 n2, const float3 t2) {
    float unused1, unused2;
    return MuellerT(n1,t1,n2,t2,unused1,unused2);
}

// Mueller linear polarizer
float4x4 MuellerPolarizer(float theta) {
    float s = sin(theta);
    float c = cos(theta);

    float4x4 P = { };
    P[0][0] = 1;
    P[0][1] = P[1][0] = c;
    P[0][2] = P[2][0] = s;
    P[1][2] = P[2][1] = c*s;
    P[1][1] = c*c;
    P[2][2] = s*s;
    P[3][3] = 0;

    return .5f * P;
}

// Mueller Fresnel matrices
float4x4 MuellerFresnel(float2 fs, float2 fp) {
    const float Rp = cnorm2(fp);
    const float Rs = cnorm2(fs);
    const float m00 = (Rp+Rs)/2.f;
    const float m01 = (Rp-Rs)/2.f;
    const float m22 = creal(fs*cconj(fp));
    const float m23 = cimag(fs*cconj(fp));
    return float4x4(m00,m01, 0,  0,
                    m01,m00, 0,  0,
                    0,  0,   m22,m23,
                    0,  0,  -m23,m22);
}
float4x4 invOneMinusMuellerFresnel(const float2 fs, const float2 fp) {
    const float Rp = cnorm2(fp);
    const float Rs = cnorm2(fs);
    const float m00 = (Rp+Rs)/2;
    const float m01 = (Rp-Rs)/2;
    const float m22 = creal(fs*cconj(fp));
    const float m23 = cimag(fs*cconj(fp));

    const float2x2 minor1 = float2x2(1,0,0,1) - float2x2(m00,m01, m01,m00);
    const float2x2 minor2 = float2x2(1,0,0,1) - float2x2(m22,m23,-m23,m22);

    float2x2 im1,im2;
    if (!tryInvert(minor1, im1) || !tryInvert(minor2, im2)) {
        float4x4 z = { 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0 };
        return z;
    }

    return float4x4(im1[0][0], im1[0][1], 0,         0,
                    im1[0][1], im1[0][0], 0,         0,
                    0,         0,         im2[0][0], im2[0][1],
                    0,         0,         im2[1][0], im2[0][0]);
}
float4x4 MuellerFresnelRConductor(float cosThetaI, const float2 eta) {
    float2 rs,rp;
    fresnel_conductor(cosThetaI, eta, rs, rp);

    return MuellerFresnel(rs, rp);
}
float4x4 MuellerFresnelRConductor(float cosThetaI, const float2 eta, out float2 rs, out float2 rp) {
    fresnel_conductor(cosThetaI, eta, rs, rp);

    return MuellerFresnel(rs, rp);
}
float4x4 MuellerFresnelRDielectric(float cosThetaI, float eta) {
    float rs,rp, ts,tp;
    fresnel_dielectric(cosThetaI, eta, rs, rp, ts, tp);

    return MuellerFresnel(float2(rs,0), float2(rp,0));
}
float4x4 invOneMinusMuellerFresnelRDielectric(float cosThetaI, float eta) {
    float rs,rp, ts,tp;
    fresnel_dielectric(cosThetaI, eta, rs, rp, ts, tp);

    return invOneMinusMuellerFresnel(float2(rs,0), float2(rp,0));
}
float4x4 MuellerFresnelTDielectric(float cosThetaI, float eta) {
    float rs,rp, ts,tp;
    fresnel_dielectric(cosThetaI, eta, rs, rp, ts, tp);

    return MuellerFresnel(float2(ts,0), float2(tp,0));
}
float4x4 MuellerFresnelDielectric(float cosThetaI, float eta, bool reflection) {
    return reflection ?
        MuellerFresnelRDielectric(cosThetaI, eta) :
        MuellerFresnelTDielectric(cosThetaI, eta);
}



struct fresnel_spm_order1_data {
    float mr[2][2];
    float mt[2][2];
    float2 kai1[2];
    float2 kai2[2];
    float2 kai3[2];
    float2 beta1[2];
    float2 beta2[2];
    float2 beta3[2];

    float R,T;
};
fresnel_spm_order1_data fresnel_spm_order1(float cos_theta_i, float cos_theta_o, const float phi_i, const float phi_o, float2 eta) {
    if (cos_theta_i<.0f)
        eta = cdiv(c_t(1), eta);
    const float reta = creal(eta);
    cos_theta_i = abs(cos_theta_i);
    cos_theta_o = abs(cos_theta_o);
    const float sin_theta_i = sqrt(max(.0f, 1.f - sqr(cos_theta_i)));
    const float sin_theta_o = sqrt(max(.0f, 1.f - sqr(cos_theta_o)));

    const float phi = phi_o - phi_i + M_PI;
    const float cos_phi = cos(phi);
    const float sin_phi = sin(phi);
    const float2 eta2 = csqr(eta);

    const float2 si = csqrt(eta2 - c_t(sqr(sin_theta_i)));
    const float2 ss = csqrt(eta2 - c_t(sqr(sin_theta_o)));
    const float2 st = csqrt(c_t(1) - eta2*sqr(sin_theta_o));
    const float2 qi = c_t(cos_theta_i) - si;
    const float2 qs = c_t(cos_theta_o) - ss;
    const float2 qt = eta*cos_theta_o  - st;
    const float2 ti = c_t(sqr(sin_theta_i)) + si * cos_theta_i;
    const float2 ts = c_t(sqr(sin_theta_o)) + ss * cos_theta_o;
    const float2 tt = eta*sqr(sin_theta_o)  + st * cos_theta_o;
    const float2 wi = -csqr(si) + si * cos_theta_i;
    const float2 ws = -csqr(ss) + ss * cos_theta_o;
    const float2 wt = -csqr(st) + cmul(eta,st) * cos_theta_o;
    const float2 s  = eta2*sin_theta_i*sin_theta_o - cmul(si,ss)*cos_phi;
    const float2 t  = eta *sin_theta_i*sin_theta_o + cmul(si,st)*cos_phi;

    fresnel_spm_order1_data d;

    d.R = cos_theta_i / cnorm2(c_t(cos_theta_i) + si);
    d.T = cos_theta_i * reta*sqrt(reta) / sqr(sqr(reta)-1);

    for (int j=0;j<2;++j)
    for (int l=0;l<2;++l) {
        const float ll = l==0?1.f:-1.f;
        const float jj = j==0?1.f:-1.f;
        d.mr[j][l] = ll * cnorm2(cdiv(cmul(qs,s),cmul(ti,ts))) +
                     cnorm2(qs) * sqr(cos_phi) +
                     jj * (cnorm2(cdiv(ws,ts)) + ll*cnorm2(cdiv(cmul(qs,si),ti))) * sqr(sin_phi);
        d.mt[j][l] = ll * cnorm2(cdiv(cmul(cmul(qi,qt),t),cmul(ti,tt))) +
                     cnorm2(cmul(qi,qt)) * sqr(cos_phi) +
                     jj * (cnorm2(cdiv(cmul(qi,wt),tt)) + ll*cnorm2(cdiv(cmul(qt,wi),ti))) * sqr(sin_phi);
    }
    for (int j=0;j<2;++j) {
        const float jj = j==0?1.f:-1.f;

        d.kai1[j] = jj*cdiv(cmul(cmul(qs,s),cconj(ws)),ti*cnorm2(ts))*sin_phi + cdiv(si,ti)*cnorm2(qs)*cos_phi*sin_phi;
        d.kai2[j] = jj*cdiv(cmul(si,cconj(s))*cnorm2(cdiv(qs,ti)) + cmul(qs,cconj(ws))*cos_phi, cconj(ts)) * sin_phi;
        d.kai3[j] = jj*cdiv(cmul(cmul(qs,si),cconj(ws)),cmul(ti,cconj(ts)))*sqr(sin_phi) + cdiv(s,cmul(ti,ts))*cnorm2(qs)*cos_phi;

        d.beta1[j] = cdiv(jj*cmul(cmul(qt,t),cconj(wt))*cnorm2(cdiv(qi,tt)) + cmul(wi,cconj(qi))*cnorm2(qt)*cos_phi, ti) * sin_phi;
        d.beta2[j] = cdiv(jj*cmul(cmul(qi,t),cconj(wi))*cnorm2(cdiv(qt,ti)) + cmul(wt,cconj(qt))*cnorm2(qi)*cos_phi, tt) * sin_phi;
        d.beta3[j] = jj*cdiv(cmul(cmul(qi,wt),cmul(cconj(qt),cconj(wi))), cmul(tt,cconj(ti)))*sqr(sin_phi) + cdiv(t,cmul(tt,ti))*cnorm2(cmul(qi,qt))*cos_phi;
    }

    return d;
}

float4x4 MuellerFresnelRspm1(float cos_theta_i, float cos_theta_o, const float phi_i, const float phi_o, const float2 eta) {
    const fresnel_spm_order1_data d = fresnel_spm_order1(cos_theta_i, cos_theta_o, phi_i, phi_o, eta);

    return d.R * float4x4(
        .5f*d.mr[0][0],  .5f*d.mr[1][1],  creal(d.kai2[0]), cimag(d.kai2[0]),
        .5f*d.mr[0][1],  .5f*d.mr[1][0],  creal(d.kai2[1]), cimag(d.kai2[1]),
        creal(d.kai1[0]), creal(d.kai1[1]), creal(d.kai3[0]), -cimag(d.kai3[1]),
        cimag(d.kai1[0]), cimag(d.kai1[1]), cimag(d.kai3[0]), creal(d.kai3[1])
    );
}

float4x4 MuellerFresnelTspm1(float cos_theta_i, float cos_theta_o, const float phi_i, const float phi_o, float eta) {
    const fresnel_spm_order1_data d = fresnel_spm_order1(cos_theta_i, cos_theta_o, phi_i, phi_o, c_t(eta));

    return d.T * float4x4(
        .5f*d.mt[0][0],  .5f*d.mt[1][1],  -creal(d.beta2[1]), cimag(d.beta2[1]),
        .5f*d.mt[0][1],  .5f*d.mt[1][0],  -creal(d.beta2[0]), cimag(d.beta2[0]),
        creal(d.beta1[1]), creal(d.beta1[0]), creal(d.beta3[1]), -cimag(d.beta3[1]),
        cimag(d.beta1[1]), cimag(d.beta1[0]), cimag(d.beta3[0]), creal(d.beta3[0])
    );
}

float4x4 MuellerFresnelspm1(float cos_theta_i, float cos_theta_o, const float phi_i, const float phi_o, const float2 eta) {
    const bool isReflection = cos_theta_i * cos_theta_o >= .0f;
    return isReflection ?
        MuellerFresnelRspm1(cos_theta_i, cos_theta_o, phi_i, phi_o, eta) :
        MuellerFresnelTspm1(cos_theta_i, cos_theta_o, phi_i, phi_o, creal(eta));
}

