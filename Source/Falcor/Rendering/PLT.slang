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

#include "Utils/Math/MathConstants.slangh"

import Utils.Math.MathHelpers;
import Utils.HWSS;
import Utils.Sampling.SampleGenerator;

import Scene.ShadingData;

import Rendering.Materials.PLT.Mueller;
import Rendering.Materials.BSDFSample;


struct PLTCoherence {
    float3 D;     /// Diffusivity matrix
    float r_m;    /// Distance traveled from source (m)

    __init(float diffusivity, float r) {
        this.D = float3(diffusivity, 0, diffusivity);
        this.r_m = r;
    }
    __init(float2x2 D, float r) {
        this.D = float3(D[0][0],D[0][1],D[1][1]);
        this.r_m = r;
    }

    float2x2 toDiffusivityMat() {
        return float2x2(D.x, D.y, D.y, D.z);
    }
    float2x2 toInvCoherenceMat(float k) {
        const float recp_lambda = k/M_2PI;
        return sqr(recp_lambda/r()) * toDiffusivityMat();      // to mm
    }
    float2x2 toInvCoherenceMat() {
        return sqr(1.f/r()) * toDiffusivityMat();              // to mm
    }
    float det(float k) { return 1.f/determinant(toInvCoherenceMat(k)); }
    float det() { return 1.f/determinant(toInvCoherenceMat()); }

    // in mm
    float r() { return r_m*1e+3f; }
    [mutating] void propagate(const float dist_m) {
        r_m += dist_m;
    }

    [mutating] void transform(const float2x2 U) {
        const float2x2 D = toDiffusivityMat();
        const float2x2 newD = mul(transpose(U), mul(D, U));
        this.D = float3(newD[0][0],newD[0][1],newD[1][1]);
    }
};

// Units:
// wavenumbers k in (um)^(-1)
// distances in m
struct PLTBeam {
    // Stokes parameters
    hwss_t L = .0f;
    hwss_t L1 = .0f,L2 = .0f,L3 = .0f;

    // Wavelengths
    hwss_t wavelengths;             ///< Selected wavelengths
    hwss_t spectralPDFs;
    uint hwss_comps = hwss_samples;

    // Coherence
    PLTCoherence Theta = { };

    float3 posW;
    float3 r;                   ///< Direction of propagation
    float3 t;                   ///< Beam tangent (direction of horizontal linear polarization)
    bool distant = false;

    __init(hwss_t Le, const float2x2 Diffusivity, float3 posW, float3 dir, float3 tangent, hwss_t wavelengths, bool distant = false, uint hwssComps = hwss_samples) {
        this.hwss_comps = hwssComps;
        this.wavelengths = wavelengths;
        this.spectralPDFs = 1.f;

        this.L = Le;
        this.L1 = this.L2 = this.L3 = hwss_t(.0f);

        this.Theta = PLTCoherence(Diffusivity, distant ? 1e-3f : .0f);

        this.posW = posW;
        this.r = dir;
        this.t = tangent;
        this.distant = distant;
    }

    float4 getSP(int hwss_idx) {
        return float4(L[hwss_idx],
                      L1[hwss_idx],
                      L2[hwss_idx],
                      L3[hwss_idx]);
    }
    [mutating] void setSP(int hwss_idx, float4 SP) {
        L[hwss_idx] = SP.x;
        L1[hwss_idx] = SP.y;
        L2[hwss_idx] = SP.z;
        L3[hwss_idx] = SP.w;
    }
    [mutating] void setZero() {
        L=L1=L2=L3=hwss_t(.0f);
    }
    [mutating] void scale(hwss_t s) {
        L *= s;
        L1 *= s;
        L2 *= s;
        L3 *= s;
    }
    [mutating] void scale(float s) {
        L *= s;
        L1 *= s;
        L2 *= s;
        L3 *= s;
    }

    // Rotation on the transverse plane to local coordinates
    float2x2 Q() {
        const float2 t2 = t.xy;
        const float2 b2 = cross(t,r).xy;
        return transpose(float2x2(t2,b2));
    }
    float2x2 invTheta(const float k) {
        return Theta.toInvCoherenceMat(k);
    }
    float2x2 invTheta() {
        return Theta.toInvCoherenceMat();
    }

    // Mutual coherence between points spaced by difference v
    float mutualCoherence(const float k, const float3 v) {
        const float2x2 invT = invTheta(k);
        const float x = dot(v.xy,mul(invT,v.xy));
        return exp(-.5f*x);
    }
    hwss_t mutualCoherence(const hwss_t k, const float3 v) {
        const hwss_t recp_lambda = k/M_2PI;
        const float2x2 invT = invTheta();
        const hwss_t x = sqr(recp_lambda)*dot(v.xy,mul(invT,v.xy));
        return exp(-.5f*x);
    }
    // Mutual coherence between two incident directions
    // d1,d2 - normalized vectors
    float mutualCoherenceAngular(const float3 d1, const float3 d2) {
        const float2 v = 1.f / max(sqrt(M_4PI)*abs(d1-d2).xy, FLT_EPSILON);
        const float2x2 invT = invTheta()*sqr(Theta.r());
        const float x = 1.f / dot(v,mul(invT,v));
        return exp(-.5f*x);
    }

    // Coherence PDFs
    float coherencePDF(const float k, const float3 v) {
        return mutualCoherence(k,v) / (M_2PI * sqrt(Theta.det(k)));
    }
    float coherencePDFAngular(const float3 d1, const float3 d2) {
        const float2 v = 1.f / max(sqrt(M_4PI)*abs(d1-d2).xy, FLT_EPSILON);
        const float2x2 invT = invTheta()*sqr(Theta.r());
        const float x = 1.f / dot(v,mul(invT,v));
        return exp(-.5f*x) / sqrt(determinant(invT)) / M_2PI;
    }

    float coherenceArea(const float k) {
        return M_PI * sqrt(Theta.det(k));
    }
    float coherenceAnisotropy(const float k) {
        float2x2 U, S;
        svd_symmetric(Theta.toInvCoherenceMat(k), U, S);
        return 1.f - S[0][0]/S[1][1];
    }

    // Coherence is transformed by the inverse of U
    [mutating] void transformCoherence(const float2x2 U) {
        Theta.transform(U);
    }
    [mutating] void rotateFrame(float3 newt, float3 newr) {
        float sint, cost;
        float4x4 T = MuellerT(r,t,newr,newt, sint,cost);
        // Rotate stokes parameters
        for (int j = 0; j < hwss_comps; ++j)
            setSP(j, mul(T, getSP(j)));
        // Rotate coherene matrices
        const float2x2 R = float2x2(cost,-sint,sint,cost);
        transformCoherence(R);

        // Set new frame
        r = newr;
        t = newt;
    }
    // Works in local frame (normal is (0,0,1) and (1,0,0) is tangent)
    [mutating] void constructLocalFrame(float3 newwo) {
        float3 newt = cross(float3(0,0,1),newwo);
        const float l2 = dot(newt,newt);
        newt = l2>1e-8 ? newt/sqrt(l2) : perp_stark(newwo);
        rotateFrame(newt, newwo);
    }
    [mutating] void propagate(float3 p) {
        if (!distant) {
            const float dist = length(p-posW); // m
            Theta.propagate(dist);
        }
        posW = p;
    }

    // Transforms vectors from/to the local beam frame (x aligns with t, and z with direction of propagation r).
    float3 fromLocal(float3 v) {
        return t*v.x + cross(t,r)*v.y + r*v.z;
    }
    float3 toLocal(float3 v) {
        return float3(dot(v,t), dot(v,cross(t,r)), dot(v,r));
    }

    // Discards non-Hero wavelength samples.
    // Beam carries a single wavelength henceforth.
    [mutating] void collapseToHeroWavelengthOnly() {
        hwss_comps = 1;
    }
};


/* PLT beam sourcing from light sources
*/

// Sources a randomly-polarized beam
// solidAngle - solid angle subtended by the distant source
PLTBeam pltSourceBeamDistant(const float3 dir,
                             float solidAngle,
                             const hwss_t Le,
                             const hwss_t wavelengths,
                             const float maxBeamOmega,
                             const bool forceFullyCoherent = false,
                             const uint hwssComps = hwss_samples) {
    solidAngle = min(solidAngle, maxBeamOmega);
    const float2x2 Diffusivity = forceFullyCoherent ?
        1e-9f * ident2() :
        solidAngle * ident2();

    const float3 t = perp_stark(dir);
    return PLTBeam(Le, Diffusivity, .0f, dir, t, wavelengths, true, hwssComps);
}

// Sources a randomly-polarized beam
// posW - source position
// A - sourcing area in mm^2
// dist - distance to first receiver
PLTBeam pltSourceBeamArea(const float3 posW,
                          const float3 dir,
                          float A,
                          const float dist,
                          const hwss_t Le,
                          const hwss_t wavelengths,
                          const float maxBeamOmega,
                          const bool forceFullyCoherent = false,
                          const uint hwssComps = hwss_samples) {
    const float r2 = sqr(dist * 1e+3f);     // in mm
    A = min(A, maxBeamOmega*r2);
    const float2x2 Diffusivity = forceFullyCoherent ?
        1e-7f * ident2() :
        A * ident2();

    const float3 t = perp_stark(dir);
    return PLTBeam(Le, Diffusivity, posW, dir, t, wavelengths, false, hwssComps);
}
