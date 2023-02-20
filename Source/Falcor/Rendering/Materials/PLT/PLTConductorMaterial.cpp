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
#include "PLTConductorMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTConductorMaterial.slang";
    }

    PLTConductorMaterial::SharedPtr PLTConductorMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTConductorMaterial(std::move(pDevice), name));
    }

    PLTConductorMaterial::PLTConductorMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTConductor)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGB, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Specular] = { "specular", TextureChannelFlags::Green, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };

        setBaseColor(float4{ 1.f });
        setExtIndexOfRefraction(1.f);
        setSpecularParams(float4{ 1.f });
        setRoughness(.0f);
        setGamma(3.f);
    }

    Program::ShaderModuleList PLTConductorMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTConductorMaterial::getTypeConformances() const
    {
        return { {{"PLTConductorMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTConductor} };
    }

    void PLTConductorMaterial::setGamma(float gamma)
    {
        if (mData.specular[0] != (float16_t)gamma)
        {
            mData.specular[0] = (float16_t)gamma;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTConductorMaterial::setRoughness(float roughness)
    {
        if (mData.specular[1] != (float16_t)roughness)
        {
            mData.specular[1] = (float16_t)roughness;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    bool PLTConductorMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
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

        if (auto pTexture = getSpecularTexture())
        {
            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";

            widget.text("roughness: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            widget.image("roughness", pTexture, float2(100.f));
            if (widget.button("Remove texture##Specular")) setSpecularTexture(nullptr);
        }
        else
        {
            float roughness = getRoughness();
            if (widget.var("roughness", roughness, .0f, 1.f, 0.001f)) setRoughness(roughness);
        }

        float gamma = getGamma();
        if (widget.var("gamma", gamma, .125f, 5.f, 0.01f)) setGamma(gamma);

        const auto& profileN = scene->getSpectralProfile(getIORSpectralProfile().first.get());
        const auto& profileK = scene->getSpectralProfile(getIORSpectralProfile().second.get());
        widget.text("index of refraction");
        widget.graph("", BasicMaterial::UIHelpers::grapher, (void*)&profileN, BasicMaterial::UIHelpers::grapher_bins, 0);
        widget.graph("", BasicMaterial::UIHelpers::grapher, (void*)&profileK, BasicMaterial::UIHelpers::grapher_bins, 0);

        float extIOR = getExtIndexOfRefraction();
        if (widget.var("ext IOR", extIOR, 1.f, 3.f, 0.1f))
            setExtIndexOfRefraction(extIOR);

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

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTConductorMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTConductorMaterial, BasicMaterial, PLTConductorMaterial::SharedPtr> material(m, "PLTConductorMaterial");
        auto create = [] (const std::string& name) {
            return PLTConductorMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED

        material.def_property("roughness", &PLTConductorMaterial::getRoughness, &PLTConductorMaterial::setRoughness);
        material.def_property("gamma", &PLTConductorMaterial::getGamma, &PLTConductorMaterial::setGamma);
        material.def_property("extIOR", &PLTConductorMaterial::getExtIndexOfRefraction, &PLTConductorMaterial::setExtIndexOfRefraction);
    }
}
