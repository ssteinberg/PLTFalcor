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
#include "DiffractionGrating.slangh"

import Utils.Math.MathHelpers;
import Utils.HWSS;
__exported import Utils.Sampling.SampleGeneratorInterface;

import Scene.ShadingData;

import Rendering.Utils.DifferentialShadingGeometry;


struct DiffractionGrating {
    float2 gratingX;
    float2 invPitch;
    float q;
    uint lobeCount = 5;
    uint type = (uint)DiffractionGratingType::sinusoidal;

    // Should be untouched for physical correctness
    float intensityMultiplier = 1.f;

    __init(float gratingDir, const ShadingData sd, float2 invPitch, float q, uint lobes, uint type, float intensityMult = 1.f) {
        this.type = type;

        this.gratingX = float2(cos(gratingDir),sin(gratingDir));
        if ((type&(uint)DiffractionGratingType::radial)!=0) {
            // Radial grating
            const float2 radial = normalize(sd.uv - float2(.5, .5));
            this.gratingX = mul(float2x2(cos(gratingDir), sin(gratingDir), -sin(gratingDir), cos(gratingDir)), float2(radial.x,-radial.y));
        }

        this.invPitch = invPitch;
        this.q = q;
        this.lobeCount = lobes;
        this.intensityMultiplier = intensityMult;
    }


    bool is1DGrating() { return invPitch.y==.0f; }

    float alpha(float3 wi, float k) {
        const float costhetai = wi.z;
        const float a = sqr(costhetai * q * k);

        return exp(-a);
    }
    hwss_t alpha(float3 wi, hwss_t k) {
        const float costhetai = wi.z;
        const hwss_t a = sqr(costhetai * q * k);

        return exp(-a);
    }

    ShadingData localGratingShadingFrame(const ShadingData sd) {
        // Work in local space s.t. x-axis aligns with gratingX and z-axis is normal
        ShadingData gratingSd;
        gratingSd.T = sd.fromLocal(float3(gratingX,.0f));
        gratingSd.N = sd.N;
        gratingSd.B = cross(gratingSd.N,gratingSd.T);
        return gratingSd;
    }

    int2 closestLobeHint(const float3 wiLocal, const float3 woHint, const float alpha, const float lambda) {
        if (alpha==1.f)
            return 0;

        const float2 li2  = sqr(wiLocal.xy) + sqr(wiLocal.zz);
        const float2 lo2  = sqr(woHint.xy)  + sqr(woHint.zz);
        const float2 sini = li2 > FLT_EPSILON ?  wiLocal.xy / sqrt(li2) : .0f;
        const float2 sino = lo2 > FLT_EPSILON ? -woHint.xy  / sqrt(lo2) : .0f;
        const float2 l = (sini - sino) / (invPitch * lambda);

        int2 lobe = clamp((int2)(l+sign(l)*.5f), -int2(lobeCount), int2(lobeCount));
        lobe = alpha==.0f && lobe==0 ? sign(l) : lobe;
        lobe.y = is1DGrating() ? 0 : lobe.y;

        return lobe;
    }

    int2 sampleLobe<S : ISampleGenerator>(const float3 wiLocal, out float3 wo, out float2 pdf, const float lambda, inout S sg) {
        // Compute the intensity of each lobe
        float intensity[16];
        float total = .0f;
        for (int l=0;l<lobeCount;++l) {   // positive lobes
            const float li = lobeIntensity(int2(l+1,0),wiLocal,lambda);
            total += li;
            intensity[l] = li;
        }

        // Choose a lobe
        const float2 rand = (sampleNext2D(sg)-.5f)*2.f;
        float cdf = .0f;
        int2 lobe = 0;
        pdf = .0f;
        for (int l=0;l<lobeCount;++l) {
            const float p = intensity[l] / total;
            cdf += p;
            const bool2 select = abs(rand)<float2(cdf) && lobe==0;
            pdf = select ? float2(p) : pdf;
            lobe = select ? int2(l+1) : lobe;
        }
        pdf /= 2.f;

        lobe = rand<.0f ? -lobe : lobe;
        if (is1DGrating()) {
            lobe.y = 0;
            pdf.y = 1.f;
        }

        return lobe;
    }

    float3 diffract(const float3 wi, const int2 lobe, const float lambda) {
        const float2 p = sqrt(sqr(wi.xy) + sqr(wi.zz));
        const float2 sini = p>FLT_EPSILON ? wi.xy/p : .0f;
        const float2 sino = lambda * lobe*invPitch - sini;
        const float a = sino.x;
        const float b = sino.y;
        const float m = (sqr(a)-1) / (sqr(a*b)-1);
        const float q = 1 - sqr(b)*m;

        return all(abs(sino)<=1.f) ?
            float3(a*sqrt(max(.0f,q)),
                   b*sqrt(m),
                   sqrt(max(.0f, 1-sqr(a)*q-sqr(b)*m))) :
            float3(.0f);
    }

    float3 coherenceVec(const float3 wi, const float3 wo, const int2 lobe, const float lambda) {
        return 2.f * (wo + wi);
    }

    float lobeIntensity(const int2 lobe, const float3 wi, const float lambda) {
        const uint gratingtype = type&(uint)DiffractionGratingType::TypeMask;
        const float a = M_4PI * q / (lambda * abs(wi.z));
        float ix,iy;

        if (gratingtype == (uint)DiffractionGratingType::sinusoidal) {
            // Sinusoidal phase grating, with BesselJ diffraction efficiency
            iy=ix  = lobe.x==0 ? 1 : BesselJ(lobe.x,a);
            if (!is1DGrating())
                iy = lobe.y==0 ? 1 : BesselJ(lobe.y,a);
        }
        else if (gratingtype == (uint)DiffractionGratingType::rectangular) {
            // Rectangular phase grating, with sinc diffraction efficiency
            iy=ix  = lobe.x==0 ? 1 : sin(a/2.f) * sinc(M_PI*lobe.x/2.f);
            if (!is1DGrating())
                iy = lobe.y==0 ? 1 : sin(a/2.f) * sinc(M_PI*lobe.y/2.f);
        } else {
            // Linearly decreasing intensity (roughly corresponds to a from of a triangular phase grating)
            iy=ix  = lobe.x==0 ? 1 : 1.f/sqrt(abs(lobe.x));
            if (!is1DGrating())
                iy = lobe.y==0 ? 1 : 1.f/sqrt(abs(lobe.y));
        }

        return intensityMultiplier * ix*iy;
    }

    float3pdv gratingXpdv(const DifferentialShadingGeometry dsg) {
        float3pdv X = { dsg.fromLocal(float3(gratingX, .0f)),
            gratingX.x * dsg.s.ddu + gratingX.y * dsg.t.ddu,
            gratingX.x * dsg.s.ddv + gratingX.y * dsg.t.ddv,
        };
        return X;
    }

    // Computes the partial derivatives of a diffraction grating in world coordinates.
    float3kpdv partialDerivatives(const DifferentialShadingGeometry dsg, const float3pdv wi, const int2 lobe, const float wavelength)
    {
        const float3pdv n = dsg.n;
        const float3pdv X = gratingXpdv(dsg);

        if (all(lobe==0))
            return reflectDerivatives(wi,n);

        const float lambda = 1e-3f*wavelength;       // um
        const float2 lp = lobe*invPitch;

        const float3 Y    = cross(n.v,X.v);
        const float x     = dot(wi.v,X.v);
        const float y     = dot(wi.v,Y);
        const float z     = dot(wi.v,n.v);
        const float2 p    = sqrt(sqr(float2(x,y)) + sqr(float2(z,z)));
        const float2 invp = p>FLT_EPSILON ? 1.f/p : .0f;
        const float2 sini = float2(x,y)*invp;
        const float2 sino = lambda * lp - sini;

        const float a = sino.x;
        const float oneMinusA2 = max(.0f, 1-sqr(a));
        const float b = sino.y;
        const float m = -oneMinusA2 / (sqr(a*b)-1);
        const float q = 1 - sqr(b)*m;

        if (any(sino>1.f || sino<-1.f) || q<.0f || !(m>=.0f))
            return {};

        const float sqrtOneM = sqrt(q);
        const float sqrtM = sqrt(m);
        const float c = .5f / (sqrtOneM * sqrt(oneMinusA2));

        const float  dxdu = dot(wi.v,X.ddu)+dot(wi.ddu,X.v);
        const float  dxdv = dot(wi.v,X.ddv)+dot(wi.ddv,X.v);
        const float  dzdu = dot(wi.v,n.ddu)+dot(wi.ddu,n.v);
        const float  dzdv = dot(wi.v,n.ddv)+dot(wi.ddv,n.v);

        const float2 dsino_du = z * (float2(x,y)*dzdu - float2(z,z)*dxdu) * (sqr(invp)*invp);
        const float2 dsino_dv = z * (float2(x,y)*dzdv - float2(z,z)*dxdv) * (sqr(invp)*invp);
        const float2 dsino_dl = lp;
        const float  dadu = dsino_du.x;
        const float  dbdu = dsino_du.y;
        const float  dadv = dsino_dv.x;
        const float  dbdv = dsino_dv.y;
        const float  dadl = dsino_dl.x;
        const float  dbdl = dsino_dl.y;
        const float  dmdu = 2*a * (a*b*oneMinusA2*dbdu - dadu*(1-sqr(b))) / sqr(sqr(a*b)-1);
        const float  dmdv = 2*a * (a*b*oneMinusA2*dbdv - dadv*(1-sqr(b))) / sqr(sqr(a*b)-1);
        const float  dmdl = 2*a * (a*b*oneMinusA2*dbdl - dadl*(1-sqr(b))) / sqr(sqr(a*b)-1);

        float3kpdv ret;

        ret.v = X.v * a*sqrtOneM +
                Y   * b*sqrtM +
                n.v * sqrt(max(.0f, 1-sqr(a)*q-sqr(b)*m));

        ret.ddu = X.v * (q*dadu - a*b*(b*dmdu/2.f+m*dbdu)) / sqrtOneM +
                  Y   * (b*dmdu/2.f + m*dbdu) / sqrtM +
                  n.v * (-2*a*dadu*q - b*(b*dmdu+2.f*m*dbdu) + sqr(a)*b*(b*dmdu+2.f*m*dbdu)) * c;
        ret.ddv = X.v * (q*dadv - a*b*(b*dmdv/2.f+m*dbdv)) / sqrtOneM +
                  Y   * (b*dmdv/2.f + m*dbdv) / sqrtM +
                  n.v * (-2*a*dadv*q - b*(b*dmdv+2.f*m*dbdv) + sqr(a)*b*(b*dmdv+2.f*m*dbdv)) * c;
        ret.ddl = X.v * (q*dadl - a*b*(b*dmdl/2.f+m*dbdl)) / sqrtOneM +
                  Y   * (b*dmdl/2.f + m*dbdl) / sqrtM +
                  n.v * (-2*a*dadl*q - b*(b*dmdl+2.f*m*dbdl) + sqr(a)*b*(b*dmdl+2.f*m*dbdl)) * c;

        return ret;
    }
}
