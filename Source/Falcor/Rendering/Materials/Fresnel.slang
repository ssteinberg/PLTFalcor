/***************************************************************************
 # Copyright (c) 2015-22, NVIDIA CORPORATION. All rights reserved.
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
import Utils.Math.MathHelpers;

void fresnel_dielectric(float cosThetaI_, float eta, out float rs, out float rp, out float ts, out float tp, out float cosThetaT) {
    if (eta == 1) {
        cosThetaT = -cosThetaI_;
        rs = rp = 0;
        ts = tp = 1;
        return;
    }

    /* Using Snell's law, calculate the squared sine of the
       angle between the normal and the transmitted ray */
    eta = (cosThetaI_ > 0) ? eta : 1/eta;
    const float cosThetaI = abs(cosThetaI_);
    const float cosThetaTSqr = 1 - (1-sqr(cosThetaI)) / sqr(eta);

    /* Find the absolute cosines of the incident/transmitted rays */
    cosThetaT = sqrt(max(.0f,cosThetaTSqr));

    rs = (cosThetaI - eta * cosThetaT) / (cosThetaI + eta * cosThetaT);
    rp = (eta * cosThetaI - cosThetaT) / (eta * cosThetaI + cosThetaT);
    const float imp = sqrt(eta*cosThetaT/cosThetaI);
    ts = imp * (rs+1);// 2 * cosThetaI / (cosThetaI + eta * cosThetaT);
    tp = imp * (rp+1) / eta;// 2 * cosThetaI / (eta * cosThetaI + cosThetaT);

    cosThetaT *= -sign(cosThetaI_);
}
void fresnel_dielectric(float cosThetaI, float eta, out float rs, out float rp, out float ts, out float tp) {
    float cosThetaT;
    fresnel_dielectric(cosThetaI,eta,rs,rp,ts,tp,cosThetaT);
}

void fresnel_conductor(float cosThetaI, const float2 eta,
                       out float2 rs, out float2 rp) {
    if (all(eta == float2(0)) || cosThetaI<.0f) {
        rs = rp = .0f;
        return;
    }

    const float2 t2 = c_t(1) - (1-sqr(cosThetaI)) * csqr(cdiv(c_t(1),eta));
    const float2 t = csqrt(t2);

    const float2 i = c_t(cosThetaI);
    rs = cdiv((i - cmul(eta,t)), (i + cmul(eta,t)));
    rp = cdiv((cmul(eta,i) - t), (cmul(eta,i) + t));
}

float evalFresnelDielectric(float eta, float cosThetaI, out float cosThetaT)
{
    float rs,rp,ts,tp;
    fresnel_dielectric(cosThetaI,eta,rs,rp,ts,tp,cosThetaT);
    return .5f * (sqr(rs)+sqr(rp));
}
float evalFresnelDielectric(float eta, float cosThetaI)
{
    float cosThetaT;
    return evalFresnelDielectric(eta, cosThetaI, cosThetaT);
}
float evalFresnelConductor(const float2 eta, float cosThetaI) {
    float2 rs, rp;
    fresnel_conductor(cosThetaI, eta, rs, rp);
    return .5f * (cnorm2(rs)+cnorm2(rp));
}

