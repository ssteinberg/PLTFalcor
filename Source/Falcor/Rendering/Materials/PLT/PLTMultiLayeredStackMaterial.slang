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
__exported import Rendering.Materials.IMaterial;
__exported import Rendering.Materials.PLT.PLTMultiLayeredStackBSDF;
import Scene.Material.BasicMaterialData;
import Scene.Material.ShadingUtils;

struct PLTMultiLayeredStackMaterial : MaterialBase, IMaterial
{
    BasicMaterialData data;

    typedef PLTMultiLayeredStackBSDF MaterialInstance;

    PLTMultiLayeredStackBSDF setupMaterialInstance(const MaterialSystem ms, const ShadingData sd, const ITextureSampler lod)
    {
        SamplerState s = ms.getTextureSampler(header.getDefaultTextureSamplerID());
        const float4 base = ms.sampleTexture(data.texBaseColor, s, sd.uv, data.baseColor, lod);
        const float4 data1 = ms.sampleTexture(data.texData1, s, sd.uv, data.data1, lod);
        const float2 data2 = ms.sampleTexture(data.texData2, s, sd.uv, data.data2, lod).rg;

        const float extIor = data.IoR;
        const float ior1 = data2.x;
        const float ior2 = data2.y;
        const float thickness1 = data1.x;
        const float thickness2 = data1.y;
        const uint layers = (uint)asuint16(data.data1.w);

        PLTMultiLayeredStackBSDF brdf = {{ base.rgb, extIor, float2(ior1,ior2), float2(thickness1,thickness2), layers }};

        return brdf;
    }

    void modifyTangentSpace(const MaterialSystem ms, const ITextureSampler lod, inout ShadingData sd)
    {
        SamplerState s = ms.getTextureSampler(header.getDefaultTextureSamplerID());
        float3 encodedNormal = ms.sampleTexture(data.texNormalMap, s, sd.uv, float4(0.f), lod).rgb;
        applyNormalMap(sd, data.getNormalMapType(), encodedNormal);
    }

    float evalOpacity(const MaterialSystem ms, const VertexData v, const ITextureSampler lod)
    {
        SamplerState s = ms.getTextureSampler(header.getDefaultTextureSamplerID());
        return ms.sampleTexture(data.texBaseColor, s, v.texC, data.baseColor, lod).a;
    }
};
