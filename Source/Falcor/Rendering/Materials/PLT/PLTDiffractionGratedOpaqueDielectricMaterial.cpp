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
#include "PLTDiffractionGratedOpaqueDielectricMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"

namespace Falcor
{
    namespace
    {
        const char kShaderFile[] = "Rendering/Materials/PLT/PLTDiffractionGratedOpaqueDielectricMaterial.slang";
    }

    PLTDiffractionGratedOpaqueDielectricMaterial::SharedPtr PLTDiffractionGratedOpaqueDielectricMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
    {
        return SharedPtr(new PLTDiffractionGratedOpaqueDielectricMaterial(std::move(pDevice), name));
    }

    PLTDiffractionGratedOpaqueDielectricMaterial::PLTDiffractionGratedOpaqueDielectricMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
        : BasicMaterial(std::move(pDevice), name, MaterialType::PLTDiffractionGratedOpaqueDielectric)
    {
        // Setup additional texture slots.
        mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = { "baseColor", TextureChannelFlags::RGBA, true };
        mTextureSlotInfo[(uint32_t)TextureSlot::Specular] = { "specular", TextureChannelFlags::RG, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = { "normal", TextureChannelFlags::RGB, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Data1] = { "data1", TextureChannelFlags::RGBA, false };
        mTextureSlotInfo[(uint32_t)TextureSlot::Data2] = { "data2", TextureChannelFlags::RG, false };

        setGratingPitchX(3);
        setGratingPitchY(0);
        setGratingHeight(1.f);
        setGratingHeightScale(.5f);
        setGratingPowerMultiplier(1.f);
        setGratingTypeAndLobes({ DiffractionGratingType::sinusoidal, 3 });
        setRoughness(.0f);
        guiGratingPitchY = 3.f;
    }

    Program::ShaderModuleList PLTDiffractionGratedOpaqueDielectricMaterial::getShaderModules() const
    {
        return { Program::ShaderModule(kShaderFile) };
    }

    Program::TypeConformanceList PLTDiffractionGratedOpaqueDielectricMaterial::getTypeConformances() const
    {
        return { {{"PLTDiffractionGratedOpaqueDielectricMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTDiffractionGratedOpaqueDielectric} };
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setRoughness(float roughness)
    {
        if (mData.data2[1] != (float16_t)roughness)
        {
            mData.data2[1] = (float16_t)roughness;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingDir(float dir)
    {
        if (mData.data1[2] != (float16_t)dir)
        {
            mData.data1[2] = (float16_t)dir;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPitch(float pitch)
    {
        if (mData.data1[0] != (float16_t)pitch)
        {
            mData.data1[0] = (float16_t)pitch;
            markUpdates(UpdateFlags::DataChanged);
        }
    }
    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPitchY(float pitch)
    {
        if (mData.data1[1] != (float16_t)pitch)
        {
            mData.data1[1] = (float16_t)pitch;
            markUpdates(UpdateFlags::DataChanged);
        }
        if (pitch!=0)
            guiGratingPitchY = pitch;
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingHeight(float q)
    {
        if (mData.data2[0] != (float16_t)q)
        {
            mData.data2[0] = (float16_t)q;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingHeightScale(float scale)
    {
        if (mData.specular[0] != (float16_t)scale)
        {
            mData.specular[0] = (float16_t)scale;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPowerMultiplier(float mult)
    {
        if (mData.specular[1] != (float16_t)mult)
        {
            mData.specular[1] = (float16_t)mult;
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    void PLTDiffractionGratedOpaqueDielectricMaterial::setGratingTypeAndLobes(std::pair<DiffractionGratingType, uint> val)
    {
        const auto v = uint16_t((uint(val.first)<<8) + std::min<uint>(val.second, diffractionGratingsMaxLobes));
        if (mData.data1[3] != asfloat16(v))
        {
            mData.data1[3] = asfloat16(v);
            markUpdates(UpdateFlags::DataChanged);
        }
    }

    bool PLTDiffractionGratedOpaqueDielectricMaterial::renderUI(Gui::Widgets& widget, const Scene *scene)
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

        if (auto group = widget.group("grating")) {
            const Gui::DropdownList kGratingDims = {
                { 0, "1-dimensional" },
                { 1, "2-dimensional" },
            };
            uint32_t gratingDim = getGratingPitchY()==0 ? 0 : 1;
            if (widget.dropdown("dimensionality", kGratingDims, gratingDim)) {
                if (gratingDim==0) setGratingPitchY(.0f);
                else {
                    if (guiGratingPitchY==0) guiGratingPitchY=3.f;
                    setGratingPitchY(guiGratingPitchY);
                }
            }

            auto type = uint32_t(getGratingType());
            const Gui::DropdownList kGratingTypes = {
                { 0, "sinusoidal" },
                { 1, "rectangular" },
                { 2, "linear" },
                { 0x10, "sinusoidal (UV radial)" },
                { 0x11, "rectangular (UV radial)" },
            };
            if (widget.dropdown("type", kGratingTypes, type)) setGratingType((DiffractionGratingType)type);

            float pitch = getGratingPitch();
            if (widget.var("X pitch (um)", pitch, .001f, 500.f, 0.01f)) setGratingPitch(pitch);

            if (gratingDim >= 1) {
                if (widget.var("Y pitch (um)", guiGratingPitchY, .001f, 500.f, 0.01f)) setGratingPitchY(guiGratingPitchY);
            }

            float dir = getGratingDir() * 180.f/M_PI;
            if (widget.var("direction", dir, .0f, 180.f, 0.5f)) setGratingDir(dir*M_PI/180.f);

            float q = getGratingHeightScale();
            if (widget.var("height (um)", q, .0f, 5.f, 0.01f)) setGratingHeightScale(q);

            float mult = getGratingPowerMultiplier();
            if (widget.var("intensity multiplier", mult, .0f, 10.f, 0.01f)) setGratingPowerMultiplier(mult);
            widget.tooltip("Amplifies diffraction lobes, should be set to 1.0 for physical plausibility.");

            uint lobes = getGratingLobes();
            if (widget.var("lobe count", lobes, 1u, uint(diffractionGratingsMaxLobes))) setGratingLobes(lobes);
        }

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

        if (auto pTexture = getData2Texture())
        {
            std::ostringstream oss;
            oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight()
                << " (" << to_string(pTexture->getFormat()) << ")";

            widget.text("height/roughness: " + pTexture->getSourcePath().string());
            widget.text(oss.str());

            widget.image("height/roughness", pTexture, float2(100.f));
            if (widget.button("Remove texture##Data2")) setData2Texture(nullptr);
        }
        else
        {
            float r = getRoughness();
            if (widget.var("roughness", r, .0f, 1.f, 0.001f)) setRoughness(r);
        }

        // Restore update flags.
        const auto changed = mUpdates != UpdateFlags::None;
        markUpdates(prevUpdates | mUpdates);

        return changed;
    }

    FALCOR_SCRIPT_BINDING(PLTDiffractionGratedOpaqueDielectricMaterial)
    {
        using namespace pybind11::literals;

        FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

        pybind11::class_<PLTDiffractionGratedOpaqueDielectricMaterial, BasicMaterial, PLTDiffractionGratedOpaqueDielectricMaterial::SharedPtr> material(m, "PLTDiffractionGratedOpaqueDielectricMaterial");
        auto create = [] (const std::string& name) {
            return PLTDiffractionGratedOpaqueDielectricMaterial::create(getActivePythonSceneBuilder().getDevice(), name);
        };
        material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED

        material.def_property("gratingHeight", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingHeightScale, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingHeightScale);
        material.def_property("gratingDir", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingDir, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingDir);
        material.def_property("gratingPitch", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingPitch, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPitch);
        material.def_property("gratingPitchX", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingPitchX, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPitchX);
        material.def_property("gratingPitchY", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingPitchY, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPitchY);
        material.def_property("gratingPowerMultiplier", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingPowerMultiplier, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingPowerMultiplier);
        material.def_property("gratingType", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingType, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingType);
        material.def_property("lobeCount", &PLTDiffractionGratedOpaqueDielectricMaterial::getGratingLobes, &PLTDiffractionGratedOpaqueDielectricMaterial::setGratingLobes);
    }
}
