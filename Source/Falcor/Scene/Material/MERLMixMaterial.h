/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
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
#include "Material.h"
#include "MERLMixMaterialData.slang"

namespace Falcor
{
    class BufferAllocator;

    /** Measured material that can mix BRDFs from the MERL BRDF database.

        The class loads a list of MERL BRDFs and allows blending between them at runtime.
        The blending can be textured to create mosaics of spatially varying BRDFs.

        For details refer to:
        Wojciech Matusik, Hanspeter Pfister, Matt Brand and Leonard McMillan.
        "A Data-Driven Reflectance Model". ACM Transactions on Graphics,
        vol. 22(3), 2003, pages 759-769.
    */
    class FALCOR_API MERLMixMaterial : public Material
    {
    public:
        using SharedPtr = std::shared_ptr<MERLMixMaterial>;

        /** Create a new MERLMix material.
            \param[in] name The material name.
            \param[in] paths List of paths of BRDF files to load.
            \return A new object, or throws an exception if creation failed.
        */
        static SharedPtr create(std::shared_ptr<Device> pDevice, const std::string& name, const std::vector<std::filesystem::path>& paths);

        bool renderUI(Gui::Widgets& widget) override;
        Material::UpdateFlags update(MaterialSystem* pOwner) override;
        bool isEqual(const Material::SharedPtr& pOther) const override;
        MaterialDataBlob getDataBlob() const override { return prepareDataBlob(mData); }
        Program::ShaderModuleList getShaderModules() const override;
        Program::TypeConformanceList getTypeConformances() const override;
        int getBufferCount() const override { return 1; }

        bool setTexture(const TextureSlot slot, const Texture::SharedPtr& pTexture) override;
        void setDefaultTextureSampler(const Sampler::SharedPtr& pSampler) override;
        Sampler::SharedPtr getDefaultTextureSampler() const override { return mpDefaultSampler; }

        void setNormalMap(const Texture::SharedPtr& pNormalMap) { setTexture(TextureSlot::Normal, pNormalMap); }
        Texture::SharedPtr getNormalMap() const { return getTexture(TextureSlot::Normal); }

    protected:
        MERLMixMaterial(std::shared_ptr<Device> pDevice, const std::string& name, const std::vector<std::filesystem::path>& paths);

        void updateNormalMapType();
        void updateIndexMapType();

        struct BRDFDesc
        {
            std::string name;               ///< Name of the BRDF. This is the file basename without extension.
            std::filesystem::path path;     ///< Full path to the loaded BRDF file.
            size_t byteOffset = 0;          ///< Offset in bytes to where the BRDF data is stored in the shared data buffer.
            size_t byteSize = 0;            ///< Size in bytes of the BRDF data.

            bool operator==(const BRDFDesc& rhs) const
            {
                return name == rhs.name && path == rhs.path;
            }
        };

        std::vector<BRDFDesc> mBRDFs;       ///< List of loaded BRDFs.

        MERLMixMaterialData mData;          ///< Material parameters.
        Buffer::SharedPtr mpBRDFData;       ///< GPU buffer holding all BRDF data as float3 arrays.
        Texture::SharedPtr mpAlbedoLUT;     ///< Precomputed albedo lookup table.
        Sampler::SharedPtr mpLUTSampler;    ///< Sampler for accessing the LUT texture.
        Sampler::SharedPtr mpIndexSampler;  ///< Sampler for accessing the index map.
        Sampler::SharedPtr mpDefaultSampler;
    };
}
