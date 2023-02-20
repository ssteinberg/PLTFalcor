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
    /** This class implements a smooth, thin dielectric slab material. This material can be birefringent or act as a polarizer.

        Texture channel layout:

            BaseColor
                - R - Birefringence
                - G - Birefringence optic axis X
                - B - Birefringence optic axis Y
            Specular
                - R - Birefringence scale
                - A - Thickness
            Normal
                - 3-Channel standard normal map, or 2-Channel BC5 format

        See additional texture channels defined in BasicMaterial.
    */
    class FALCOR_API PLTThinDielectricMaterial : public BasicMaterial
    {
    public:
        using SharedPtr = std::shared_ptr<PLTThinDielectricMaterial>;

        /** Create a new PLTThinDielectric material.
            \param[in] name The material name.
        */
        static SharedPtr create(std::shared_ptr<Device> pDevice, const std::string& name = "");

        // In millimetres
        void setThickness(float thickness);
        float getThickness() const { return (float)mData.specular[3]; }

        // Difference between ordinary and extraordinary IORs
        void setBirefringence(float birefringence);
        float getBirefringence() const { return (float)mData.baseColor[0]; }

        void setBirefringenceOpticAxis(float3 axis);
        float3 getBirefringenceOpticAxis() const {
            float x = (float)mData.baseColor[1];
            float y = (float)mData.baseColor[2];
            float z = std::sqrt(std::max(.0f, 1.f-x*x-y*y));
            return float3{ x,y,z };
        }

        Program::ShaderModuleList getShaderModules() const override;
        Program::TypeConformanceList getTypeConformances() const override;

        bool renderUI(Gui::Widgets& widget, const Scene* scene);

    protected:
        PLTThinDielectricMaterial(std::shared_ptr<Device> pDevice, const std::string& name);
    };
}
