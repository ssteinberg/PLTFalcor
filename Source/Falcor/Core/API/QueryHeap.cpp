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
#include "QueryHeap.h"
#include "Device.h"
#include "GFXAPI.h"

namespace Falcor
{

QueryHeap::SharedPtr QueryHeap::create(Device* pDevice, Type type, uint32_t count)
{
    return SharedPtr(new QueryHeap(pDevice->shared_from_this(), type, count));
}

QueryHeap::QueryHeap(std::shared_ptr<Device> pDevice, Type type, uint32_t count) : mCount(count), mType(type)
{
    FALCOR_ASSERT(pDevice);
    gfx::IQueryPool::Desc desc = {};
    desc.count = count;
    switch (type)
    {
    case Type::Timestamp:
        desc.type = gfx::QueryType::Timestamp;
        break;
    default:
        FALCOR_UNREACHABLE();
        break;
    }
    FALCOR_GFX_CALL(pDevice->getGfxDevice()->createQueryPool(desc, mGfxQueryPool.writeRef()));
}
} // namespace Falcor
