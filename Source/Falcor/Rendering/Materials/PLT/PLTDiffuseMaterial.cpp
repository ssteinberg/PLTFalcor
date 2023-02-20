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
#include "PLTDiffuseMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"
#include "Utils/Color/SpectrumUtils.h"
#include "Scene/Scene.h"
#include <imgui.h>

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTDiffuseMaterial.slang";
    }

    PLTDiffuseMaterial::SharedPtr PLTDiffuseMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTDiffuseMaterial(std::move(pDevice), name));
    }

    PLTDiffuseMaterial::PLTDiffuseMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTDiffuse)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGB, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };
    }

    Program::ShaderModuleList PLTDiffuseMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTDiffuseMaterial::getTypeConformances() const
    {
        return { {{"PLTDiffuseMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTDiffuse} };
    }

    bool PLTDiffuseMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
    {
        // We're re-using the material's update flags here to track changes.
        // Cache the previous flag so we can restore it before returning.
        UpdateFlags prevUpdates = mUpdates;
        mUpdates = UpdateFlags::None;

        widget.text("Type: " + to_string(getType()));

        if (auto pTexture = getBaseColorTexture())
        {
            bool hasAlpha = isAlphaSupported() && doesFormatHaveAlpha(pTexture->getFormat());
            bool alphaConst = mIsTexturedAlphaConstant && hasAlpha;
            bool colorConst = mIsTexturedBaseColorConstant;

            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";
            if (colorConst && !alphaConst) oss << " (color constant)";
            else if (!colorConst && alphaConst) oss << " (alpha constant)";
            else if (colorConst && alphaConst) oss << " (color and alpha constant)"; // Shouldn't happen

            widget.text("Base color: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            if (colorConst || alphaConst)
            {
                float4 baseColor = getBaseColor();
                if (widget.var("Base color", baseColor, 0.f, 1.f, 0.01f)) setBaseColor(baseColor);
            }

            widget.image("Base color", pTexture, float2(100.f));
            if (widget.button("Remove texture##BaseColor")) setBaseColorTexture(nullptr);
        }
        else
        {
            float4 baseColor = getBaseColor();
            if (widget.var("Base color", baseColor, 0.f, 1.f, 0.01f)) setBaseColor(baseColor);
        }

        if (auto pTexture = getNormalMap())
        {
            widget.text("Normal map: " + pTexture->getSourcePath().string());
            widget.text("Texture info: " + std::to_string(pTexture->getWidth()) + "x" + std::to_string(pTexture->getHeight()) + " (" + to_string(pTexture->getFormat()) + ")");
            widget.image("Normal map", pTexture, float2(100.f));
            if (widget.button("Remove texture##NormalMap")) setNormalMap(nullptr);
        }

        const float3& emission = isEmissive() ? scene->getSpectralProfile(getEmissionSpectralProfile().get()).rgb : float3(.0f);
        const float intensity = std::max(1.f,std::max(emission.r, std::max(emission.g, emission.b)));
        if (isEmissive()) {
            const auto& profile = scene->getSpectralProfile(getEmissionSpectralProfile().get());
            widget.graph("emission spectrum", BasicMaterial::UIHelpers::grapher, (void*)&profile, BasicMaterial::UIHelpers::grapher_bins, 0);
            widget.rgbColor("", emission/intensity);
        }

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTDiffuseMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTDiffuseMaterial, BasicMaterial, PLTDiffuseMaterial::SharedPtr> material(m, "PLTDiffuseMaterial");
        auto create = [] (const std::string& name) {
            return PLTDiffuseMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED
    }
}
