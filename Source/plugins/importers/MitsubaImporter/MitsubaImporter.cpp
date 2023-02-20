/***************************************************************************
 # Copyright (c) 2015-21, NVIDIA CORPORATION. All rights reserved.
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
#include "MitsubaImporter.h"
#include "Parser.h"
#include "Loader.h"
#include "Tables.h"
//#include "skymodel/sunmodel.h"
#include "Utils/Math/Common.h"
#include "Utils/Math/FalcorMath.h"
#include "Utils/Math/MathHelpers.h"
#include "Utils/Color/SampledSpectrum.h"
#include "Utils/Color/SpectrumUtils.h"

#include "Rendering/Materials/PLT/PLTDiffuseMaterial.h"
#include "Rendering/Materials/PLT/PLTConductorMaterial.h"
#include "Rendering/Materials/PLT/PLTDielectricMaterial.h"
#include "Rendering/Materials/PLT/PLTThinDielectricMaterial.h"
#include "Rendering/Materials/PLT/PLTCoatedConductorMaterial.h"
#include "Rendering/Materials/PLT/PLTCoatedOpaqueDielectricMaterial.h"
#include "Rendering/Materials/PLT/PLTDiffractionGratedConductorMaterial.h"

#include <glm/gtx/euler_angles.hpp>

#include <optional>

namespace Falcor
{
    namespace Mitsuba
    {
        struct BuilderContext
        {
            SceneBuilder& builder;
            std::unordered_map<std::string, XMLObject>& instances;
            std::unordered_set<std::string> warnings;

            void forEachReference(const XMLObject& inst, Class cls, std::function<void(const XMLObject&)> func)
            {
                for (const auto& [name, id] : inst.props.getNamedReferences())
                {
                    const auto& child = instances[id];
                    if (child.cls == cls) func(child);
                }
            }

            template<typename... Args>
            void logWarningOnce(const std::string_view fmtString, Args&&... args)
            {
                auto msg = fmt::format(fmtString, std::forward<Args>(args)...);
                auto it = warnings.find(msg);
                if (it == warnings.end())
                {
                    warnings.insert(msg);
                    Falcor::logWarning("MitsubaImporter: {}", msg);
                }
            }

            void unsupportedParameter(const std::string& name)
            {
                logWarningOnce("Parameter '{}' is not supported.", name);
            }

            void unsupportedType(const std::string& name)
            {
                logError("Type '{}' is not supported.", name);
            }


        };

        struct ShapeInfo
        {
            TriangleMesh::SharedPtr pMesh;
            Hair::SharedPtr pHair;
            glm::mat4 transform;
            BasicMaterial::SharedPtr pMaterial;
        };

        struct SensorInfo
        {
            Camera::SharedPtr pCamera;
            glm::mat4 transform;
        };

        struct EmitterInfo
        {
            EnvMap::SharedPtr pEnvMap;
            Light::SharedPtr pLight;
            glm::mat4 transform;
            bool useNode = true;
        };

        struct TextureInfo
        {
            float4 value;
            Texture::SharedPtr pTexture;
            glm::mat4 transform;
        };

        struct BSDFInfo
        {
            BasicMaterial::SharedPtr pMaterial;
        };

        struct MediumInfo
        {
            struct Homogeneous
            {
                using SharedPtr = std::shared_ptr<Homogeneous>;
                static SharedPtr create() { return SharedPtr(new Homogeneous()); }
                float3 sigmaS = float3(0.f);
                float3 sigmaA = float3(0.f);
            };

            Homogeneous::SharedPtr pHomogeneous;
        };

        SampledSpectrum<float> getSpectrum(const Properties& props, const std::string& name, const std::optional<Color3>& defaultColor = std::nullopt)
        {
            if (props.hasSpectrum(name)) {
                return SampledSpectrum<float>{ props.getSpectrum(name) };
            }
            else if (props.hasColor3(name)) {
                return SpectrumUtils::rgbToSpectrum<float>(props.getColor3(name));
            }
            else if (!!defaultColor) {
                return SpectrumUtils::rgbToSpectrum<float>(defaultColor.value());
            }

            throw RuntimeError("Expected color value in '{}'.", name);
        }
        bool hasSpectrum(const Properties& props, const std::string& name)
        {
            return props.hasSpectrum(name) || props.hasColor3(name);
        }
        SpectralProfileID getEmissionSpectrum(BuilderContext& ctx, const Properties& props, const std::string& name, const std::optional<Color3>& defaultColor = std::nullopt)
        {
            if (props.hasString("emission_profile"))
            {
                return ctx.builder.addSpectralProfileForEmitterType(props.getString("emission_profile"), props.getFloat("scale", 1.f));
            }
            auto spec = getSpectrum(props, name, defaultColor);
            return ctx.builder.addSpectralProfile(std::move(spec));
        }

        std::pair<float,float> lookupIOR(const Properties& props, const std::string& name, const std::string& defaultIOR)
        {
            if (props.hasFloat(name))
            {
                return { props.getFloat(name), std::numeric_limits<float>::infinity() };
            }
            else
            {
                return lookupIOR(props.getString(name, defaultIOR));
            }
        }

        float convertGSSigma2(float sigma2) {
            return clamp(2.f*(1.f - std::pow(std::max(.0f, sigma2/1000.f), 1.f/32.f)), .0f, 1.f);
        }

        float3 extractRotation(const glm::mat4& toWorld) {
            float3 rotation;
            std::swap(rotation.y, rotation.z);
            rotation.z *= -1.f;

            return rotation;
        }
        auto adjustToWorld(glm::mat4 toWorld, float3& translate, float3& rotation) {
            const glm::mat4 transform(
                1.f, 0.f, 0.f, 0.f,
                0.f, 0.f, 1.f, 0.f,
                0.f, 1.f, 0.f, 0.f,
                0.f, 0.f, 0.f, 1.f
            );
            toWorld = transform * toWorld;

            glm::extractEulerAngleXYZ(toWorld, rotation.x, rotation.y, rotation.z);
            rotation = extractRotation(toWorld);
            translate = toWorld[3];

            return toWorld;
        }
        auto adjustToWorld(glm::mat4 toWorld) {
            float3 a, b;
            return adjustToWorld(std::move(toWorld), a, b);
        }

        TextureInfo buildTexture(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Texture);

            const auto& props = inst.props;

            // Common properties.
            auto toUV = props.getTransform("to_uv", glm::identity<glm::mat4>());
            toUV = glm::inverse(toUV);

            TextureInfo texture;

            if (inst.type == "bitmap")
            {
                auto filename = props.getString("filename");
                auto raw = props.getBool("raw", false);

                if (props.hasString("filter_type")) ctx.unsupportedParameter("filter_type");
                if (props.hasString("wrap_mode")) ctx.unsupportedParameter("wrap_mode");

                texture.pTexture = Texture::createFromFile(ctx.builder.getDevice().get(), filename, true, !raw);
                texture.transform = toUV;
            }
            else if (inst.type == "checkerboard")
            {
                auto color0 = props.getColor3("color0", Color3(0.4f));
                auto color1 = props.getColor3("color1", Color3(0.2f));

                const uint32_t kSize = 512;
                std::vector<float4> pixels(kSize * kSize);
                for (uint32_t y = 0; y < kSize; ++y)
                {
                    for (uint32_t x = 0; x < kSize; ++x)
                    {
                        float4 c(1.f);
                        c.xyz = (x < kSize / 2) ^ (y < kSize / 2) ? color1 : color0;
                        pixels[y * kSize + x] = c;
                    }
                }

                texture.pTexture = Texture::create2D(ctx.builder.getDevice().get(), kSize, kSize, ResourceFormat::RGBA32Float, 1, Resource::kMaxPossible, pixels.data()
                );
                texture.transform = toUV;
            }
            else
            {
                ctx.unsupportedType(inst.type);
            }

            return texture;
        }

        TextureInfo lookupTexture(BuilderContext& ctx, const Properties& props, const std::string& name, float4 defaultValue)
        {
            if (props.hasFloat(name))
            {
                return { float4(props.getFloat(name)) };
            }
            else if (props.hasColor3(name))
            {
                return { props.getColor3(name) };
            }
            else if (props.hasNamedReference(name))
            {
                const auto& inst = ctx.instances[props.getNamedReference(name)];
                if (inst.cls != Class::Texture) throw RuntimeError("Parameter '{}' needs to be a color or texture.", name);
                return buildTexture(ctx, inst);
            }
            else
            {
                return { defaultValue };
            }
        }

        BSDFInfo buildBSDF(BuilderContext& ctx, const XMLObject& inst, const std::string& default_name = {})
        {
            FALCOR_ASSERT(inst.cls == Class::BSDF);

            const auto& props = inst.props;
            const std::string& name = props.hasString("name") ? props.getString("name") :
                                      !default_name.length() || (inst.id.length() && inst.id.substr(0,9)!="_unnamed_") ? inst.id : default_name;

            BasicMaterial::SharedPtr pMaterial = nullptr;

            auto extIOR = lookupIOR(props, "ext_ior", "air").first;

            if (inst.type == "diffuse")
            {
                pMaterial = PLTDiffuseMaterial::create(ctx.builder.getDevice(), name);

                auto reflectance = lookupTexture(ctx, props, "reflectance", float4(0.5f));
                if (reflectance.pTexture)
                    pMaterial->setTexture(Material::TextureSlot::BaseColor, reflectance.pTexture);
                else
                    pMaterial->setBaseColor(reflectance.value);
            }
            else if (inst.type == "dielectric" || inst.type == "roughdielectric")
            {
                auto mat = PLTDielectricMaterial::create(ctx.builder.getDevice(), name);

                auto intIOR = lookupIOR(props, "int_ior", "bk7");

                if (props.getProperties().find("specular_reflectance") != props.getProperties().end()) {
                    const auto& specular = lookupTexture(ctx, props, "specular_reflectance", float4(1.f));
                    if (specular.pTexture)
                        mat->setTexture(Material::TextureSlot::BaseColor, specular.pTexture);
                    else
                        mat->setBaseColor(specular.value);
                }
                if (props.getProperties().find("specular_transmittance") != props.getProperties().end()) {
                    const auto& transmission = lookupTexture(ctx, props, "specular_transmittance", float4(1.f));
                    if (transmission.pTexture)
                        mat->setTexture(Material::TextureSlot::Transmission, transmission.pTexture);
                    else
                        mat->setTransmissionColor(transmission.value);
                }

                mat->setDoubleSided(false);
                mat->setExtIndexOfRefraction(extIOR);
                mat->setIndexOfRefraction(intIOR.first);
                mat->setAbbeNumber(intIOR.second);
                if (props.hasFloat("roughness"))
                    mat->setRoughness(props.getFloat("roughness"));
                else
                    mat->setRoughness(convertGSSigma2(props.getFloat("sigma2",100.f)));

                pMaterial = std::move(mat);
            }
            else if (inst.type == "thindielectric")
            {
                auto mat = PLTThinDielectricMaterial::create(ctx.builder.getDevice(), name);

                auto intIOR = lookupIOR(props, "int_ior", "bk7");

                if (props.hasFloat("specular_reflectance")) ctx.unsupportedParameter("specular_reflectance");
                if (props.hasFloat("specular_transmittance")) ctx.unsupportedParameter("specular_transmittance");

                mat->setDoubleSided(false);
                mat->setIndexOfRefraction(intIOR.first);

                mat->setThickness(props.getFloat("thickness", .001f));
                mat->setBirefringenceOpticAxis(props.getFloat3("optic_axis", float3{ 0,0,1 }));
                mat->setBirefringence(props.getFloat("birefringence_scale",1.f));
                auto birefringence = lookupTexture(ctx, props, "birefringence", float4(0.f));
                if (birefringence.pTexture)
                    mat->setTexture(Material::TextureSlot::Specular, birefringence.pTexture);
                else
                    mat->setSpecularParams(float4{ birefringence.value.x, mat->getSpecularParams().yzw });

                pMaterial = std::move(mat);
            }
            else if (inst.type == "conductor" || inst.type == "roughconductor")
            {
                auto mat = PLTConductorMaterial::create(ctx.builder.getDevice(), name);

                const auto& specular = lookupTexture(ctx, props, "specular_reflectance", float4(1.f));
                if (specular.pTexture)
                    mat->setTexture(Material::TextureSlot::BaseColor, specular.pTexture);
                else
                    mat->setBaseColor(specular.value);

                // Read complex IORs
                std::pair<SampledSpectrum<float>, SampledSpectrum<float>> nk;
                if (props.hasString("material"))
                {
                    mat->setIORSpectralProfile(ctx.builder.addSpectralProfileFromMaterial(props.getString("material")));
                }
                else if (hasSpectrum(props, "eta") && hasSpectrum(props, "k"))
                {
                    nk.first = getSpectrum(props, "eta");
                    nk.second = getSpectrum(props, "k");
                    const auto& profilen = ctx.builder.addSpectralProfile(nk.first);
                    const auto& profilek = ctx.builder.addSpectralProfile(nk.second);
                    mat->setIORSpectralProfile(std::make_pair(profilen,profilek));
                }
                else
                {
                    throw RuntimeError("'conductor' BSDF must specify either 'eta' and 'k' IOR values or 'material' name.");
                }

                mat->setExtIndexOfRefraction(extIOR);
                if (props.hasFloat("roughness"))
                    mat->setRoughness(props.getFloat("roughness"));
                else
                    mat->setRoughness(convertGSSigma2(props.getFloat("sigma2",100.f)));

                pMaterial = std::move(mat);
            }
            else if (inst.type == "coated_conductor" || inst.type == "coated_roughconductor")
            {
                PLTConductorMaterial::SharedPtr conductor = nullptr;
                for (const auto& [name, id] : props.getNamedReferences())
                {
                    const auto& child = ctx.instances[id];
                    if (child.cls == Class::BSDF)
                    {
                        if (conductor) throw RuntimeError("'coatedConductor' BSDF can only have one nested BSDF.");
                        auto nested = buildBSDF(ctx, child).pMaterial;
                        if (nested->getType()!=MaterialType::PLTConductor) throw RuntimeError("'coatedConductor' BSDF must contain only a nested 'conductor' BSDF.");
                        conductor = std::move(std::dynamic_pointer_cast<PLTConductorMaterial>(nested));
                    }
                }
                if (!conductor)
                    throw RuntimeError("'twosided' BSDF must contain a single nested BSDF.");

                auto mat = PLTCoatedConductorMaterial::create(ctx.builder.getDevice(), name);

                auto intIOR = lookupIOR(props, "int_ior", "bk7");
                mat->setIORSpectralProfile(conductor->getIORSpectralProfile());
                mat->setExtIndexOfRefraction(conductor->getExtIndexOfRefraction());
                mat->setRoughness(conductor->getRoughness());
                mat->setSpecularParams(conductor->getSpecularParams());
                mat->setBaseColorTexture(conductor->getBaseColorTexture());
                mat->setCoatIndexOfRefraction(intIOR.first);
                mat->setCoatThickness(props.getFloat("thickness",50));

                pMaterial = std::move(mat);
            }
            else if (inst.type == "grating")
            {
                auto mat = PLTDiffractionGratedConductorMaterial::create(ctx.builder.getDevice(), name);

                // Read complex IORs
                std::pair<SampledSpectrum<float>, SampledSpectrum<float>> nk;
                if (props.hasString("material"))
                {
                    mat->setIORSpectralProfile(ctx.builder.addSpectralProfileFromMaterial(props.getString("material")));
                }
                else if (hasSpectrum(props, "eta") && hasSpectrum(props, "k"))
                {
                    nk.first = getSpectrum(props, "eta");
                    nk.second = getSpectrum(props, "k");
                    const auto& profilen = ctx.builder.addSpectralProfile(nk.first);
                    const auto& profilek = ctx.builder.addSpectralProfile(nk.second);
                    mat->setIORSpectralProfile(std::make_pair(profilen,profilek));
                }
                else
                {
                    throw RuntimeError("'grating' BSDF must specify either 'eta' and 'k' IOR values or 'material' name.");
                }

                mat->setExtIndexOfRefraction(extIOR);
                mat->setGratingPitch(props.getFloat("pitch",5.f));
                mat->setGratingLobes(props.getInt("lobes",3));
                mat->setGratingHeightScale(props.getFloat("q",.5f));
                mat->setGratingHeight(1.f);
                mat->setGratingDir(props.getFloat("grating_direction",.0f)*M_PI/180.f);
                mat->setGratingPowerMultiplier(props.getFloat("amplify",1.f));

                if (props.hasString("type")) {
                    if (props.getString("type")=="sinusoidal")
                        mat->setGratingType(DiffractionGratingType::sinusoidal);
                    else if (props.getString("type")=="rectangular")
                        mat->setGratingType(DiffractionGratingType::rectangular);
                    else if (props.getString("type")=="linear")
                        mat->setGratingType(DiffractionGratingType::linear);
                    else if (props.getString("type")=="radial_sinusoidal")
                        mat->setGratingType((DiffractionGratingType)
                            ((uint)DiffractionGratingType::sinusoidal | (uint)DiffractionGratingType::radial));
                    else if (props.getString("type")=="radial_rectangular")
                        mat->setGratingType((DiffractionGratingType)
                            ((uint)DiffractionGratingType::rectangular | (uint)DiffractionGratingType::radial));
                    else
                        throw RuntimeError("Unsupported 'type' name.");
                }

                pMaterial = std::move(mat);
            }
            else if (inst.type == "normalmap")
            {
                TextureInfo normalmap = {};
                for (const auto& [name, id] : props.getNamedReferences())
                {
                    const auto& child = ctx.instances[id];
                    if (child.cls == Class::BSDF)
                    {
                        if (pMaterial) throw RuntimeError("'normalmap' BSDF can only have one nested BSDF.");
                        pMaterial = buildBSDF(ctx, child, name).pMaterial;
                    }
                    else if (child.cls == Class::Texture) {
                        normalmap = buildTexture(ctx, child);
                    }
                }

                if (!pMaterial || !normalmap.pTexture)
                    throw RuntimeError("'normalmap' BSDF must contain a single nested BSDF and a bitmap.");

                pMaterial->setNormalMap(normalmap.pTexture);
            }
            else if (inst.type == "twosided")
            {
                for (const auto& [name, id] : props.getNamedReferences())
                {
                    const auto& child = ctx.instances[id];
                    if (child.cls == Class::BSDF)
                    {
                        if (pMaterial) throw RuntimeError("'twosided' BSDF can only have one nested BSDF.");
                        pMaterial = buildBSDF(ctx, child, name).pMaterial;
                        if (pMaterial) pMaterial->setDoubleSided(true);
                    }
                }
                if (!pMaterial)
                    throw RuntimeError("'twosided' BSDF must contain a single nested BSDF.");
            }
            else
            {
                ctx.unsupportedType(inst.type);

                pMaterial = PLTDiffuseMaterial::create(ctx.builder.getDevice(), name);
                pMaterial->setBaseColor(float4(1,0,0,1));
            }

            return { pMaterial };
        }

        MediumInfo buildMedium(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Medium);

            const auto& props = inst.props;

            MediumInfo medium;

            if (inst.type == "homogeneous")
            {
                auto scale = props.getFloat("scale", 1.f);

                if (props.hasString("material"))
                {
                    ctx.unsupportedParameter("material");
                }
                else if (props.hasColor3("sigma_s") && props.hasColor3("sigma_a"))
                {
                    medium.pHomogeneous = MediumInfo::Homogeneous::create();
                    medium.pHomogeneous->sigmaS = scale * (float3)props.getColor3("sigma_s");
                    medium.pHomogeneous->sigmaA = scale * (float3)props.getColor3("sigma_a");
                }
                else if (props.hasColor3("albedo") && props.hasColor3("sigma_t"))
                {
                    float3 albedo = props.getColor3("albedo");
                    float3 sigmaT = props.getColor3("sigma_s");
                    medium.pHomogeneous = MediumInfo::Homogeneous::create();
                    medium.pHomogeneous->sigmaS = scale * (albedo * sigmaT);
                    medium.pHomogeneous->sigmaA = scale * (sigmaT - medium.pHomogeneous->sigmaS);
                }
            }
            else
            {
                // Unsupported: heterogeneous
                ctx.unsupportedType(inst.type);
            }

            return medium;
        }


        ShapeInfo buildShape(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Shape);

            const auto& props = inst.props;

            // Common properties.
            auto toWorld = props.getTransform("to_world", glm::identity<glm::mat4>());
            auto flipNormals = props.getBool("flip_normals", false);
            std::string default_name{};

            const glm::mat4 transformYtoZ(
                1.f, 0.f, 0.f, 0.f,
                0.f, 0.f, 1.f, 0.f,
                0.f, 1.f, 0.f, 0.f,
                0.f, 0.f, 0.f, 1.f
            );

            ShapeInfo shape;

            if (inst.type == "obj")
            {
                auto filename = props.getString("filename");
                auto faceNormals = props.getBool("face_normals", false);
                auto flipTexCoords = props.getBool("flip_tex_coords", true);

                if (props.hasBool("face_normals")) ctx.unsupportedParameter("face_normals");

                shape.pMesh = TriangleMesh::createFromFile(filename, !faceNormals);
                if (shape.pMesh) shape.pMesh->setName(inst.id);
                if (shape.pMesh && !flipTexCoords) shape.pMesh->flipTexCoords();
                shape.transform = toWorld;

                default_name = filename;
            }
            else if (inst.type == "ply")
            {
                auto filename = props.getString("filename");
                auto faceNormals = props.getBool("face_normals", false);
                auto flipTexCoords = props.getBool("flip_tex_coords", true);

                // if (props.hasBool("face_normals")) ctx.unsupportedParameter("face_normals");

                shape.pMesh = TriangleMesh::createFromFile(filename, !faceNormals);
                if (shape.pMesh) shape.pMesh->setName(inst.id);
                if (shape.pMesh && flipTexCoords) shape.pMesh->flipTexCoords();
                shape.transform = toWorld;

                default_name = filename;
            }
            else if (inst.type == "serialized")
            {
                auto filename = props.getString("filename");
                auto shapeIndex = props.getInt("shape_index", 0);
                auto faceNormals = props.getBool("face_normals", false);

                ctx.unsupportedType(inst.type);

                default_name = filename;
            }
            else if (inst.type == "sphere")
            {
                auto center = props.getFloat3("center", float3(0.f));
                auto radius = props.getFloat("radius", 1.f);

                shape.pMesh = TriangleMesh::createSphere(radius, 128,32);
                shape.pMesh->setName(inst.id);
                if (flipNormals) shape.pMesh->flipNormals();
                shape.transform = toWorld * glm::translate(center);
            }
            else if (inst.type == "cylinder")
            {
                auto p0 = props.getFloat3("p0", float3(0.f, 0.f, 0.f));
                auto p1 = props.getFloat3("p1", float3(0.f, 0.f, 1.f));
                auto radius = props.getFloat("radius", 1.f);

                ctx.unsupportedType(inst.type);
            }
            else if (inst.type == "disk")
            {
                shape.pMesh = TriangleMesh::createDisk(1.f);
                shape.pMesh->setName(inst.id);
                if (flipNormals) shape.pMesh->flipNormals();
                shape.transform = toWorld * transformYtoZ;
            }
            else if (inst.type == "rectangle")
            {
                shape.pMesh = TriangleMesh::createQuad(float2(2.f));
                shape.pMesh->setName(inst.id);
                if (flipNormals) shape.pMesh->flipNormals();
                shape.transform = toWorld * transformYtoZ;
            }
            else if (inst.type == "cube")
            {
                shape.pMesh = TriangleMesh::createCube(float3(2.f));
                shape.pMesh->setName(inst.id);
                if (flipNormals) shape.pMesh->flipNormals();
                shape.transform = toWorld;
            }
            else if (inst.type == "shapegroup")
            {
                ctx.unsupportedType(inst.type);
            }
            else if (inst.type == "instance")
            {
                ctx.unsupportedType(inst.type);
            }
            else if (inst.type == "hair")
            {
                float radius = props.getFloat("radius", 0.025f);
                shape.pHair = Hair::createFromFile(props.getString("filename"), radius);

                if (props.hasFloat("angle_threshold")) ctx.unsupportedParameter("angle_threshold");
                if (props.hasFloat("reduction")) ctx.unsupportedParameter("reduction");
            }
            else
            {
                ctx.unsupportedType(inst.type);
            }

            if (props.hasString("name"))
                default_name = props.getString("name");
            else {
                // Remove path components from default name
                const auto lslash = default_name.find_last_of("\\/");
                if (lslash != std::string::npos)
                    default_name = default_name.substr(lslash+1);
            }

            // Look for nested BSDF.
            for (const auto& [name, id] : props.getNamedReferences())
            {
                const auto& child = ctx.instances[id];
                if (child.cls == Class::BSDF)
                {
                    if (shape.pMaterial) throw RuntimeError("Shape can only have one BSDF.");
                    auto bsdf = buildBSDF(ctx, child, default_name);
                    shape.pMaterial = bsdf.pMaterial;
                }
            }

            // Create default material.
            if (!shape.pMaterial)
                shape.pMaterial = PLTDiffuseMaterial::create(ctx.builder.getDevice(), "default");

            // Look for interior medium.
            for (const auto& [name, id] : props.getNamedReferences())
            {
                const auto& child = ctx.instances[id];
                if (child.cls == Class::Medium && name == "interior")
                {
                    auto medium = buildMedium(ctx, child);
                    if (medium.pHomogeneous)
                    {
                        shape.pMaterial->setVolumeScattering(medium.pHomogeneous->sigmaS);
                        shape.pMaterial->setVolumeAbsorption(medium.pHomogeneous->sigmaA);
                    }
                }
            }

            // Look for nested area emitter.
            for (const auto& [name, id] : props.getNamedReferences())
            {
                const auto& child = ctx.instances[id];
                if (child.cls == Class::Emitter && child.type == "area")
                {
                    const auto& radiance = getEmissionSpectrum(ctx, child.props, "radiance");
                    shape.pMaterial->setEmissionSpectralProfile(true, radiance);
                }
            }

            return shape;
        }

        SensorInfo buildSensor(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Sensor)

            const auto& props = inst.props;

            // Common properties.
            const auto& toWorld = props.getTransform("to_world", glm::identity<glm::mat4>());

            // Check for film to get resolution.
            uint32_t width = 768;
            uint32_t height = 576;
            for (const auto& [name, id] : props.getNamedReferences())
            {
                const auto& child = ctx.instances[id];
                if (child.cls == Class::Film)
                {
                    width = (uint32_t)child.props.getInt("width", 768);
                    height = (uint32_t)child.props.getInt("height", 576);
                }
            }

            SensorInfo sensor;

            if (inst.type == "perspective" || inst.type == "thinlens")
            {
                if (props.hasFloat("focal_length") && props.hasFloat("fov"))
                {
                    throw RuntimeError("Cannot specify both 'focal_length' and 'fov'.");
                }
                float focalLength = props.getFloat("focal_length", 50.f);
                if (props.hasFloat("fov"))
                {
                    float filmWidth = (24.f / height) * width;
                    focalLength = fovYToFocalLength(glm::radians(props.getFloat("fov")), filmWidth);
                }

                if (props.hasString("fov_axis")) ctx.unsupportedParameter("fov_axis");

                // TODO handle fov_axis
                auto pCamera = Camera::create();
                pCamera = Camera::create();
                pCamera->setFocalLength(focalLength);
                pCamera->setFrameHeight(24.f);
                pCamera->setNearPlane(props.getFloat("near_clip", 1e-2f));
                pCamera->setFarPlane(props.getFloat("far_clip", 1e4f));
                pCamera->setFocalDistance(props.getFloat("focus_distance", 1.f));
                pCamera->setApertureRadius(props.getFloat("aperture_radius", 0.f));
                pCamera->setPolarizationIntensity(props.getFloat("polarizer_intensity", 0.f));
                pCamera->setPolarizationAngle(props.getFloat("polarizer", 0.f)*M_PI/180.f);

                const glm::mat4 flipZ(
                    1.f, 0.f, 0.f, 0.f,
                    0.f, 1.f, 0.f, 0.f,
                    0.f, 0.f, -1.f, 0.f,
                    0.f, 0.f, 0.f, 1.f
                );

                sensor.pCamera = pCamera;
                sensor.transform = toWorld * flipZ;
            }
            else
            {
                // Unsupported: orthographic, telecentric, spherical, radiancemeter, irradiancemeter, fluencemeter, perspective_rdist
                ctx.unsupportedType(inst.type);
            }

            // Key frames
            Animation::SharedPtr anim = nullptr;
            for (const auto& [name, id] : props.getNamedReferences()) {
                const auto& child = ctx.instances[id];
                if (child.cls == Class::KeyFrame)
                {
                    if (!anim) {
                        if (!props.hasFloat("animation_duration"))
                        {
                            throw RuntimeError("'animation_duration' unspecified.");
                        }
                        anim = ctx.builder.createAnimation(sensor.pCamera, "camera animation", props.getFloat("animation_duration"));
                        anim->setPreInfinityBehavior(Animation::Behavior::Cycle);
                        anim->setPostInfinityBehavior(Animation::Behavior::Cycle);
                        anim->setInterpolationMode(props.getBool("animation_interpolate_hermite", false) ? Animation::InterpolationMode::Hermite : Animation::InterpolationMode::Linear);
                    }

                    const auto pos = child.props.getFloat3("position", { .0f,.0f,-1.f });
                    const auto target = child.props.getFloat3("target", { .0f,.0f,.0f });
                    const auto up = child.props.getFloat3("up", { .0f,1.f,.0f });

                    auto transform = Transform{};
                    transform.lookAt(pos, target, up);

                    Animation::Keyframe keyframe{ child.props.getFloat("time", .0f), transform.getTranslation(), transform.getScaling(), transform.getRotation() };
                    anim->addKeyframe(keyframe);
                }
            }
            if (anim) {
                sensor.pCamera->setIsAnimated(true);
            }

            return sensor;
        }

        EmitterInfo buildEmitter(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Emitter);

            const auto& props = inst.props;

            // Common properties.
            const auto& name = props.getString("name", "");
            float3 translate, rotation;
            auto toWorld = adjustToWorld(props.getTransform("to_world", glm::identity<glm::mat4>()), translate, rotation);

            EmitterInfo emitter;

            if (inst.type == "area")
            {
                throw RuntimeError("'area' emitter needs to be nested in a shape.");
            }
            else if (inst.type == "constant")
            {
                auto radiance = props.getColor3("radiance");
                float4 data = radiance;
                auto pTexture = Texture::create2D(ctx.builder.getDevice().get(), 1, 1, ResourceFormat::RGBA32Float, 1, Texture::kMaxPossible, &data);
                auto pEnvMap = EnvMap::create(ctx.builder.getDevice(), pTexture);
                emitter.pEnvMap = pEnvMap;
            }
            else if (inst.type == "envmap")
            {
                auto filename = props.getString("filename");
                auto scale = props.getFloat("scale", 1.f);
                auto pEnvMap = EnvMap::createFromFile(ctx.builder.getDevice(), filename);
                if (pEnvMap)
                {
                    pEnvMap->setIntensity(scale);
                    pEnvMap->setRotation(glm::degrees(rotation));
                }
                emitter.pEnvMap = pEnvMap;
            }
            else if (inst.type == "point")
            {
                const auto& intensity = getEmissionSpectrum(ctx, props, "intensity");

                if (props.hasFloat3("position"))
                {
                    if (props.hasTransform("to_world")) throw RuntimeError("Either 'to_world' or 'position' can be specified, not both.");
                    toWorld = glm::translate(props.getFloat3("position"));
                }
                emitter.transform = toWorld;

                auto light = PointLight::create(name);
                light->setIntensity(intensity, ctx.builder.getSpectralProfile(intensity));
                light->setWorldPosition(translate);

                if (props.hasFloat("A")) {
                    light->setLightArea(props.getFloat("A"));
                }
                else
                    throw RuntimeError("Emitter must specify sourcing area 'A'.");

                emitter.pLight = light;
            }
            else if (inst.type == "directional")
            {
                const auto& irradiance = getEmissionSpectrum(ctx, props, "irradiance");
                if (props.hasFloat3("direction")) {
                    if (props.hasTransform("to_world")) throw RuntimeError("Either 'to_world' or 'direction' can be specified, not both.");
                    rotation = props.getFloat3("direction");
                }

                emitter.useNode = false;

                auto light = DistantLight::create(name);
                light->setIntensity(irradiance, ctx.builder.getSpectralProfile(irradiance));
                light->setWorldDirection(rotation);

                if (props.hasFloat("Omega"))
                    light->setSourceSolidAngle(props.getFloat("Omega"));
                else if (props.hasFloat("source_area") && props.hasFloat("distance")) {
                    const float d = props.getFloat("distance");
                    light->setSourceSolidAngle(props.getFloat("source_area") / d / d);
                }
                else
                    throw RuntimeError("Emitter must specify coherence properties by setting both 'Omega' and 'A'.");

                emitter.pLight = light;

                // Key frames
                Animation::SharedPtr anim = nullptr;
                for (const auto& [name, id] : props.getNamedReferences()) {
                    const auto& child = ctx.instances[id];
                    if (child.cls == Class::KeyFrame)
                    {
                        if (!anim) {
                            if (!props.hasFloat("animation_duration"))
                            {
                                throw RuntimeError("'animation_duration' unspecified.");
                            }
                            anim = ctx.builder.createAnimation(emitter.pLight, "directional light animation", props.getFloat("animation_duration"));
                            anim->setPreInfinityBehavior(Animation::Behavior::Cycle);
                            anim->setPostInfinityBehavior(Animation::Behavior::Cycle);
                            anim->setInterpolationMode(props.getBool("animation_interpolate_hermite", false) ? Animation::InterpolationMode::Hermite : Animation::InterpolationMode::Linear);
                        }

                        const auto dir = child.props.getFloat3("direction", { .0f,.0f,.0f });
                        auto transform = Transform{ glm::mat4(1.f) };
                        const float3 up(0.f, 0.f, 1.f);
                        const float3 vec = glm::cross(up, -dir);
                        const float sinTheta = glm::length(vec);
                        if (sinTheta > 0.f)
                        {
                            float cosTheta = glm::dot(up, -dir);
                            transform = Transform{ rmcv::toGLM(rmcv::rotate(rmcv::mat4(), std::acos(cosTheta), vec)) };
                        }

                        Animation::Keyframe keyframe{ child.props.getFloat("time", .0f), transform.getTranslation(), transform.getScaling(), transform.getRotation() };
                        anim->addKeyframe(keyframe);
                    }
                }
                if (anim) {
                    emitter.pLight->setIsAnimated(true);
                }
            }
            else
            {
                // Unsupported: collimated, sky, sun, sunsky, projector
                ctx.unsupportedType(inst.type);
            }

            return emitter;
        }

        void buildScene(BuilderContext& ctx, const XMLObject& inst)
        {
            FALCOR_ASSERT(inst.cls == Class::Scene);

            const auto& props = inst.props;

            for (const auto& [name, id] : props.getNamedReferences())
            {
                const auto& child = ctx.instances[id];

                switch (child.cls)
                {
                case Class::Sensor:
                    {
                        auto sensor = buildSensor(ctx, child);

                        if (sensor.pCamera)
                        {
                            // SceneBuilder::Node node { id, rmcv::toRMCV(sensor.transform) };
                            // auto nodeID = ctx.builder.addNode(node);
                            // sensor.pCamera->setNodeID(nodeID);
                            ctx.builder.addCamera(sensor.pCamera);
                        }
                    }
                    break;

                case Class::Emitter:
                    {
                        auto emitter = buildEmitter(ctx, child);

                        if (emitter.pEnvMap)
                        {
                            if (ctx.builder.getEnvMap() != nullptr) throw RuntimeError("Only one envmap can be added.");
                            ctx.builder.setEnvMap(emitter.pEnvMap);
                        }
                        else if (emitter.pLight)
                        {
                            if (emitter.useNode) {
                                SceneBuilder::Node node { id, rmcv::toRMCV(emitter.transform) };
                                auto nodeID = ctx.builder.addNode(node);
                                emitter.pLight->setNodeID(nodeID);
                            }
                            ctx.builder.addLight(emitter.pLight);
                        }
                    }
                    break;

                case Class::Shape:
                    {
                        auto shape = buildShape(ctx, child);

                        if (shape.pMesh && shape.pMaterial)
                        {
                            SceneBuilder::Node node { id, rmcv::toRMCV(shape.transform) };
                            auto nodeID = ctx.builder.addNode(node);
                            auto meshID = ctx.builder.addTriangleMesh(shape.pMesh, shape.pMaterial);
                            ctx.builder.addMeshInstance(nodeID, meshID);
                        }
                        else if (shape.pHair && shape.pMaterial)
                        {
                            SceneBuilder::Node node { id, rmcv::toRMCV(shape.transform) };
                            auto nodeID = ctx.builder.addNode(node);

                            SceneBuilder::Curve curve;
                            curve.name = id;
                            curve.vertexCount = (uint32_t)shape.pHair->getVertices().size();
                            curve.positions.pData = shape.pHair->getVertices().data();
                            curve.radius.pData = shape.pHair->getRadii().data();
                            curve.texCrds.pData = shape.pHair->getTexCoords().data();
                            curve.indexCount = (uint32_t)shape.pHair->getIndices().size();
                            curve.pIndices = shape.pHair->getIndices().data();
                            curve.pMaterial = shape.pMaterial;
                            auto curveID = ctx.builder.addCurve(curve);

                            ctx.builder.addCurveInstance(nodeID, curveID);
                        }
                    }
                    break;
                }
            }
        }
    }

    void MitsubaImporter::importScene(const std::filesystem::path& path, SceneBuilder& builder, const Dictionary& dict)
    {
        if (!path.is_absolute())
            throw ImporterError(path, "Expected absolute path.");

        std::filesystem::path fullpath;
        if (!findFileInDataDirectories(path, fullpath))
        {
            throw ImporterError(path, "File not found.");
        }

        pugi::xml_document doc;
        auto result = doc.load_file(fullpath.c_str(), pugi::parse_default | pugi::parse_comments);
        if (!result)
        {
            throw ImporterError(path, "Failed to parse XML: {}", result.description());
        }

        try
        {
            Mitsuba::XMLSource src { path.string(), doc};
            Mitsuba::XMLContext ctx;
            ctx.resolver.append(fullpath.parent_path());
            Mitsuba::Properties props;
            pugi::xml_node root = doc.document_element();
            size_t argCounter = 0;
            auto sceneID = Mitsuba::parseXML(src, ctx, root, Mitsuba::Tag::Invalid, props, argCounter).second;

            Mitsuba::BuilderContext builderCtx { builder, ctx.instances };
            Mitsuba::buildScene(builderCtx, builderCtx.instances[sceneID]);
        }
        catch (const RuntimeError& e)
        {
            throw ImporterError(path, e.what());
        }
    }

    std::unique_ptr<Importer> MitsubaImporter::create()
    {
        return std::make_unique<MitsubaImporter>();
    }

    extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
    {
        registry.registerClass<Importer, MitsubaImporter>();
    }
}
