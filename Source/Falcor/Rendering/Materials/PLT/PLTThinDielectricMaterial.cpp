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
#include "PLTThinDielectricMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTThinDielectricMaterial.slang";
    }

    PLTThinDielectricMaterial::SharedPtr PLTThinDielectricMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTThinDielectricMaterial(std::move(pDevice), name));
    }

    PLTThinDielectricMaterial::PLTThinDielectricMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTThinDielectric)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGB, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Specular] = { "specular", TextureChannelFlags::Red | TextureChannelFlags::Alpha, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };

        setSpecularParams(float4{ .0f });
        setBirefringenceOpticAxis(float3{ 0,0,1 });
        setThickness(.0003f);
        setBirefringence(.0f);
    }

    Program::ShaderModuleList PLTThinDielectricMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTThinDielectricMaterial::getTypeConformances() const
    {
        return { {{"PLTThinDielectricMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTThinDielectric} };
    }

    void PLTThinDielectricMaterial::setThickness(float tau)
    {
        if (mData.specular[3] != (float16_t)tau)
        {
            mData.specular[3] = (float16_t)tau;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTThinDielectricMaterial::setBirefringence(float birefringence)
    {
        if (mData.baseColor[0] != (float16_t)birefringence)
        {
            mData.baseColor[0] = (float16_t)birefringence;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTThinDielectricMaterial::setBirefringenceOpticAxis(float3 axis)
    {
        axis = normalize(axis);
        if (axis.z<0) axis=-axis;
        if (mData.baseColor[1] != (float16_t)axis.x || mData.baseColor[2] != (float16_t)axis.y)
        {
            mData.baseColor[1] = (float16_t)axis.x;
            mData.baseColor[2] = (float16_t)axis.y;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    bool PLTThinDielectricMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
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
        if (widget.var("IOR", ior, 1.f, 3.f, 0.025f))
            setIndexOfRefraction(ior);

        float tau = getThickness() * 1e+6f;
        if (widget.var("tau (um)", tau, 0.f, 1000.f, 0.5f)) setThickness(tau / 1e+3f);

        float birefringence = getBirefringence();
        if (widget.var("birefringence", birefringence, -.5f, .5f, 0.01f)) setBirefringence(birefringence);

        float3 opticAxis = getBirefringenceOpticAxis();
        if (widget.direction("opticAxis", opticAxis)) setBirefringenceOpticAxis(opticAxis);

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTThinDielectricMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTThinDielectricMaterial, BasicMaterial, PLTThinDielectricMaterial::SharedPtr> material(m, "PLTThinDielectricMaterial");
        auto create = [] (const std::string& name) {
            return PLTThinDielectricMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED

        material.def_property("thickness", &PLTThinDielectricMaterial::getThickness, &PLTThinDielectricMaterial::setThickness);
        material.def_property("birefringence", &PLTThinDielectricMaterial::getBirefringence, &PLTThinDielectricMaterial::setBirefringence);
        material.def_property("opticAxis", &PLTThinDielectricMaterial::getBirefringenceOpticAxis, &PLTThinDielectricMaterial::setBirefringenceOpticAxis);
    }
}
