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
#include "PLTDielectricMaterial.h"
#include "Scene/SceneBuilderAccess.h"

#include "Utils/Scripting/ScriptBindings.h"

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTDielectricMaterial.slang";
    }

    PLTDielectricMaterial::SharedPtr PLTDielectricMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTDielectricMaterial(std::move(pDevice), name));
    }

    PLTDielectricMaterial::PLTDielectricMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTDielectric)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGB, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Specular] = { "specular", TextureChannelFlags::RG | TextureChannelFlags::Alpha, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Transmission] = { "transmission", TextureChannelFlags::RGB, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };

        setBaseColor(float4{ 1.f });
        setExtIndexOfRefraction(1.f);
        setTransmissionColor(float3{ 1.f });
        setAbbeNumber(100.f);
    }

    Program::ShaderModuleList PLTDielectricMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTDielectricMaterial::getTypeConformances() const
    {
        return { {{"PLTDielectricMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTDielectric} };
    }

    void PLTDielectricMaterial::setRoughness(float roughness)
    {
        if (mData.specular[1] != (float16_t)roughness)
        {
            mData.specular[1] = (float16_t)roughness;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDielectricMaterial::setExtIndexOfRefraction(float ior)
    {
        if (mData.specular[3] != (float16_t)ior)
        {
            mData.specular[3] = (float16_t)ior;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDielectricMaterial::setDispersion(float B)
    {
        if (mData.specular[0] != (float16_t)B)
        {
            mData.specular[0] = (float16_t)B;
            markUpdates(UpdateFlags::DataChanged);
        }
    }
    void PLTDielectricMaterial::setAbbeNumber(float abbe)
    {
        if (std::fabs(abbe) <= FLT_EPSILON)
            throw std::runtime_error("abbe must be non-zero");

        setDispersion(.52f * (getIndexOfRefraction()-1) / abbe);
    }

    float PLTDielectricMaterial::getAbbeNumber() const {
        return .52f * (getIndexOfRefraction()-1) / getDispersion();
    }

    bool PLTDielectricMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
    {
        // We're re-using the material's update flags here to track changes.
        // Cache the previous flag so we can restore it before returning.
        UpdateFlags prevUpdates = mUpdates;
        mUpdates = UpdateFlags::None;

        widget.text("Type: " + to_string(getType()));

        if (auto pTexture = getNormalMap())
        {
            widget.text("Normal map: " + pTexture->getSourcePath().string());
            widget.text("Texture info: " + std::to_string(pTexture->getWidth()) + "x" + std::to_string(pTexture->getHeight()) + " (" + to_string(pTexture->getFormat()) + ")");
            widget.image("Normal map", pTexture, float2(100.f));
            if (widget.button("Remove texture##NormalMap")) setNormalMap(nullptr);
        }

        float ior = getIndexOfRefraction();
        if (widget.var("index of refraction", ior, 1.f, 3.f, 0.025f)) setIndexOfRefraction(ior);

        float roughness = getRoughness();
        if (widget.var("roughness", roughness, .0f, 1.f, 0.001f)) setRoughness(roughness);

        float dispersion = getDispersion();
        if (widget.var("dispersion (Cauchy B coefficient)", dispersion, -.2f, .2f, .0002f)) setDispersion(dispersion);

        if (auto pTexture = getBaseColorTexture())
        {
            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";

            widget.text("specular reflectance: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            widget.image("specular reflectance", pTexture, float2(100.f));
            if (widget.button("Remove texture##BaseColor")) setBaseColorTexture(nullptr);
        }
        else
        {
            float3 spec = getBaseColor().xyz;
            if (widget.rgbColor("specular reflectance", spec)) setBaseColor({ spec, 1.f });
        }

        if (auto pTexture = getTransmissionTexture())
        {
            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";

            widget.text("transmission reflectance: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            widget.image("transmission reflectance", pTexture, float2(100.f));
            if (widget.button("Remove texture##Transmission")) setTransmissionTexture(nullptr);
        }
        else
        {
            float3 tran = getTransmissionColor();
            if (widget.rgbColor("transmission reflectance", tran)) setTransmissionColor(tran);
        }

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTDielectricMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTDielectricMaterial, BasicMaterial, PLTDielectricMaterial::SharedPtr> material(m, "PLTDielectricMaterial");
        auto create = [] (const std::string& name) {
            return PLTDielectricMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED

        material.def_property("roughness", &PLTDielectricMaterial::getRoughness, &PLTDielectricMaterial::setRoughness);
        material.def_property("abbe", &PLTDielectricMaterial::getAbbeNumber, &PLTDielectricMaterial::setAbbeNumber);
        material.def_property("dispersion", &PLTDielectricMaterial::getDispersion, &PLTDielectricMaterial::setDispersion);
        material.def_property("extIOR", &PLTDielectricMaterial::getExtIndexOfRefraction, &PLTDielectricMaterial::setExtIndexOfRefraction);
    }
}
