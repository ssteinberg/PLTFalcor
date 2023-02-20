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
#include "Scene/Material/BasicMaterial.h"
#include "Rendering/Materials/PLT/DiffractionGrating.slangh"

namespace Falcor
{
    /** This class implements a diffraction-grated conductor material.
     * It has a base conductor lobe (specular), and additionally it disperses light into diffracted lobes.

        Texture channel layout:

            BaseColor
                - RGB - Reflectance color modulator
            Specular
                - R - grating height scale
                - G - diffraction lobes amplifier (physical = 1)
            Data1
                - RG - grating pitch XY
                - B - grating dir
                - A - type and lobes
            Data2
                - R - grating height (Q)
                - G - roughness
            Normal
                - 3-Channel standard normal map, or 2-Channel BC5 format

        See additional texture channels defined in BasicMaterial.
    */
    class FALCOR_API PLTDiffractionGratedConductorMaterial : public BasicMaterial
    {
    public:
        using SharedPtr = std::shared_ptr<PLTDiffractionGratedConductorMaterial>;

        /** Create a new PLTDiffractionGratedConductor material.
            \param[in] name The material name.
        */
        static SharedPtr create(std::shared_ptr<Device> pDevice, const std::string& name = "");

        Program::ShaderModuleList getShaderModules() const override;
        Program::TypeConformanceList getTypeConformances() const override;

        void setExtIndexOfRefraction(float ior) { setIndexOfRefraction(ior); }
        float getExtIndexOfRefraction() const { return getIndexOfRefraction(); }

        void setGratingHeight(float q);
        float getGratingHeight() const { return (float)mData.data2[0]; }
        void setGratingHeightScale(float scale);
        float getGratingHeightScale() const { return (float)mData.specular[0]; }

        void setGratingDir(float dir);
        float getGratingDir() const { return (float)mData.data1[2]; }

        void setRoughness(float roughness);
        float getRoughness() const { return (float)mData.data2[1]; }

        void setGratingPitch(float pitch);
        float getGratingPitch() const { return (float)mData.data1[0]; }
        void setGratingPitchX(float pitch) { setGratingPitch(pitch); }
        float getGratingPitchX() const { return getGratingPitch(); }
        void setGratingPitchY(float pitch);
        float getGratingPitchY() const { return (float)mData.data1[1]; }

        // Shouldn't be set (defaults to 1)
        void setGratingPowerMultiplier(float mult);
        float getGratingPowerMultiplier() const { return (float)mData.specular[1]; }

        void setGratingTypeAndLobes(std::pair<DiffractionGratingType, uint> val);
        std::pair<DiffractionGratingType, uint> getGratingTypeAndLobes() const {
            const auto val = asuint16(mData.data1[3]);
            const auto type = (DiffractionGratingType)(val >> 8);
            const auto lobes = uint(val) & 0xFF;
            return std::pair<DiffractionGratingType, uint>{ type, lobes };
        }
        DiffractionGratingType getGratingType() const { return getGratingTypeAndLobes().first; }
        uint getGratingLobes() const { return getGratingTypeAndLobes().second; }
        void setGratingType(DiffractionGratingType type) { setGratingTypeAndLobes({ type, getGratingLobes() }); }
        void setGratingLobes(uint lobes) { setGratingTypeAndLobes({ getGratingType(), lobes }); }

        bool renderUI(Gui::Widgets& widget, const Scene* scene);

    protected:
        PLTDiffractionGratedConductorMaterial(std::shared_ptr<Device> pDevice, const std::string& name);

        float guiGratingPitchY{};
    };
}
