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
#include "PLTMultiLayeredStackMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTMultiLayeredStackMaterial.slang";
    }

    PLTMultiLayeredStackMaterial::SharedPtr PLTMultiLayeredStackMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTMultiLayeredStackMaterial(std::move(pDevice), name));
    }

    PLTMultiLayeredStackMaterial::PLTMultiLayeredStackMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTMultiLayeredStack)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGB, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Data1] = { "data1", TextureChannelFlags::RGBA, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Data2] = { "data2", TextureChannelFlags::RG, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };

        setBaseColor(float4{ 1.f });
        setTransmissionColor(float4{ .0f });
        setThickness1(.1f);
        setThickness2(.2f);
        setExtIndexOfRefraction(1);
        setIndexOfRefraction1(1.3f);
        setIndexOfRefraction2(1.2f);
        setLayersCount(2);
    }

    Program::ShaderModuleList PLTMultiLayeredStackMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTMultiLayeredStackMaterial::getTypeConformances() const
    {
        return { {{"PLTMultiLayeredStackMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTMultiLayeredStack} };
    }

    void PLTMultiLayeredStackMaterial::setThickness1(float thickness)
    {
        if (mData.data1[0] != (float16_t)thickness)
        {
            mData.data1[0] = (float16_t)thickness;
            markUpdates(UpdateFlags::DataChanged);
        }
    }
    void PLTMultiLayeredStackMaterial::setThickness2(float thickness)
    {
        if (mData.data1[1] != (float16_t)thickness)
        {
            mData.data1[1] = (float16_t)thickness;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTMultiLayeredStackMaterial::setIndexOfRefraction1(float ior)
    {
        if (mData.data2[0] != (float16_t)ior)
        {
            mData.data2[0] = (float16_t)ior;
            markUpdates(UpdateFlags::DataChanged);
        }
    }
    void PLTMultiLayeredStackMaterial::setIndexOfRefraction2(float ior)
    {
        if (mData.data2[1] != (float16_t)ior)
        {
            mData.data2[1] = (float16_t)ior;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTMultiLayeredStackMaterial::setLayersCount(uint count)
    {
        if (mData.data1[3] != asfloat16(uint16_t(count)))
        {
            mData.data1[3] = asfloat16(uint16_t(count));
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    bool PLTMultiLayeredStackMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
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

        float ior1 = getIndexOfRefraction1();
        if (widget.var("IOR1", ior1, 1.f, 3.f, 0.025f)) setIndexOfRefraction1(ior1);
        float ior2 = getIndexOfRefraction2();
        if (widget.var("IOR2", ior2, 1.f, 3.f, 0.025f)) setIndexOfRefraction2(ior2);

        float thickness1 = getThickness1();
        if (widget.var("thickness1 (um)", thickness1, .0f, 10.f, 0.005f)) setThickness1(thickness1);
        float thickness2 = getThickness2();
        if (widget.var("thickness2 (um)", thickness2, .0f, 10.f, 0.005f)) setThickness2(thickness2);

        uint layers = getLayersCount();
        if (widget.slider("layers", layers, 1u, 10u)) setLayersCount(layers);

        if (auto pTexture = getBaseColorTexture())
        {
            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";

            widget.text("base reflectance: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            widget.image("base reflectance", pTexture, float2(100.f));
            if (widget.button("Remove texture##BaseColor")) setBaseColorTexture(nullptr);
        }
        else
        {
            float3 spec = getBaseColor().xyz;
            if (widget.rgbColor("base reflectance", spec)) setBaseColor({ spec, 1.f });
        }

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTMultiLayeredStackMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTMultiLayeredStackMaterial, BasicMaterial, PLTMultiLayeredStackMaterial::SharedPtr> material(m, "PLTMultiLayeredStackMaterial");
        auto create = [] (const std::string& name) {
            return PLTMultiLayeredStackMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED

        material.def_property("thickness1", &PLTMultiLayeredStackMaterial::getThickness1, &PLTMultiLayeredStackMaterial::setThickness1);
        material.def_property("thickness2", &PLTMultiLayeredStackMaterial::getThickness2, &PLTMultiLayeredStackMaterial::setThickness2);
        material.def_property("extIOR", &PLTMultiLayeredStackMaterial::getExtIndexOfRefraction, &PLTMultiLayeredStackMaterial::setExtIndexOfRefraction);
        material.def_property("IOR1", &PLTMultiLayeredStackMaterial::getIndexOfRefraction1, &PLTMultiLayeredStackMaterial::setIndexOfRefraction1);
        material.def_property("IOR2", &PLTMultiLayeredStackMaterial::getIndexOfRefraction2, &PLTMultiLayeredStackMaterial::setIndexOfRefraction2);
        material.def_property("layers", &PLTMultiLayeredStackMaterial::getLayersCount, &PLTMultiLayeredStackMaterial::setLayersCount);
    }
}
