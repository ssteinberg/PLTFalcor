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
#pragma once
#include "Utils/HostDeviceShared.slangh"

BEGIN_NAMESPACE_FALCOR

/** Flags representing the various lobes of a BSDF.
*/
// TODO: Specify the backing type when Slang issue has been resolved
enum class LobeType // : uint32_t
{
    None                    = 0x00,

    DiffuseReflection       = 0x01,
    ScatterReflection       = 0x02,
    DeltaReflection         = 0x04,
    DispersiveDeltaReflection = 0x08,

    DiffuseTransmission     = 0x10,
    ScatterTransmission     = 0x20,
    DeltaTransmission       = 0x40,
    DispersiveDeltaTransmission = 0x80,

    Diffuse                 = 0x11,
    Scatter                 = 0x22,
    NonDispersiveDelta      = 0x44,
    DispersiveDelta         = 0x88,
    Delta                   = 0xCC,
    NonDelta                = 0x33,

    Reflection              = 0x0f,
    Transmission            = 0xf0,

    NonDeltaReflection      = 0x03,
    NonDeltaTransmission    = 0x30,

    ClientSide              = 0xff,

    // Can be used in shader code only
    All                     = 0xffff,
    MaterialSpecifc         = 0xff00,       // For materials' private use
};
static const uint LobeTypeMaterialSpecificOffset = 8;

END_NAMESPACE_FALCOR
