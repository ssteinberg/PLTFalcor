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

#include "PLTPT.h"

#include "RenderGraph/RenderPassHelpers.h"
#include "RenderGraph/RenderPassStandardFlags.h"
#include "Rendering/Lights/EmissiveUniformSampler.h"
#include "Rendering/Lights/EmissivePowerSampler.h"

static void regPLTPTPass(pybind11::module& m)
{
    pybind11::class_<PLTPT, RenderPass, PLTPT::SharedPtr> pass(m, "PLTPT");
    pass.def_property("sourcingAreaFromEmissiveGeometry", &PLTPT::getSourcingAreaFromEmissiveGeometry, &PLTPT::setSourcingAreaFromEmissiveGeometry);
}

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry) {
    registry.registerClass<RenderPass, PLTPT>();
    ScriptBindings::registerBinding(regPLTPTPass);
}

namespace {
    const std::string kSamplePassFileName   = "RenderPasses/PLTPT/pltpt_sample.rt.slang";
    const std::string kSolvePassFileName    = "RenderPasses/PLTPT/pltpt_solve.rt.slang";

    const std::string kShaderModel = "6_5";

    // Ray tracing settings that affect the traversal stack size.
    static constexpr uint32_t kBasePayloadSizeBytes = 84u;
    static constexpr uint32_t kShadowPayloadSizeBytes = 20u;
    static constexpr uint32_t kPerBouncePayloadSizeBytes = 40u;
    static constexpr uint32_t kMaxRecursionDepth = 1u;

    static constexpr uint kVisibilityRayId = 0;
    static constexpr uint kShadowRayId = 1;

    const char kInputViewDir[] = "viewW";

    const ChannelList kInputChannels = {
        { "vbuffer",        "gVBuffer",     "Visibility buffer in packed format" },
        { kInputViewDir,    "gViewW",       "World-space view direction (xyz float format)", true /* optional */ },
    };

    const ChannelList kOutputChannels = {
    };
    const ChannelList kSampleOutputChannels = {
        { "normal",         "gOutputNormal", "Output normal", false, ResourceFormat::RGBA32Float },
        { "albedo",         "gOutputAlbedo", "Output albedo", false, ResourceFormat::RGBA32Float },
    };
    const ChannelList kSolveOutputChannels = {
        { "color",          "gOutputColor", "Output color (sum of direct and indirect)", false, ResourceFormat::RGBA32Float },
    };

    const Gui::DropdownList kEmissiveSamplerList = {
        { (uint32_t)EmissiveLightSamplerType::Uniform, "Uniform" },
        { (uint32_t)EmissiveLightSamplerType::Power, "Power" },
    };

    const Gui::DropdownList kDebugViewList = {
        { (uint32_t)DebugViewType::none, "None" },
        { (uint32_t)DebugViewType::nans, "NaNs" },
        { (uint32_t)DebugViewType::inf, "INFs" },
        { (uint32_t)DebugViewType::path_length, "Path length" },
        { (uint32_t)DebugViewType::hwss_comps, "Spectral samples" },
        { (uint32_t)DebugViewType::normals, "normals" },
        { (uint32_t)DebugViewType::albedo, "albedo" },
        { (uint32_t)DebugViewType::roughness, "roughness" },
        { (uint32_t)DebugViewType::UVs, "UVs" },
        { (uint32_t)DebugViewType::coherence_area, "Coherence area" },
        { (uint32_t)DebugViewType::coherence_anisotropy, "Coherence anisotropy" },
        { (uint32_t)DebugViewType::polarization, "Polarization" },
        { (uint32_t)DebugViewType::mnee_iterations, "MNEE iterations" },
        { (uint32_t)DebugViewType::mnee_bounces, "MNEE bounces" },
    };

    const std::string kMaxBounces = "maxBounces";
    const std::string kTileSize = "tileSize";

    const std::string kHWSS = "HWSS";
    const std::string kHWSSDoMIS = "HWSSDoMIS";

    const std::string kSampleGenerator = "sampleGenerator";

    const std::string kDebugView = "debugView";
    const std::string kDebugViewIntensity = "debugViewIntensity";

    const std::string kSourcingAreaFromEmissiveGeometry = "sourcingAreaFromEmissiveGeometry";
    const std::string kSourcingMaxBeamOmega = "sourcingMaxBeamOmega";

    const std::string kUseDirectLights = "useDirectLights";
    const std::string kUseEnvLights = "useEnvLights";
    const std::string kUseEmissiveLights = "useEmissiveLights";
    const std::string kUseAnalyticLights = "useAnalyticLights";

    const std::string kAlphaMasking = "alphaMasking";

    const std::string kDoNEE = "doNEE";
    const std::string kDoMIS = "doMIS";
    const std::string kEmissiveSampler = "emissiveSampler";
    const std::string kDoRussianRoulette = "doRussianRoulette";
    const std::string kNEEUsePerTileSG = "NEEUsePerTileSG";

    const std::string kDoImportanceSampleEmitters = "doImportanceSampleEmitters";

    const std::string kDoMNEE = "doMNEE";
    const std::string kMNEEMaxOccluders = "MNEEMaxOccluders";
    const std::string kMNEEMaxIterations = "MNEEMaxIterations";
    const std::string kMNEESolverThreshold = "MNEESolverThreshold";

    const std::string kBounceBufferName = "bounceBuffer";
}

PLTPT::PLTPT(std::shared_ptr<Device> pDevice) : RenderPass(std::move(pDevice)) {}

PLTPT::SharedPtr PLTPT::create(std::shared_ptr<Device> pDevice, const Dictionary& dict) {
    SharedPtr pPLTPT = SharedPtr(new PLTPT(std::move(pDevice)));
    pPLTPT->parseDictionary(dict);
    return pPLTPT;
}

void PLTPT::parseDictionary(const Dictionary& dict) {
    for (const auto& [key, value] : dict) {
        if (key == kMaxBounces) mMaxBounces = value;
        else if (key == kTileSize) mTileSize = value;
        else if (key == kDebugView) mDebugView = value;
        else if (key == kDebugViewIntensity) mDebugViewIntensity = value;
        else if (key == kSourcingAreaFromEmissiveGeometry) mSourcingAreaFromEmissiveGeometry = value;
        else if (key == kSourcingMaxBeamOmega) mSourcingMaxBeamOmega = value;
        else if (key == kSampleGenerator) mSelectedSampleGenerator = value;
        else if (key == kHWSS) mHWSS = value;
        else if (key == kHWSSDoMIS) mHWSSDoMIS = value;
        else if (key == kUseDirectLights) mUseDirectLights = value;
        else if (key == kUseEnvLights) mUseEnvLights = value;
        else if (key == kUseEmissiveLights) mUseEmissiveLights = value;
        else if (key == kUseAnalyticLights) mUseAnalyticLights = value;
        else if (key == kAlphaMasking) mAlphaMasking = value;
        else if (key == kDoNEE) mDoNEE = value;
        else if (key == kNEEUsePerTileSG) mNEEUsePerTileSG = value;
        else if (key == kDoMIS) mDoMIS = value;
        else if (key == kEmissiveSampler) mEmissiveSampler = value;
        else if (key == kDoRussianRoulette) mDoRussianRoulette = value;
        else if (key == kDoImportanceSampleEmitters) mDoImportanceSampleEmitters = value;
        else if (key == kDoMNEE) mDoMNEE = value;
        else if (key == kMNEEMaxOccluders) mMNEEMaxOccluders = value;
        else if (key == kMNEEMaxIterations) mMNEEMaxIterations = value;
        else if (key == kMNEESolverThreshold) mMNEESolverThreshold = value;
        else logError("Unknown field '{}' in PLTPathTracer dictionary.", key);
    }
}

Dictionary PLTPT::getScriptingDictionary() {
    Dictionary d;
    d[kMaxBounces] = mMaxBounces;
    d[kTileSize] = mTileSize;
    d[kDebugView] = mDebugView;
    d[kDebugViewIntensity] = mDebugViewIntensity;
    d[kSourcingAreaFromEmissiveGeometry] = mSourcingAreaFromEmissiveGeometry;
    d[kSourcingMaxBeamOmega] = mSourcingMaxBeamOmega;
    d[kSampleGenerator] = mSelectedSampleGenerator;
    d[kHWSS] = mHWSS;
    d[kHWSSDoMIS] = mHWSSDoMIS;
    d[kUseDirectLights] = mUseDirectLights;
    d[kUseEnvLights] = mUseEnvLights;
    d[kUseEmissiveLights] = mUseEmissiveLights;
    d[kUseAnalyticLights] = mUseAnalyticLights;
    d[kAlphaMasking] = mAlphaMasking;
    d[kDoNEE] = mDoNEE;
    d[kNEEUsePerTileSG] = mNEEUsePerTileSG;
    d[kDoImportanceSampleEmitters] = mDoImportanceSampleEmitters;
    d[kDoMNEE] = mDoMNEE;
    d[kDoMIS] = mDoMIS;
    d[kEmissiveSampler] = mEmissiveSampler;
    d[kDoRussianRoulette] = mDoRussianRoulette;
    d[kMNEEMaxOccluders] = mMNEEMaxOccluders;
    d[kMNEEMaxIterations] = mMNEEMaxIterations;
    d[kMNEESolverThreshold] = mMNEESolverThreshold;
    return d;
}

RenderPassReflection PLTPT::reflect(const CompileData& compileData) {
    // Define the required resources here
    RenderPassReflection reflector;
    addRenderPassInputs(reflector, kInputChannels);
    addRenderPassOutputs(reflector, kOutputChannels);
    addRenderPassOutputs(reflector, kSampleOutputChannels);
    addRenderPassOutputs(reflector, kSolveOutputChannels);
    return reflector;
}

Program::DefineList PLTPT::getDefines() const {
    Program::DefineList defines;

    // Specialize program.

    defines.add("VISIBILITY_RAY_ID", std::to_string(kVisibilityRayId));
    defines.add("SHADOW_RAY_ID", std::to_string(kShadowRayId));

    defines.add("MAX_BOUNCES", std::to_string(mMaxBounces));
    defines.add("TILE_SIZE", std::to_string(mTileSize));

    defines.add("HWSS_SAMPLES", std::to_string(mHWSS));
    defines.add("HWSS_MIS", mHWSSDoMIS ? "true" : "false");

    defines.add("DO_DEBUG_VIEW", mDebugView==0 ? "0" : "1");
    defines.add("DEBUG_VIEW_TYPE", std::to_string(mDebugView));

    defines.add("USE_DIRECT_LIGHTS", mUseDirectLights ? "true" : "false");
    defines.add("USE_EMISSIVE_LIGHTS", mUseEmissiveLights && mpScene->useEmissiveLights() ? "true" : "false");
    defines.add("USE_ENV_LIGHT", mUseEnvLights && mpScene->useEnvLight() ? "true" : "false");
    defines.add("USE_ANALYTIC_LIGHTS", mUseAnalyticLights && mpScene->useAnalyticLights() ? "true" : "false");

    defines.add("ALPHA_MASKING", mAlphaMasking ? "true" : "false");

    defines.add("DO_NEE", mDoNEE ? "true" : "false");
    defines.add("DO_MIS", mDoMIS ? "true" : "false");
    defines.add("DO_RUSSIAN_ROULETTE", mDoRussianRoulette ? "true" : "false");
    defines.add("NEE_USE_PER_TILE_SG_SELECTOR", mNEEUsePerTileSG ? "true" : "false");

    defines.add("DO_IMPORTANCE_SAMPLING_EMITTERS", mDoImportanceSampleEmitters ? "true" : "false");

    defines.add("DO_MNEE", mDoMNEE ? "true" : "false");
    defines.add("MNEE_MAX_MS_OCCLUDERS", std::to_string(mMNEEMaxOccluders));
    defines.add("MNEE_MAX_ITERATIONS", std::to_string(mMNEEMaxIterations));
    defines.add("MNEE_SOLVER_THRESHOLD", std::to_string(mMNEESolverThreshold));

    // Use compression for PackedHitInfo
    // defines.add("HIT_INFO_USE_COMPRESSION", "1");

    return defines;
}

void PLTPT::renderUI(Gui::Widgets& widget) {
    bool dirty = false;

    if (auto group = widget.group("Lights")) {
        widget.var("Max solid angle into which sourced beams propagate (sr)", mSourcingMaxBeamOmega, 1e-7f, 1.f, 1e-7f);
        widget.tooltip("Applies to all light sources. Specifies the maximal angular spread of generalized rays in a sourced beam. ", true);

        dirty |= widget.checkbox("Direct", mUseDirectLights);
        widget.tooltip("Use direct lighting.", true);
        dirty |= widget.checkbox("Env Maps", mUseEnvLights);
        widget.tooltip("Use environment maps for lighting.", true);
        dirty |= widget.checkbox("Analytic lights", mUseAnalyticLights);
        widget.tooltip("Use analytic light sources.", true);

        if (auto group = widget.group("Emissive geometry lights")) {
            dirty |= widget.checkbox("Emissive geometry lights", mUseEmissiveLights);
            widget.tooltip("Use emissive (area) light sources.", true);

            if (mUseEmissiveLights) {
                widget.var("Sourcing area for emissive geometry (mm^2)", mSourcingAreaFromEmissiveGeometry, 1e-4f, 1e+8f, 1e-4f);
                widget.tooltip("Beams sourced from emissive geometry will have this initial area. Default (1cm^2) is a good general choice when scene units roughly correspond to metres.", true);

                dirty |= widget.dropdown("Emissive geometry sampler", kEmissiveSamplerList, (uint32_t&)mEmissiveSampler);
                widget.tooltip("Selects which light sampler to use for importance sampling of emissive geometry.", true);

                if (mpEmissiveSampler) {
                    if (mpEmissiveSampler->renderUI(group)) dirty = true;
                }
            }
        }
    }

    if (auto group = widget.group("Spectral")) {
        dirty |= widget.slider("HWSS samples", mHWSS, 1u, 4u);
        mHWSS = std::max(1u, std::min(4u, mHWSS));
        widget.tooltip("Hero wavelength spectral sampling sample count.", true);

        dirty |= widget.checkbox("Spectral multiple importance sampling", mHWSSDoMIS);
        widget.tooltip("Do multiple importance sampling for spectral samples.", true);

        dirty |= widget.checkbox("Sample emissive spectra", mDoImportanceSampleEmitters);
        widget.tooltip("Importance sample the emission spectrum of emitters, when possible.", true);
    }

    if (auto group = widget.group("Materials")) {
        dirty |= widget.checkbox("Alpha masking", mAlphaMasking);
        widget.tooltip("Use alpha masking.", true);
    }

    if (auto group = widget.group("Path tracing")) {
        dirty |= widget.slider("Tile size", mTileSize, 1u, 1024u);
        mTileSize = std::max(1u, mTileSize);
        widget.tooltip("We partition the screen into tiles and render a tile at a time.", true);

        dirty |= widget.slider("Max bounces", mMaxBounces, 0u, 128u);
        mMaxBounces = std::max(0u, mMaxBounces);
        widget.tooltip("Maximum path length for indirect illumination.\n1 = direct only\n2 = one indirect bounce etc.", true);

        dirty |= widget.checkbox("NEE", mDoNEE);
        widget.tooltip("Perform next-event estimation.", true);
        if (mDoNEE) {
            dirty |= widget.checkbox("MIS", mDoMIS);
            widget.tooltip("Perform multiple importance sampling.", true);

            dirty |= widget.checkbox("Per-tile NEE light selector", mNEEUsePerTileSG);
            widget.tooltip("Select an NEE light source on a per-tile basis. Reduces divergence.", true);

            if (auto mneegroup = widget.group("MNEE")) {
                dirty |= widget.checkbox("Manifold Sampling", mDoMNEE);
                widget.tooltip("Manifold Sampling on NEE.", true);
                if (mDoMNEE) {
                    dirty |= widget.slider("Max occluders", mMNEEMaxOccluders, 1u, 2u);
                    dirty |= widget.slider("Max iterations", mMNEEMaxIterations, 1u, 200u);
                    dirty |= widget.var("Solver threshold", mMNEESolverThreshold, 1e-6f, 1e-2f, 1e-6f);
                }
            }
        }

        dirty |= widget.checkbox("Russian Roulette", mDoRussianRoulette);
        widget.tooltip("Perform \"Russian Roulette\" path termination.", true);
    }

    // Sample generator selection.
    if (auto group = widget.group("Sample generator")) {
        dirty |= widget.dropdown("##SampleGenerator", SampleGenerator::getGuiDropdownList(), mSelectedSampleGenerator);
    }

    if (auto group = widget.group("Debug view")) {
        dirty |= widget.dropdown("##DebugView", kDebugViewList, mDebugView);
        if (mDebugView != 0)
            widget.var("Overlay intensity", mDebugViewIntensity, 0.f, 1.f, 1e-3f);
    }

    // If rendering options that modify the output have changed, set flag to indicate that.
    // In execute() we will pass the flag to other passes for reset of temporal data etc.
    if (dirty)
        mOptionsChanged = true;
}

void PLTPT::execute(RenderContext* pRenderContext, const RenderData& renderData) {
    // Update refresh flag if options that affect the output have changed.
    auto& dict = renderData.getDictionary();
    const uint2& targetDim = renderData.getDefaultTextureDims();
    if (mOptionsChanged) {
        const auto& flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;

        mpEmissiveSampler = nullptr;

        // Need to update ray tracing structure memory budget
        if (mpScene)
            setScene(pRenderContext, mpScene);

        mOptionsChanged = false;
    }

    // If we have no scene, just clear the outputs and return.
    if (!mpScene) {
        const auto clear = [&](const auto& name) {
            Texture* pDst = renderData.getTexture(name).get();
            if (pDst) pRenderContext->clearTexture(pDst);
        };
        for (const auto& it : kOutputChannels)          clear(it.name);
        for (const auto& it : kSampleOutputChannels)    clear(it.name);
        for (const auto& it : kSolveOutputChannels)     clear(it.name);
        return;
    }

    if (!mpSampleGenerator)
        mpSampleGenerator = SampleGenerator::create(this->mpDevice, mSelectedSampleGenerator);

    if (mpScene->useEnvLight()) {
        if (!mpEnvMapSampler)
            mpEnvMapSampler = EnvMapSampler::create(this->mpDevice, mpScene->getEnvMap());
        FALCOR_ASSERT(mpEnvMapSampler);
    }
    else
        mpEnvMapSampler = nullptr;
    // Request the light collection if emissive lights are enabled.
    if (mpScene->getRenderSettings().useEmissiveLights)
        mpScene->getLightCollection(pRenderContext);
    if (mUseEmissiveLights && mpScene->useEmissiveLights()) {
        if (!mpEmissiveSampler) {
            switch (mEmissiveSampler) {
            case EmissiveLightSamplerType::Uniform:
                mpEmissiveSampler = EmissiveUniformSampler::create(pRenderContext, mpScene);
                break;
            case EmissiveLightSamplerType::Power:
                mpEmissiveSampler = EmissivePowerSampler::create(pRenderContext, mpScene);
                break;
            default:
                throw RuntimeError("Unknown emissive light sampler type");
            }
        }
        FALCOR_ASSERT(mpEmissiveSampler);

        mpEmissiveSampler->update(pRenderContext);
    }
    else
        mpEmissiveSampler = nullptr;

    // Configure depth-of-field.
    const bool useDOF = mpScene->getCamera()->getApertureRadius() > 0.f;
    if (useDOF && renderData[kInputViewDir] == nullptr) {
        logWarning("Depth-of-field requires the '{}' input. Expect incorrect shading.", kInputViewDir);
    }

    // Bounce buffer
    const auto bounceBufferElements = (mMaxBounces+1u) * mTileSize*mTileSize;
    if (mpBounceBuffer==nullptr || mpBounceBuffer->getElementCount() != (uint32_t)bounceBufferElements) {
        mpBounceBuffer = Buffer::createStructured(this->mpDevice.get(), kPerBouncePayloadSizeBytes, (uint32_t)bounceBufferElements, Resource::BindFlags::ShaderResource | Resource::BindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false);
        mpBounceBuffer->setName("PLTPT::mpBounceBuffer");
    }

    auto defines = getDefines();
    // For optional I/O resources, set 'is_valid_<name>' defines to inform the program of which ones it can access.
    // TODO: This should be moved to a more general mechanism using Slang.
    defines.add(getValidResourceDefines(kInputChannels, renderData));
    defines.add(getValidResourceDefines(kOutputChannels, renderData));

    if (mpSampleGenerator)  defines.add(mpSampleGenerator->getDefines());
    if (mpEmissiveSampler)  defines.add(mpEmissiveSampler->getDefines());
    mSampleTracer.pProgram->addDefines(defines);
    mSampleTracer.pProgram->addDefines(getValidResourceDefines(kSampleOutputChannels, renderData));
    mSolveTracer.pProgram->addDefines(defines);
    mSolveTracer.pProgram->addDefines(getValidResourceDefines(kSolveOutputChannels, renderData));

    // Prepare program vars. This may trigger shader compilation.
    // The program should have all necessary defines set at this point.
    if (!mSampleTracer.pVars || !mSolveTracer.pVars) prepareVars();
    FALCOR_ASSERT(mSampleTracer.pVars && mSolveTracer.pVars);

    // Get dimensions of ray dispatch.
    FALCOR_ASSERT(targetDim.x > 0 && targetDim.y > 0);
    const auto tiles = (targetDim + uint2(mTileSize - 1)) / mTileSize;


    // Set constants.
    auto varSetter = [&](auto& var) {
        var["CB"]["gFrameCount"] = mFrameCount;
        var["CB"]["kOutputSize"] = targetDim;
        var["CB"]["kSourcingAreaFromEmissiveGeometry"] = mSourcingAreaFromEmissiveGeometry;
        var["CB"]["kSourcingMaxBeamOmega"] = mSourcingMaxBeamOmega;

        if (mpEnvMapSampler)    mpEnvMapSampler->setShaderData(var["CB"]["envMapSampler"]);
        if (mpEmissiveSampler)  mpEmissiveSampler->setShaderData(var["CB"]["emissiveSampler"]);
        if (mDebugView != 0)
            var["CB"]["kDebugViewIntensity"] = mDebugViewIntensity;

        var["bounceBuffer"] = mpBounceBuffer;
    };

    varSetter(mSampleTracer.pVars->getRootVar());
    varSetter(mSolveTracer.pVars->getRootVar());


    // Bind I/O buffers. These needs to be done per-frame as the buffers may change anytime.
    const auto& bind = [&](const ChannelDesc& desc, bool sample=true, bool solve=true) {
        if (!desc.texname.empty()) {
            if (sample) mSampleTracer.pVars->getRootVar()[desc.texname] = renderData.getTexture(desc.name);
            if (solve)  mSolveTracer.pVars->getRootVar()[desc.texname]  = renderData.getTexture(desc.name);
        }
    };
    for (const auto& channel : kInputChannels)          bind(channel);
    for (const auto& channel : kOutputChannels)         bind(channel);
    for (const auto& channel : kSampleOutputChannels)   bind(channel, true, false);
    for (const auto& channel : kSolveOutputChannels)    bind(channel, false, true);


    // Render
    for (uint x=0;x<tiles.x;++x)
    for (uint y=0;y<tiles.y;++y) {
        mSampleTracer.pVars->getRootVar()["CB"]["kTile"] = uint2(x,y);
        mSolveTracer.pVars->getRootVar()["CB"]["kTile"] = uint2(x,y);

        mpScene->raytrace(pRenderContext, mSampleTracer.pProgram.get(), mSampleTracer.pVars, { mTileSize, mTileSize, 1 });
        mpScene->raytrace(pRenderContext, mSolveTracer.pProgram.get(),  mSolveTracer.pVars,  { mTileSize, mTileSize, 1 });
    }


    mFrameCount++;
}

void PLTPT::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene) {
    mSampleTracer = { nullptr, nullptr, nullptr };
    mSolveTracer = { nullptr, nullptr, nullptr };

    mpEnvMapSampler = nullptr;
    mpSampleGenerator = nullptr;

    mpScene = pScene;

    mFrameCount = 0;

    if (mpScene) {
        const auto& globalTypeConformances = mpScene->getMaterialSystem()->getTypeConformances();

        RtProgram::Desc solveDesc, sampleDesc;

        sampleDesc.addShaderModules(pScene->getShaderModules());
        sampleDesc.addShaderLibrary(kSamplePassFileName);
        sampleDesc.setShaderModel(kShaderModel);
        sampleDesc.setMaxPayloadSize(kBasePayloadSizeBytes);
        sampleDesc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
        sampleDesc.setMaxTraceRecursionDepth(kMaxRecursionDepth);

        solveDesc.addShaderModules(pScene->getShaderModules());
        solveDesc.addShaderLibrary(kSolvePassFileName);
        solveDesc.setShaderModel(kShaderModel);
        solveDesc.setMaxPayloadSize(kShadowPayloadSizeBytes);
        solveDesc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
        solveDesc.setMaxTraceRecursionDepth(1);

        if (!mpScene->hasProceduralGeometry()) {
            sampleDesc.setPipelineFlags(RtPipelineFlags::SkipProceduralPrimitives);
            solveDesc.setPipelineFlags(RtPipelineFlags::SkipProceduralPrimitives);
        }

        // Sample pass
        mSampleTracer.pBindingTable = RtBindingTable::create(1, 1, mpScene->getGeometryCount());
        mSampleTracer.pBindingTable->setRayGen(sampleDesc.addRayGen("main", globalTypeConformances));
        mSampleTracer.pBindingTable->setMiss(0, sampleDesc.addMiss("scatterMiss"));
        mSampleTracer.pBindingTable->setHitGroup(0, mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), sampleDesc.addHitGroup("scatterTriangleMeshClosestHit"));

        mSampleTracer.pProgram = RtProgram::create(this->mpDevice, sampleDesc, mpScene->getSceneDefines());

        // Solve pass
        mSolveTracer.pBindingTable = RtBindingTable::create(2, 2, mpScene->getGeometryCount());
        mSolveTracer.pBindingTable->setRayGen(solveDesc.addRayGen("main", globalTypeConformances));
        mSolveTracer.pBindingTable->setMiss(kVisibilityRayId, solveDesc.addMiss("visibilityMiss"));
        mSolveTracer.pBindingTable->setHitGroup(kShadowRayId, mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), solveDesc.addHitGroup("shadowTriangleMeshHit"));

        mSolveTracer.pProgram = RtProgram::create(this->mpDevice, solveDesc, mpScene->getSceneDefines());
    }
}

void PLTPT::prepareVars() {
    FALCOR_ASSERT(mpScene);
    FALCOR_ASSERT(mSampleTracer.pProgram);
    FALCOR_ASSERT(mSolveTracer.pProgram);

    // Configure program.
    mSampleTracer.pProgram->setTypeConformances(mpScene->getTypeConformances());
    mSolveTracer.pProgram->setTypeConformances(mpScene->getTypeConformances());

    // Create program variables for the current program.
    // This may trigger shader compilation. If it fails, throw an exception to abort rendering.
    mSampleTracer.pVars = RtProgramVars::create(this->mpDevice, mSampleTracer.pProgram, mSampleTracer.pBindingTable);
    mSolveTracer.pVars = RtProgramVars::create(this->mpDevice, mSolveTracer.pProgram, mSolveTracer.pBindingTable);

    // Bind utility classes into shared data.
    if (mpSampleGenerator) {
        mpSampleGenerator->setShaderData(mSampleTracer.pVars->getRootVar());
        mpSampleGenerator->setShaderData(mSolveTracer.pVars->getRootVar());
    }
}
