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

#pragma once

#include "pltpt_constants.slangh"

import Scene.Scene;
import Scene.HitInfo;

import Rendering.PLT;
import Rendering.Materials.LobeType;

import Utils.HWSS;
import Utils.Color.SpectrumSampler;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Math.MathHelpers;


struct RayFlags {
    enum class Flags {
        lastBounceWasDelta          = 0x1,
        hasDispersiveDeltaSegment   = 0x2,
        onlyDelta                   = 0x4,

        miss                        = 0x10,
        terminated                  = 0x20,

        MSCompatibleBouncesMask     = 0xffff0000,
    };
    static const int RayFlagsMSCompatibleMaskOffset = 16;

    uint flags;

    property MSCompatibleBounces : uint {
        get { return flags>>RayFlagsMSCompatibleMaskOffset; }
        set {
            flags &= ~(uint)Flags::MSCompatibleBouncesMask;
            flags |= newValue<<RayFlagsMSCompatibleMaskOffset;
        }
    }
    property lastBounceWasDelta : bool {
        get { return (flags & (uint)Flags::lastBounceWasDelta)!=0; }
        set {
            if (newValue) flags |=  (uint)Flags::lastBounceWasDelta;
            else          flags &= ~(uint)Flags::lastBounceWasDelta;
        }
    }
    property dispersiveDeltaSegment : bool {
        get { return (flags & (uint)Flags::hasDispersiveDeltaSegment)!=0; }
        set {
            if (newValue) flags |=  (uint)Flags::hasDispersiveDeltaSegment;
            else          flags &= ~(uint)Flags::hasDispersiveDeltaSegment;
        }
    }
    property onlyDelta : bool {
        get { return (flags & (uint)Flags::onlyDelta)!=0; }
        set {
            if (newValue) flags |=  (uint)Flags::onlyDelta;
            else          flags &= ~(uint)Flags::onlyDelta;
        }
    }

    property miss : bool {
        get { return (flags & (uint)Flags::miss)!=0; }
        set {
            if (newValue) flags |=  (uint)Flags::miss;
            else          flags &= ~(uint)Flags::miss;
        }
    }
    property terminated : bool {
        get { return (flags & (uint)Flags::terminated)!=0; }
        set {
            if (newValue) flags |=  (uint)Flags::terminated;
            else          flags &= ~(uint)Flags::terminated;
        }
    }

    property valid : bool {
        get { return !this.miss && !this.terminated; }
    }
}


/** Bounce information */
struct BounceData {
    // 16B
    PackedHitInfo hit;
    // 8B
    float2 encodedWi;
    // 4B
    uint sampledBsdfLobe;
    // 3x4B
    RayFlags flags;
    float pathContribution;
    float lastNonDeltaPdf;

    property wi : float3 {
        get { return oct_to_ndir_equal_area_snorm(encodedWi); }
        set { encodedWi = ndir_to_oct_equal_area_snorm(newValue); }
    }

    property delta : bool {
        get { return (sampledBsdfLobe & (uint)LobeType::Delta)!=0; }
    }
    property dispersiveDelta : bool {
        get { return (sampledBsdfLobe & (uint)LobeType::DispersiveDelta)!=0; }
    }
    property nonDispersiveDelta : bool {
        get { return (sampledBsdfLobe & (uint)LobeType::NonDispersiveDelta)!=0; }
    }
    property transmission : bool {
        get { return (sampledBsdfLobe & (uint)LobeType::Transmission)!=0; }
    }
};


/** Payload for scatter ray */
struct Path {
    // 16B
    SampleGenerator sg;             ///< Per-ray sample generator

    // 3x12B
    float3 origin, dir, normal;     ///< Ray tracing data for next path segment

    // 4x4B
    float wavelength;               ///< Backward sampling wavelength
    float weight;                   ///< Path backward weight estimate (via fully-coherent tracing)
    float pdf;                      ///< Path backward sampling pdf
    float thp_modifier;             ///< thp modifier (e.g., for thp-boosting Russian Roulette)

    // 4x4B
    uint id;                        ///< Path ID encodes pixel with 16 bits each for pixel x|y
    int length;                     ///< Path length in number of path segments (0 at origin)
    RayFlags flags;                 ///< Ray status and flags
    float lastNonDeltaPdf;          ///< BSDF sampling PDF of the last non-delta bounce (for MIS)

    __init(SampleGenerator sg, uint2 pixel, uint2 frameDim, float wl) {
        uint pathID = (pixel.y << 16) | pixel.x;
        this.id = pathID;

        Ray ray = gScene.camera.computeRayPinhole(pixel, frameDim);
        this.origin = ray.origin;
        this.dir = ray.dir;
        this.normal = normalize(gScene.camera.data.cameraW);

        this.length = 0;

        this.sg = sg;

        this.wavelength = wl;
        this.weight = 1.f;
        this.pdf = 1.f;
        this.thp_modifier = 1.f;
        this.lastNonDeltaPdf = .0f;

        this.flags.flags = 0;
        this.flags.onlyDelta = true;
    }

    uint2 getPixel() { return uint2(id & 0xffff, id >> 16); }

    [mutating] void endPath() {
        flags.terminated = true;
    }
    [mutating] void flagMiss() {
        flags.miss = true;
    }
};


/** Payload for solve stage */
struct PLTSolve {
    SampleGenerator sg, tilesg;

    float3 Lrgb;
#if DO_DEBUG_VIEW==1
    float4 debugOutput;
#endif

    float3 pathOrigin;
    float3 pathNormal;

    float wavelength;

    __init(SampleGenerator sg, SampleGenerator tilesg, float wl) {
        this.sg = sg;
        this.tilesg = tilesg;

        this.Lrgb = .0f;
#if DO_DEBUG_VIEW==1
        this.debugOutput = .0f;
#endif

        this.pathOrigin = gScene.camera.getPosition();
        this.pathNormal = normalize(gScene.camera.data.cameraW);

        this.wavelength = wl;
    }
};
