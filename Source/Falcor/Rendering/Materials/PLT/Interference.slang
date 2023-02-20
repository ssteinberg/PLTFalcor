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


// Phase shift resulting in propagation of dist, in refractive index eta, at wavenumber k, and with potential induced phase shift due to phasor r
float phaseShift(const float eta, const float dist, const float k, const float2 r = float2(0)) {
    const float arg = carg(r);
    return sin(dist*k*eta + arg);
}
hwss_t phaseShift(const float eta, const float dist, const hwss_t ks) {
    return sin(dist*ks*eta);
}
// Interference between 2 Stokes parameters vectors, w.r.t. s- and p-polarized phasors (cosines of optical distance differences) and mutual coherence
float4 interfere(const float4 SP1, const float4 SP2, const float phasor_s, const float phasor_p, const float coh) {
    const float S1 = (SP1.x+SP1.y)/2.f;
    const float P1 = (SP1.x-SP1.y)/2.f;
    const float S2 = (SP2.x+SP2.y)/2.f;
    const float P2 = (SP2.x-SP2.y)/2.f;

    // Interfere each transverse component
    const float S = S1+S2 + 2*sqrt(max(.0f,S1*S2))*phasor_s*coh;
    const float P = P1+P2 + 2*sqrt(max(.0f,P1*P2))*phasor_p*coh;

    // Rebuild Stokes parameters
    const float n = SP1.x+SP2.x>1e-6f ? (S+P)/(SP1.x+SP2.x) : .0f;
    return float4(S+P, S-P, (SP1.z+SP2.z)*n, (SP1.w+SP2.w)*n);
}
