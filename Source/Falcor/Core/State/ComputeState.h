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
#include "StateGraph.h"
#include "Core/Macros.h"
#include "Core/API/ComputeStateObject.h"
#include "Core/Program/ComputeProgram.h"
#include <memory>

namespace Falcor
{
class ComputeVars;

/**
 * Compute state.
 * This class contains the entire state required by a single dispatch call. It's not an immutable object - you can change it dynamically
 * during rendering. The recommended way to use it is to create multiple ComputeState objects (ideally, a single object per program)
 */
class FALCOR_API ComputeState
{
public:
    using SharedPtr = std::shared_ptr<ComputeState>;

    ~ComputeState() = default;

    /**
     * Create a new state object.
     * @param pDevice GPU device.
     * @return A new object, or an exception is thrown if creation failed.
     */
    static SharedPtr create(std::shared_ptr<Device> pDevice);

    /**
     * Copy constructor. Useful if you need to make minor changes to an already existing object
     */
    SharedPtr operator=(const SharedPtr& other);

    /**
     * Bind a program to the pipeline
     */
    ComputeState& setProgram(const ComputeProgram::SharedPtr& pProgram)
    {
        mpProgram = pProgram;
        return *this;
    }

    /**
     * Get the currently bound program
     */
    ComputeProgram::SharedPtr getProgram() const { return mpProgram; }

    /**
     * Get the active compute state object
     */
    ComputeStateObject::SharedPtr getCSO(const ComputeVars* pVars);

private:
    ComputeState(std::shared_ptr<Device> pDevice);

    std::shared_ptr<Device> mpDevice;
    ComputeProgram::SharedPtr mpProgram;
    ComputeStateObject::Desc mDesc;

    struct CachedData
    {
        const ProgramKernels* pProgramKernels = nullptr;
    };
    CachedData mCachedData;

    using StateGraph = StateGraph<ComputeStateObject::SharedPtr, void*>;
    StateGraph::SharedPtr mpCsoGraph;
};
} // namespace Falcor
