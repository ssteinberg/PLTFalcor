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

namespace Falcor
{
    /** This class implements an alternating stack of dielectric layers material.

        Texture channel layout:

            BaseColor
                - RGB - Base reflectance color
            Data1
                - R - Thickness 1
                - G - Thickness 2
                - A - Layers count
            Data2
                - R - IOR 1
                - G - IOR 2
            Normal
                - 3-Channel standard normal map, or 2-Channel BC5 format

        See additional texture channels defined in BasicMaterial.
    */
    class FALCOR_API PLTMultiLayeredStackMaterial : public BasicMaterial
    {
    public:
        using SharedPtr = std::shared_ptr<PLTMultiLayeredStackMaterial>;

        /** Create a new PLTMultiLayeredStack material.
            \param[in] name The material name.
        */
        static SharedPtr create(std::shared_ptr<Device> pDevice, const std::string& name = "");

        Program::ShaderModuleList getShaderModules() const override;
        Program::TypeConformanceList getTypeConformances() const override;

        // Thickness in um
        void setThickness1(float thickness);
        float getThickness1() const { return (float)mData.data1[0]; }
        void setThickness2(float thickness);
        float getThickness2() const { return (float)mData.data1[1]; }

        void setIndexOfRefraction1(float ior);
        float getIndexOfRefraction1() const { return (float)mData.data2[0]; }
        void setIndexOfRefraction2(float ior);
        float getIndexOfRefraction2() const { return (float)mData.data2[1]; }

        void setExtIndexOfRefraction(float ior) { setIndexOfRefraction(ior); }
        float getExtIndexOfRefraction() const { return getIndexOfRefraction(); }

        void setLayersCount(uint layers);
        uint getLayersCount() const { return (uint)asuint16(mData.data1[3]); }

        bool renderUI(Gui::Widgets& widget, const Scene* scene);

    protected:
        PLTMultiLayeredStackMaterial(std::shared_ptr<Device> pDevice, const std::string& name);
    };
}
