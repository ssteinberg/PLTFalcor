/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
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
#include "Device.h"
#include "Handles.h"
#include "NativeHandle.h"
#include "Core/Macros.h"
#include "Core/Program/ProgramVersion.h"

namespace Falcor
{
#if FALCOR_HAS_D3D12
class D3D12RootSignature;
#endif

class FALCOR_API ComputeStateObject
{
public:
    using SharedPtr = std::shared_ptr<ComputeStateObject>;

    class FALCOR_API Desc
    {
    public:
        Desc& setProgramKernels(const ProgramKernels::SharedConstPtr& pProgram)
        {
            mpProgram = pProgram;
            return *this;
        }

#if FALCOR_HAS_D3D12
        /**
         * Set a D3D12 root signature to use instead of the one that comes with the program kernel.
         * This function is supported on D3D12 only.
         * @param[in] pRootSignature An overriding D3D12RootSignature object to use in the compute state.
         */
        Desc& setD3D12RootSignatureOverride(const std::shared_ptr<const D3D12RootSignature>& pRootSignature)
        {
            mpD3D12RootSignatureOverride = pRootSignature;
            return *this;
        }
#endif
        const ProgramKernels::SharedConstPtr getProgramKernels() const { return mpProgram; }
        ProgramVersion::SharedConstPtr getProgramVersion() const { return mpProgram->getProgramVersion(); }
        bool operator==(const Desc& other) const;

    private:
        friend class ComputeStateObject;
        ProgramKernels::SharedConstPtr mpProgram;
#if FALCOR_HAS_D3D12
        std::shared_ptr<const D3D12RootSignature> mpD3D12RootSignatureOverride;
#endif
    };

    ~ComputeStateObject();

    /**
     * Create a compute state object.
     * @param[in] desc State object description.
     * @return New object, or throws an exception if creation failed.
     */
    static SharedPtr create(Device* pDevice, const Desc& desc);

    gfx::IPipelineState* getGfxPipelineState() const { return mGfxPipelineState; }

    /**
     * Returns the native API handle:
     * - D3D12: ID3D12PipelineState*
     * - Vulkan: VkPipeline
     */
    NativeHandle getNativeHandle() const;

    const Desc& getDesc() const { return mDesc; }

private:
    ComputeStateObject(std::shared_ptr<Device> pDevice, const Desc& desc);

    std::shared_ptr<Device> mpDevice;
    Desc mDesc;
    Slang::ComPtr<gfx::IPipelineState> mGfxPipelineState;
};
} // namespace Falcor
