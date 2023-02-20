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

#include "Falcor.h"

#include "Rendering/Lights/EmissiveLightSampler.h"
#include "Rendering/Lights/EnvMapSampler.h"
#include "Utils/Sampling/SampleGenerator.h"

#include "DebugViewType.slangh"

using namespace Falcor;

class PLTPT : public RenderPass {
public:
    FALCOR_PLUGIN_CLASS(PLTPT, "PLTPT", "Physical Light Transport Path Tracer.");

    using SharedPtr = std::shared_ptr<PLTPT>;

    static SharedPtr create(std::shared_ptr<Device> pDevice, const Dictionary& dict);

    virtual Dictionary getScriptingDictionary() override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

    void setSourcingAreaFromEmissiveGeometry(float area) { mSourcingAreaFromEmissiveGeometry = area; }
    float getSourcingAreaFromEmissiveGeometry() const { return mSourcingAreaFromEmissiveGeometry; }

private:
    PLTPT(std::shared_ptr<Device> pDevice);
    Program::DefineList PLTPT::getDefines() const;
    void parseDictionary(const Dictionary& dict);
    void prepareVars();

    // Internal state
    Scene::SharedPtr            mpScene;                        ///< Current scene.
    SampleGenerator::SharedPtr  mpSampleGenerator;              ///< GPU sample generator.
    EnvMapSampler::SharedPtr    mpEnvMapSampler;
    EmissiveLightSampler::SharedPtr mpEmissiveSampler;

    uint32_t                    mTileSize = 512;                ///< Size of a tile
    uint                        mMaxBounces = 32;               ///< Max number of indirect bounces (0 = none).
    Buffer::SharedPtr           mpBounceBuffer;                 ///< Per-tile bounce buffer.

    // Configuration
    uint32_t                    mSelectedSampleGenerator = SAMPLE_GENERATOR_DEFAULT;            ///< Which pseudorandom sample generator to use.

    uint32_t                    mDebugView = (uint32_t)DebugViewType::none;
    float                       mDebugViewIntensity = 1.f;

    float                       mSourcingAreaFromEmissiveGeometry = 1.f;       ///< Sourcing area for emissive geometry (default - 1mm^2)
    float                       mSourcingMaxBeamOmega = .025f;                   ///< Max diffusivity of sourced beams

    uint                        mHWSS = 4;                      ///< Number of HWSS samples
    bool                        mHWSSDoMIS = true;

    bool                        mUseDirectLights = true;
    bool                        mUseEnvLights = true;
    bool                        mUseEmissiveLights = true;
    bool                        mUseAnalyticLights = true;

    bool                        mAlphaMasking = true;

    bool                        mDoNEE = true;
    bool                        mDoMIS = true;
    EmissiveLightSamplerType    mEmissiveSampler = EmissiveLightSamplerType::Power;
    bool                        mDoRussianRoulette = true;
    bool                        mNEEUsePerTileSG = false;

    bool                        mDoImportanceSampleEmitters = true;

    bool                        mDoMNEE = true;
    uint                        mMNEEMaxOccluders = 2;
    uint                        mMNEEMaxIterations = 60;
    float                       mMNEESolverThreshold = 5e-5f;

    // Runtime data
    uint                        mFrameCount = 0;                ///< Frame count since scene was loaded.
    bool                        mOptionsChanged = false;

    // Ray tracing program.
    struct tracer_t {
        RtProgram::SharedPtr pProgram;
        RtBindingTable::SharedPtr pBindingTable;
        RtProgramVars::SharedPtr pVars;
    };
    tracer_t mSampleTracer, mSolveTracer;
};

