/***************************************************************************
 # Copyright (c) 2015-22, NVIDIA CORPORATION. All rights reserved.
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
#include "Utils/Math/MathConstants.slangh"

import Utils.HWSS;
import Scene.Material.MaterialData;
import Utils.Math.MathHelpers;
import Utils.Color.ColorHelpers;
import Utils.Color.SpectrumUtils;
import Rendering.Materials.Fresnel;
import Rendering.Materials.IsotropicGGX;

// Enable support for delta reflection/transmission.
#define EnableDeltaBSDF         1

// Enable GGX sampling using the distribution of visible normals (VNDF) instead of classic NDF sampling.
// This should be the default as it has lower variance, disable for testing only.
// TODO: Make default when transmission with VNDF sampling is properly validated
#define EnableVNDFSampling      1

// Enable explicitly computing sampling weights using eval(wi, wo) / evalPdf(wi, wo).
// This is for testing only, as many terms of the equation cancel out allowing to save on computation.
#define ExplicitSampleWeights   0

// We clamp the GGX width parameter to avoid numerical instability.
// In some computations, we can avoid clamps etc. if 1.0 - alpha^2 != 1.0, so the epsilon should be 1.72666361e-4 or larger in fp32.
// The the value below is sufficient to avoid visible artifacts.
// Falcor used to clamp roughness to 0.08 before the clamp was removed for allowing delta events. We continue to use the same threshold.
static const float kMinGGXAlpha = 0.0064f;
static const float kMinCosTheta = 1e-6f;

// TODO: Reduce to 52B
/** BSDF parameters for the standard BSDF.
    These are needed for initializing a `FalcorBSDF` instance.
*/
struct StandardBSDFData
{
    float3 diffuse;                 ///< Diffuse albedo.
    float3 specular;                ///< Specular albedo.
    float roughness;                ///< This is the original roughness, before remapping.
    float metallic;                 ///< Metallic parameter, blends between dielectric and conducting BSDFs.
    float eta;                      ///< Relative index of refraction (incident IoR / transmissive IoR).
    float3 transmission;            ///< Transmission color.
    float diffuseTransmission;      ///< Diffuse transmission, blends between diffuse reflection and transmission lobes.
    float specularTransmission;     ///< Specular transmission, blends between opaque dielectric BRDF and specular transmissive BSDF.
}

