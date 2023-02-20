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
#include "Utils/HostDeviceShared.slangh" // For bit packing macros

__exported import Scene.Material.BasicMaterialData;
__exported import Scene.ShadingData;

__exported import Rendering.PLT;
__exported import Rendering.Utils.DifferentialShadingGeometry;
__exported import Rendering.Materials.BSDFSample;
__exported import Rendering.Materials.LobeType;

__exported import Utils.HWSS;
__exported import Utils.Sampling.SampleGeneratorInterface;



// Surface Q cutoff for manifold sampling
static const float QcutoffForMS = .15f;



/** Describes BSDF properties.

    These properties may be useful as input to denoisers and other perceptual techniques.
    The BSDF implementations are expected to provide a best fit approximation.
*/
struct BSDFProperties
{
    uint32_t emissionSpectralId = BasicMaterialData.no_spectral_profile;
    float3 emissionRGB = .0f;
    float3 albedo = .0f;
    float roughness = .0f;

    uint flags = 0; ///< Flags storing additional properties.

    enum Flags : uint
    {
        IsTransmissive = 0x1,
        IsEmissive = 0x2,
        CanManifoldWalkReflective = 0x4,
        CanManifoldWalkTransmissive = 0x8,
    };

    property isTransmissive : bool
    {
        get { return (flags & (uint)Flags::IsTransmissive) != 0; }
    }
    property isEmissive : bool
    {
        get { return (flags & (uint)Flags::IsEmissive) != 0; }
    }
    property canManifoldWalkReflective : bool
    {
        get { return (flags & (uint)Flags::CanManifoldWalkReflective) != 0; }
    }
    property canManifoldWalkTransmissive : bool
    {
        get { return (flags & (uint)Flags::CanManifoldWalkTransmissive) != 0; }
    }
};


enum BSDFEvaluationFlags : uint {
    none = 0,
};


/** Interface for a bidirection scattering distribution function (BSDF).

    The term BSDF is used here in a broad sense for the mathematical function which
    describes the scattering of light at a shading location.

    This interface allows evaluation and sampling of the BSDF, and associated functionality.
    Implementations of the interface has all material properties evaluated at the shading location.
    BSDF instances are created and initialized by the corresponding material.

    The shading location and its attributes are described by a ShadingData struct.
    The ShadingData view direction field specifies the direction from which the
    shading location is seen. By convention we call this the incident direction (wi).
    The outgoing direction (wo) is the direction in which the transported quantity
    (radiance or importance) is scattered in.

    Conventions:
     - The incident and outgoing direction point away from the shading location.
     - The incident direction (wi) is given by ShadingData.
     - The outgoing direction (wo) is sampled.
     - The foreshortening term with respect to the sampled direction is always included.

    Note:
     - The [anyValueSize(n)] attribute specifies the maximum size in bytes an implementation type
       to IMaterialInstance can be. Slang compiler will check the implementation types and emits an error
       if an implementation exceeds this size.
     - The maximum size can be increased if needed, but it should be kept as small as possible
       to reduce register pressure in case the compiler fails to optimize.
*/
[anyValueSize(64)]
interface IMaterialInstance
{
    /** Evaluates the BSDF.
        \param[in] sd Shading data.
        \param[in] wo Outgoing direction (to eye).
        \param[in] lobe Scattering lobe to evaluate.
        \param[in,out] beam PLT beam to mutate.
    */
    void eval(const ShadingData sd, const float3 wo, const uint lobe, inout PLTBeam beam, const BSDFEvaluationFlags flags = (BSDFEvaluationFlags)0);

    /** Computed partial the derivatives of wo, given the partial derivatives of wi. Samples the delta lobe(s) only.
        \param[in] wi Incident direction and its partial derivatives.
        \param[in] dsg Differential geometry at shading point.
        \param[in] lobe Scattering lobe to evaluate.
        \param[in] wavelength wavlength.
        \return wo and its partial derivatives
    */
    float3kpdv partialDerivatives(const float3pdv wi, const DifferentialShadingGeometry dsg, const uint lobe, float wavelength);

    /** Samples the BSDF.
        \param[in] sd Shading data.
        \param[in,out] sg Sample generator.
        \param[out] result Generated sample. Only valid if true is returned.
        \param[in] wavelength wavlength.
        \param[in] lobeMask Mask of lobe types to sample from.
        \param[in] woHint When non-zero, implementation may sample a lobe as close to woHint as possible.
        \return True if a sample was generated, false otherwise.
    */
    bool sample<S : ISampleGenerator>(const ShadingData sd, inout S sg, out BSDFSample result, const float wavelength, const uint lobeMask = (uint)LobeType::All, const float3 woHint = .0f);

    /** Evaluates the directional pdf for sampling the given directions, with wavelength held constant.
        Only applies to non-delta lobes
        \param[in] sd Shading data.
        \param[in] toLight Direction to source.
        \param[in] wavelength wavlength.
        \return PDF with respect to solid angle for sampling direction wo.
    */
    float pdf(const ShadingData sd, const float3 toLight, const float wavelength);

    /** Evaluates the spectral pdf for sampling, with the directions held constant.
        (may be unnormalized)
        \param[in] sd Shading data.
        \param[in] wo Outgoing direction (to eye).
        \param[in] lobe Scattering lobe to evaluate.
        \param[in] beam PLT beam.
        \param[in] wavelengths wavlengths.
        \return PDF for sampling wavelength.
    */
    hwss_t lambdaPdf(const ShadingData sd, const float3 wo, const uint lobe, const PLTBeam beam, const hwss_t wavelengths);

    /** Return BSDF properties.
        \param[in] sd Shading data.
        \return A struct with properties.
    */
    BSDFProperties getProperties(const ShadingData sd);

    /** Return the set of available BSDF lobes.
        \param[in] sd Shading data.
        \return A combination of LobeType flags (see LobeType.slang).
    */
    uint getLobes(const ShadingData sd);
}
