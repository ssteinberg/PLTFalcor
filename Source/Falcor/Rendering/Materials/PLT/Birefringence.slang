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

struct Birefringence {

// y is up, incident ray is assumed to reside on the yz-plane

// Normal modes
static float qo(float eo, float K) {
    const float k = 1;
        return sqrt(sqr(eo)*sqr(k) - sqr(K));
}
static float2 qe(float eo, float ee, float3 A, float K) {
    const float e = sqr(ee)-sqr(eo);
    const float k = 1;
    const float a = A.x;
    const float b = A.y;
    const float c = A.z;
    const float G = sqr(b)*e+sqr(eo);

    const float qep = (eo*sqrt(max(0,sqr(K)*(sqr(a)*e-sqr(ee)) + sqr(k)*sqr(ee)*G)) + c*b*K*e)/G;
    const float qem = (-eo*sqrt(max(0,sqr(K)*(sqr(a)*e-sqr(ee)) + sqr(k)*sqr(ee)*G)) + c*b*K*e)/G;

    return float2(qep, qem);
}
// Electric fields
static float3 E_ep(float eo, float ee, float3 A, float K) {
    const float k = 1;
    const float a = A.x;
    const float b = A.y;
    const float c = A.z;
    const float q = qe(eo,ee,A,K).x;

    const float3 E_e = float3(a*sqr(k)*sqr(eo),
                          K*c*q + b*(sqr(eo)*sqr(k) - sqr(q)),
                          K*b*q + c*(sqr(eo)*sqr(k) - sqr(K)));
    return normalize(E_e);
}
static float3 E_em(float eo, float ee, float3 A, float K) {
    const float k = 1;
    const float a = A.x;
    const float b = A.y;
    const float c = A.z;
    const float q = qe(eo,ee,A,K).y;

    const float3 E_e = float3(a*sqr(k)*sqr(eo),
                          K*c*q + b*(sqr(eo)*sqr(k) - sqr(q)),
                          K*b*q + c*(sqr(eo)*sqr(k) - sqr(K)));
    return normalize(E_e);
}
static float3 E_op(float eo, float3 A, float K) {
    // const float k = 1;
    const float a = A.x;
    const float b = A.y;
    const float c = A.z;
    const float q = qo(eo,K);

    const float3 E_o = float3(-b*K-c*q, a*K, a*q);
    return normalize(E_o);
}
static float3 E_om(float eo, float3 A, float K) {
    // const float k = 1;
    const float a = A.x;
    const float b = A.y;
    const float c = A.z;
    const float q = -qo(eo,K);

    const float3 E_o = float3(-b*K-c*q, a*K, a*q);
    return normalize(E_o);
}
// Poynting vector
static float3 Poynting(float q, float3 E, float K) {
    return normalize(
            float3(E.x*(K*E.z - q*E.y),
                     K*E.z*E.y + q*(sqr(E.x) + sqr(E.z)),
                     -q*E.z*E.y - K*(sqr(E.x) + sqr(E.y))));
}

// Fresnel coefficients
static void fresnel_iso_aniso(float cos_theta, float sin_theta, float ei, float eo, float ee, float3 A, out float rss, out float rsp, out float tso, out float tse, out float rps, out float rpp, out float tpo, out float tpe) {
    const float k = 1;
    const float K = k*ei*sin_theta;
    const float qi = -qo(ei,K);
    const float3 E2om = E_om(eo,A,K);
    const float3 E2em = E_em(eo,ee,A,K);
    const float q2om = -qo(eo,K);
    const float q2em = qe(eo,ee,A,K).y;

    const float A_1 = -E2em.x*E2om.y*K*cos_theta;
    const float A_2 = -E2em.y*E2om.x*K*cos_theta;
    const float C_1 = qi*cos_theta - K*sin_theta;
    const float C_2 = E2em.x*E2om.z*(C_1 + q2om*cos_theta) - A_1;
    const float C_3 = E2em.z*E2om.x*(C_1 + q2em*cos_theta) - A_2;

    const float Ns = C_2*(qi + q2em) - C_3*(qi + q2om);

    rps = (2*E2em.x*E2om.x*cos_theta*C_1*(q2om - q2em)) / Ns;
    rpp = (-E2em.x*E2om.z*(C_1 - q2om*cos_theta)*(qi + q2em) + E2em.z*E2om.x*(C_1 - q2em*cos_theta)*(qi + q2om) - A_1*(q2em + qi) + A_2*(q2om + qi)) / Ns;
    tpo = -(2*E2em.x*cos_theta*(q2em + qi)*C_1) / Ns;
    tpe = (2*E2om.x*cos_theta*(q2om + qi)*C_1) / Ns;

    rss = (C_2*(qi - q2em) + C_3*(q2om - qi)) / Ns;
    rsp = (2*qi*(E2em.z*E2om.y*K - E2em.y*E2om.z*K + E2em.z*E2om.z*(q2om - q2em))) / Ns;
    tso = -(2*qi*(E2em.y*K*cos_theta + E2em.z*C_1 + E2em.z*q2em*cos_theta)) / Ns;
    tse = (2*qi*(E2om.y*K*cos_theta + E2om.z*C_1 + E2om.z*q2om*cos_theta)) / Ns;
}
static void fresnel_aniso_iso(float cos_phi, float sin_phi, float ei, float eo, float ee, float3 A, out float roo, out float roe, out float tos, out float top, out float reo, out float ree, out float tes, out float tep) {
    const float eo2 = ei;
    const float k = 1;
    const float K = k * ei * sin_phi;
    const float q2om = -qo(eo2,K);
    const float qop  =  qo(eo,K);
    const float2 _qe = qe(eo,ee,A,K);
    const float qep = _qe.x;
    const float qem = _qe.y;
    const float3 Eop = E_op(eo,A,K);
    const float3 Eep = E_ep(eo,ee,A,K);
    const float3 Eom = E_om(eo,A,K);
    const float3 Eem = E_em(eo,ee,A,K);

    const float B_1 = -Eep.x*K*cos_phi*(q2om - qep);
    const float B_2 = -Eom.x*K*cos_phi*(q2om + qop);
    const float B_3 = -Eop.x*K*cos_phi*(qop - q2om);
    const float D_1 = K*sin_phi - q2om*cos_phi;
    const float D_2 = Eep.z*(D_1 + qep*cos_phi);
    const float D_3 = Eem.z*(D_1 + qem*cos_phi);
    const float D_4 = Eop.z*(D_1 + qop*cos_phi);

    const float N2 = (Eep.x*(qep - q2om)*D_4 + Eop.x*(q2om - qop)*D_2 + Eop.y*B_1 + Eep.y*B_3);

    roo = -(Eep.x*Eom.z*(q2om - qep)*(qop*cos_phi - D_1) + Eom.x*(q2om + qop)*D_2 + Eom.y*B_1 - Eep.y*B_2) / N2;
    roe = -(-Eom.x*Eop.z*(qop*(qop*cos_phi + K*sin_phi) + q2om*D_1) + Eom.z*Eop.x*(qop*(qop*cos_phi - K*sin_phi) + q2om*D_1) + Eop.y*B_2 + Eom.y*B_3) / N2;
    tos = (Eep.x*qep*roe - Eom.x*qop + Eop.x*qop*roo) / q2om;
    top = -(Eom.z*qop - Eom.y*K - (Eep.y*K + Eep.z*qep)*roe - (Eop.y*K + Eop.z*qop)*roo) / D_1;

    reo = (Eem.x*(qem - q2om)*(D_2 + Eep.y*K*cos_phi) + Eep.x*(q2om - qep)*(D_3 + Eem.y*K*cos_phi)) / N2;
    ree = -(Eem.x*(qem - q2om)*D_4 - Eem.x*Eop.y*K*cos_phi*(q2om - qem) + Eem.y*B_3 + Eop.x*(q2om - qop)*D_3) / N2;
    tes = (Eem.x*qem + Eep.x*qep*ree + Eop.x*qop*reo) / q2om;
    tep = -(Eem.z + Eep.z*ree + Eop.z*reo) / cos_phi;
}

// Comptutes the four vectors in an anistrotpic slab
static void vectors_in_slab(float3 I, float ei, float eo, float ee, float3 A,
                     out float3 Io, out float3 Io2, out float3 Ie, out float3 Ie2, out float e_eff, out float e_eff2) {
    const float K = ei * I.z;
    // const float qop = qo(eo,K);
    const float qom = -qo(eo,K);
    const float qep = qe(eo,ee,A,K).x;
    const float qem = qe(eo,ee,A,K).y;
    // const float3 Eop = E_op(eo,A,K);
    const float3 Eom = E_om(eo,A,K);
    const float3 Eep = E_ep(eo,ee,A,K);
    const float3 Eem = E_em(eo,ee,A,K);

    Io = Poynting(qom,Eom,K);
    Io2 = Io;
    Io2.y *= -1.f;
    Ie = Poynting(qem,Eem,K);
    Ie2 = Poynting(qep,Eep,K);

    // Effective refractive indices
    const float3 We =  normalize(float3(0,qem,-K));
    const float3 We2 = normalize(float3(0,qep,-K));
    e_eff = K / sqrt(max(.0f,1.f - sqr(We.y)));
    e_eff2 = K / sqrt(max(.0f,1.f - sqr(We2.y)));
}

}

