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
#include "ParameterBlock.h"
#include "Device.h"
#include "CopyContext.h"
#include "GFXAPI.h"
#include "Core/Assert.h"
#include "Core/Errors.h"
#include "Core/Program/ProgramVersion.h"
#include "Utils/Logger.h"

namespace Falcor
{
namespace
{
gfx::ShaderOffset getGFXShaderOffset(const UniformShaderVarOffset& offset)
{
    gfx::ShaderOffset result;
    result.bindingArrayIndex = 0;
    result.bindingRangeIndex = 0;
    result.uniformOffset = offset.getByteOffset();
    return result;
}

gfx::ShaderOffset getGFXShaderOffset(const ParameterBlock::BindLocation& bindLoc)
{
    gfx::ShaderOffset gfxOffset = {};
    gfxOffset.bindingArrayIndex = bindLoc.getResourceArrayIndex();
    gfxOffset.bindingRangeIndex = bindLoc.getResourceRangeIndex();
    gfxOffset.uniformOffset = bindLoc.getUniform().getByteOffset();
    return gfxOffset;
}

bool isSrvType(const ReflectionType::SharedConstPtr& pType)
{
    auto resourceType = pType->unwrapArray()->asResourceType();
    if (resourceType->getType() == ReflectionResourceType::Type::Sampler ||
        resourceType->getType() == ReflectionResourceType::Type::ConstantBuffer)
        return false;

    switch (resourceType->getShaderAccess())
    {
    case ReflectionResourceType::ShaderAccess::Read:
        return true;
    case ReflectionResourceType::ShaderAccess::ReadWrite:
        return false;
    default:
        FALCOR_UNREACHABLE();
        return false;
    }
}

bool isUavType(const ReflectionType::SharedConstPtr& pType)
{
    auto resourceType = pType->unwrapArray()->asResourceType();
    if (resourceType->getType() == ReflectionResourceType::Type::Sampler ||
        resourceType->getType() == ReflectionResourceType::Type::ConstantBuffer)
        return false;

    switch (resourceType->getShaderAccess())
    {
    case ReflectionResourceType::ShaderAccess::Read:
        return false;
    case ReflectionResourceType::ShaderAccess::ReadWrite:
        return true;
    default:
        FALCOR_UNREACHABLE();
        return false;
    }
}

bool isCbvType(const ReflectionType::SharedConstPtr& pType)
{
    auto resourceType = pType->unwrapArray()->asResourceType();
    if (resourceType->getType() == ReflectionResourceType::Type::ConstantBuffer)
    {
        FALCOR_ASSERT(resourceType->getShaderAccess() == ReflectionResourceType::ShaderAccess::Read);
        return true;
    }
    return false;
}
} // namespace

ParameterBlock::SharedPtr ParameterBlock::create(
    Device* pDevice,
    const std::shared_ptr<const ProgramVersion>& pProgramVersion,
    const ReflectionType::SharedConstPtr& pElementType
)
{
    if (!pElementType)
        throw ArgumentError("Can't create a parameter block without type information");
    auto pReflection = ParameterBlockReflection::create(pProgramVersion.get(), pElementType);
    return create(pDevice, pReflection);
}

ParameterBlock::SharedPtr ParameterBlock::create(Device* pDevice, const ParameterBlockReflection::SharedConstPtr& pReflection)
{
    FALCOR_ASSERT(pReflection);
    return SharedPtr(new ParameterBlock(pDevice->shared_from_this(), pReflection->getProgramVersion(), pReflection));
}

ParameterBlock::SharedPtr ParameterBlock::create(
    Device* pDevice,
    const std::shared_ptr<const ProgramVersion>& pProgramVersion,
    const std::string& typeName
)
{
    FALCOR_ASSERT(pProgramVersion);
    return ParameterBlock::create(pDevice, pProgramVersion, pProgramVersion->getReflector()->findType(typeName));
}

ShaderVar ParameterBlock::getRootVar() const
{
    return ShaderVar(const_cast<ParameterBlock*>(this));
}

ShaderVar ParameterBlock::findMember(const std::string& varName) const
{
    return getRootVar().findMember(varName);
}

ShaderVar ParameterBlock::findMember(uint32_t index) const
{
    return getRootVar().findMember(index);
}

size_t ParameterBlock::getElementSize() const
{
    return mpReflector->getElementType()->getByteSize();
}

UniformShaderVarOffset ParameterBlock::getVariableOffset(const std::string& varName) const
{
    return getElementType()->getZeroOffset()[varName];
}

void ParameterBlock::createConstantBuffers(const ShaderVar& var)
{
    auto pType = var.getType();
    if (pType->getResourceRangeCount() == 0)
        return;

    switch (pType->getKind())
    {
    case ReflectionType::Kind::Struct:
    {
        auto pStructType = pType->asStructType();
        uint32_t memberCount = pStructType->getMemberCount();
        for (uint32_t i = 0; i < memberCount; ++i)
            createConstantBuffers(var[i]);
    }
    break;
    case ReflectionType::Kind::Resource:
    {
        auto pResourceType = pType->asResourceType();
        switch (pResourceType->getType())
        {
        case ReflectionResourceType::Type::ConstantBuffer:
        {
            auto pCB = ParameterBlock::create(mpDevice.get(), pResourceType->getParameterBlockReflector());
            var.setParameterBlock(pCB);
        }
        break;

        default:
            break;
        }
    }
    break;

    default:
        break;
    }
}

void ParameterBlock::prepareResource(CopyContext* pContext, Resource* pResource, bool isUav)
{
    if (!pResource)
        return;

    // If it's a buffer with a UAV counter, insert a UAV barrier
    const Buffer* pBuffer = pResource->asBuffer().get();
    if (isUav && pBuffer && pBuffer->getUAVCounter())
    {
        pContext->resourceBarrier(pBuffer->getUAVCounter().get(), Resource::State::UnorderedAccess);
        pContext->uavBarrier(pBuffer->getUAVCounter().get());
    }

    bool insertBarrier = true;
    insertBarrier = (is_set(pResource->getBindFlags(), Resource::BindFlags::AccelerationStructure) == false);
    if (insertBarrier)
    {
        insertBarrier = !pContext->resourceBarrier(pResource, isUav ? Resource::State::UnorderedAccess : Resource::State::ShaderResource);
    }

    // Insert UAV barrier automatically if the resource is an UAV that is already in UnorderedAccess state.
    // Otherwise the user would have to insert barriers explicitly between passes accessing UAVs, which is easily forgotten.
    if (insertBarrier && isUav)
        pContext->uavBarrier(pResource);
}

// Template specialization to allow setting booleans on a parameter block.
// On the host side a bool is 1B and the device 4B. We cast bools to 32-bit integers here.
// Note that this applies to our boolN vectors as well, which are currently 1B per element.

template<>
FALCOR_API bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const bool& value)
{
    int32_t v = value ? 1 : 0;
    return setVariable(offset, v);
}

template<>
FALCOR_API bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const bool2& value)
{
    int2 v = {value.x ? 1 : 0, value.y ? 1 : 0};
    return setVariable(offset, v);
}

template<>
FALCOR_API bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const bool3& value)
{
    int3 v = {value.x ? 1 : 0, value.y ? 1 : 0, value.z ? 1 : 0};
    return setVariable(offset, v);
}

template<>
FALCOR_API bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const bool4& value)
{
    int4 v = {value.x ? 1 : 0, value.y ? 1 : 0, value.z ? 1 : 0, value.w ? 1 : 0};
    return setVariable(offset, v);
}

ParameterBlock::~ParameterBlock() {}

ParameterBlock::ParameterBlock(std::shared_ptr<Device> pDevice, const ProgramReflection::SharedConstPtr& pReflector)
    : mpDevice(std::move(pDevice)), mpProgramVersion(pReflector->getProgramVersion()), mpReflector(pReflector->getDefaultParameterBlock())
{
    FALCOR_GFX_CALL(mpDevice->getGfxDevice()->createMutableRootShaderObject(
        pReflector->getProgramVersion()->getKernels(mpDevice.get(), nullptr)->getGfxProgram(), mpShaderObject.writeRef()
    ));
    initializeResourceBindings();
    createConstantBuffers(getRootVar());
}

ParameterBlock::ParameterBlock(
    std::shared_ptr<Device> pDevice,
    const std::shared_ptr<const ProgramVersion>& pProgramVersion,
    const ParameterBlockReflection::SharedConstPtr& pReflection
)
    : mpDevice(std::move(pDevice)), mpProgramVersion(pProgramVersion), mpReflector(pReflection)
{
    FALCOR_GFX_CALL(mpDevice->getGfxDevice()->createMutableShaderObjectFromTypeLayout(
        pReflection->getElementType()->getSlangTypeLayout(), mpShaderObject.writeRef()
    ));
    initializeResourceBindings();
    createConstantBuffers(getRootVar());
}

void ParameterBlock::initializeResourceBindings()
{
    for (uint32_t i = 0; i < mpReflector->getResourceRangeCount(); i++)
    {
        auto info = mpReflector->getResourceRangeBindingInfo(i);
        auto range = mpReflector->getResourceRange(i);
        for (uint32_t arrayIndex = 0; arrayIndex < range.count; arrayIndex++)
        {
            gfx::ShaderOffset offset = {};
            offset.bindingRangeIndex = i;
            offset.bindingArrayIndex = arrayIndex;
            switch (range.descriptorType)
            {
            case ShaderResourceType::Sampler:
                mpShaderObject->setSampler(offset, mpDevice->getDefaultSampler()->getGfxSamplerState());
                break;
            case ShaderResourceType::TextureSrv:
            case ShaderResourceType::TextureUav:
            case ShaderResourceType::RawBufferSrv:
            case ShaderResourceType::RawBufferUav:
            case ShaderResourceType::TypedBufferSrv:
            case ShaderResourceType::TypedBufferUav:
            case ShaderResourceType::StructuredBufferUav:
            case ShaderResourceType::StructuredBufferSrv:
            case ShaderResourceType::AccelerationStructureSrv:
                mpShaderObject->setResource(offset, nullptr);
                break;
            }
        }
    }
}

bool ParameterBlock::setBlob(const void* pSrc, UniformShaderVarOffset offset, size_t size)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(offset);
    return SLANG_SUCCEEDED(mpShaderObject->setData(gfxOffset, pSrc, size));
}

bool ParameterBlock::setBlob(const void* pSrc, size_t offset, size_t size)
{
    gfx::ShaderOffset gfxOffset = {};
    gfxOffset.uniformOffset = offset;
    return SLANG_SUCCEEDED(mpShaderObject->setData(gfxOffset, pSrc, size));
}

bool ParameterBlock::setBuffer(const std::string& name, const Buffer::SharedPtr& pBuffer)
{
    auto var = getRootVar()[name];
    return var.setBuffer(pBuffer);
}

bool ParameterBlock::setBuffer(const BindLocation& bindLoc, const Buffer::SharedPtr& pResource)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLoc);
    if (isUavType(bindLoc.getType()))
    {
        auto pUAV = pResource ? pResource->getUAV() : nullptr;
        mpShaderObject->setResource(gfxOffset, pUAV ? pUAV->getGfxResourceView() : nullptr);
        mUAVs[gfxOffset] = pUAV;
        mResources[gfxOffset] = pResource;
    }
    else if (isSrvType(bindLoc.getType()))
    {
        auto pSRV = pResource ? pResource->getSRV() : nullptr;
        mpShaderObject->setResource(gfxOffset, pSRV ? pSRV->getGfxResourceView() : nullptr);
        mSRVs[gfxOffset] = pSRV;
        mResources[gfxOffset] = pResource;
    }
    else
    {
        logError("Error trying to bind resource to non SRV/UAV variable. Ignoring call.");
        return false;
    }
    return true;
}

Buffer::SharedPtr ParameterBlock::getBuffer(const std::string& name) const
{
    auto var = getRootVar()[name];
    return var.getBuffer();
}

Buffer::SharedPtr ParameterBlock::getBuffer(const BindLocation& bindLoc) const
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLoc);
    if (isUavType(bindLoc.getType()))
    {
        auto iter = mUAVs.find(gfxOffset);
        if (iter == mUAVs.end())
            return nullptr;
        auto pResource = iter->second->getResource();
        return pResource ? pResource->asBuffer() : nullptr;
    }
    else if (isSrvType(bindLoc.getType()))
    {
        auto iter = mSRVs.find(gfxOffset);
        if (iter == mSRVs.end())
            return nullptr;
        auto pResource = iter->second->getResource();
        return pResource ? pResource->asBuffer() : nullptr;
    }
    else
    {
        logError("Error trying to bind resource to non SRV/UAV variable. Ignoring call.");
        return nullptr;
    }
}

bool ParameterBlock::setParameterBlock(const std::string& name, const ParameterBlock::SharedPtr& pBlock)
{
    auto var = getRootVar()[name];
    return var.setParameterBlock(pBlock);
}

bool ParameterBlock::setParameterBlock(const BindLocation& bindLocation, const ParameterBlock::SharedPtr& pBlock)
{
    auto gfxOffset = getGFXShaderOffset(bindLocation);
    mParameterBlocks[gfxOffset] = pBlock;
    return SLANG_SUCCEEDED(mpShaderObject->setObject(gfxOffset, pBlock ? pBlock->mpShaderObject : nullptr));
}

ParameterBlock::SharedPtr ParameterBlock::getParameterBlock(const std::string& name) const
{
    auto var = getRootVar()[name];
    return var.getParameterBlock();
}

ParameterBlock::SharedPtr ParameterBlock::getParameterBlock(const BindLocation& bindLocation) const
{
    auto gfxOffset = getGFXShaderOffset(bindLocation);
    auto iter = mParameterBlocks.find(gfxOffset);
    if (iter == mParameterBlocks.end())
        return nullptr;
    return iter->second;
}

template<typename VarType>
bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const VarType& value)
{
    auto gfxOffset = getGFXShaderOffset(offset);
    return SLANG_SUCCEEDED(mpShaderObject->setData(gfxOffset, &value, sizeof(VarType)));
}

#define set_constant_by_offset(_t) template FALCOR_API bool ParameterBlock::setVariable(UniformShaderVarOffset offset, const _t& value)
set_constant_by_offset(uint32_t);
set_constant_by_offset(uint2);
set_constant_by_offset(uint3);
set_constant_by_offset(uint4);

set_constant_by_offset(int32_t);
set_constant_by_offset(int2);
set_constant_by_offset(int3);
set_constant_by_offset(int4);

set_constant_by_offset(float);
set_constant_by_offset(float2);
set_constant_by_offset(float3);
set_constant_by_offset(float4);

set_constant_by_offset(rmcv::mat1x4);
set_constant_by_offset(rmcv::mat2x4);
set_constant_by_offset(rmcv::mat3x4);
set_constant_by_offset(rmcv::mat4x4);

set_constant_by_offset(uint64_t);

#undef set_constant_by_offset

bool ParameterBlock::setTexture(const std::string& name, const Texture::SharedPtr& pTexture)
{
    auto var = getRootVar()[name];
    return var.setTexture(pTexture);
}

bool ParameterBlock::setTexture(const BindLocation& bindLocation, const Texture::SharedPtr& pTexture)
{
    const auto& bindingInfo = mpReflector->getResourceRangeBindingInfo(bindLocation.getResourceRangeIndex());
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    if (isUavType(bindLocation.getType()))
    {
        auto pUAV = pTexture ? pTexture->getUAV() : nullptr;
        mpShaderObject->setResource(gfxOffset, pUAV ? pUAV->getGfxResourceView() : nullptr);
        mUAVs[gfxOffset] = pUAV;
        mResources[gfxOffset] = pTexture;
    }
    else if (isSrvType(bindLocation.getType()))
    {
        auto pSRV = pTexture ? pTexture->getSRV() : nullptr;
        mpShaderObject->setResource(gfxOffset, pSRV ? pSRV->getGfxResourceView() : nullptr);
        mSRVs[gfxOffset] = pSRV;
        mResources[gfxOffset] = pTexture;
    }
    else
    {
        logError("Error trying to bind resource to non SRV/UAV variable. Ignoring call.");
        return false;
    }
    return true;
}

Texture::SharedPtr ParameterBlock::getTexture(const std::string& name) const
{
    auto var = getRootVar()[name];
    return var.getTexture();
}

Texture::SharedPtr ParameterBlock::getTexture(const BindLocation& bindLocation) const
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    if (isUavType(bindLocation.getType()))
    {
        auto iter = mUAVs.find(gfxOffset);
        if (iter == mUAVs.end())
            return nullptr;
        auto pResource = iter->second->getResource();
        return pResource ? pResource->asTexture() : nullptr;
    }
    else if (isSrvType(bindLocation.getType()))
    {
        auto iter = mSRVs.find(gfxOffset);
        if (iter == mSRVs.end())
            return nullptr;
        auto pResource = iter->second->getResource();
        return pResource ? pResource->asTexture() : nullptr;
    }
    else
    {
        logError("Error trying to bind resource to non SRV/UAV variable. Ignoring call.");
        return nullptr;
    }
}

bool ParameterBlock::setSrv(const BindLocation& bindLocation, const ShaderResourceView::SharedPtr& pSrv)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    if (isSrvType(bindLocation.getType()))
    {
        mpShaderObject->setResource(gfxOffset, pSrv ? pSrv->getGfxResourceView() : nullptr);
        mSRVs[gfxOffset] = pSrv;
        mResources[gfxOffset] = pSrv ? pSrv->getResource() : nullptr;
    }
    else
    {
        logError("Error trying to bind SRV to a non SRV variable. Ignoring call.");
        return false;
    }
    return true;
}

bool ParameterBlock::setUav(const BindLocation& bindLocation, const UnorderedAccessView::SharedPtr& pUav)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    if (isUavType(bindLocation.getType()))
    {
        mpShaderObject->setResource(gfxOffset, pUav ? pUav->getGfxResourceView() : nullptr);
        mUAVs[gfxOffset] = pUav;
        mResources[gfxOffset] = pUav ? pUav->getResource() : nullptr;
    }
    else
    {
        logError("Error trying to bind UAV to a non UAV variable. Ignoring call.");
        return false;
    }
    return true;
}

bool ParameterBlock::setAccelerationStructure(const BindLocation& bindLocation, const RtAccelerationStructure::SharedPtr& pAccl)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    mAccelerationStructures[gfxOffset] = pAccl;
    return SLANG_SUCCEEDED(mpShaderObject->setResource(gfxOffset, pAccl ? pAccl->getGfxAccelerationStructure() : nullptr));
}

ShaderResourceView::SharedPtr ParameterBlock::getSrv(const BindLocation& bindLocation) const
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    auto iter = mSRVs.find(gfxOffset);
    if (iter == mSRVs.end())
        return nullptr;
    return iter->second;
}

UnorderedAccessView::SharedPtr ParameterBlock::getUav(const BindLocation& bindLocation) const
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    auto iter = mUAVs.find(gfxOffset);
    if (iter == mUAVs.end())
        return nullptr;
    return iter->second;
}

RtAccelerationStructure::SharedPtr ParameterBlock::getAccelerationStructure(const BindLocation& bindLocation) const
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    auto iter = mAccelerationStructures.find(gfxOffset);
    if (iter == mAccelerationStructures.end())
        return nullptr;
    return iter->second;
}

bool ParameterBlock::setSampler(const std::string& name, const Sampler::SharedPtr& pSampler)
{
    auto var = getRootVar()[name];
    return var.setSampler(pSampler);
}

bool ParameterBlock::setSampler(const BindLocation& bindLocation, const Sampler::SharedPtr& pSampler)
{
    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    auto pBoundSampler = pSampler ? pSampler : mpDevice->getDefaultSampler();
    mSamplers[gfxOffset] = pBoundSampler;
    return SLANG_SUCCEEDED(mpShaderObject->setSampler(gfxOffset, pBoundSampler->getGfxSamplerState()));
}

const Sampler::SharedPtr& ParameterBlock::getSampler(const BindLocation& bindLocation) const
{
    static const Sampler::SharedPtr pNull;

    gfx::ShaderOffset gfxOffset = getGFXShaderOffset(bindLocation);
    auto iter = mSamplers.find(gfxOffset);
    if (iter == mSamplers.end())
    {
        return pNull;
    }
    return iter->second;
}

Sampler::SharedPtr ParameterBlock::getSampler(const std::string& name) const
{
    auto var = getRootVar()[name];
    return var.getSampler();
}

size_t ParameterBlock::getSize() const
{
    return mpShaderObject->getSize();
}

bool ParameterBlock::updateSpecialization() const
{
    return true;
}

bool ParameterBlock::prepareDescriptorSets(CopyContext* pCopyContext)
{
    // Insert necessary resource barriers for bound resources.
    for (auto& srv : mSRVs)
    {
        prepareResource(pCopyContext, srv.second ? srv.second->getResource().get() : nullptr, false);
    }
    for (auto& uav : mUAVs)
    {
        prepareResource(pCopyContext, uav.second ? uav.second->getResource().get() : nullptr, true);
    }
    for (auto& subObj : this->mParameterBlocks)
    {
        subObj.second->prepareDescriptorSets(pCopyContext);
    }
    return true;
}

const ParameterBlock::SharedPtr& ParameterBlock::getParameterBlock(uint32_t resourceRangeIndex, uint32_t arrayIndex) const
{
    static const ParameterBlock::SharedPtr pNull;

    gfx::ShaderOffset gfxOffset = {};
    gfxOffset.bindingRangeIndex = resourceRangeIndex;
    gfxOffset.bindingArrayIndex = arrayIndex;
    auto iter = mParameterBlocks.find(gfxOffset);
    if (iter == mParameterBlocks.end())
    {
        return pNull;
    }
    return iter->second;
}

void ParameterBlock::collectSpecializationArgs(SpecializationArgs& ioArgs) const {}

void ParameterBlock::markUniformDataDirty() const
{
    throw "unimplemented";
}

void const* ParameterBlock::getRawData() const
{
    return mpShaderObject->getRawData();
}

const Buffer::SharedPtr& ParameterBlock::getUnderlyingConstantBuffer() const
{
    throw "unimplemented";
}

#if FALCOR_HAS_CUDA
void* ParameterBlock::getCUDAHostBuffer(size_t& outSize)
{
    return nullptr;
}

void* ParameterBlock::getCUDADeviceBuffer(size_t& outSize)
{
    return nullptr;
}
#endif
} // namespace Falcor
