#!/bin/sh

# $1 -> Project directory
# $2 -> Binary output directory
# $3 -> Build configuration
# $4 -> Slang build configuration
# $5 -> DLSS directory

ExtDir=$1/external/packman/
OutDir=$2

IsDebug=false
if [ "$3" = "Debug" ]; then
    IsDebug=true
fi
SlangDir=$4

# Copy externals
if [ "${IsDebug}" = false ]; then
    cp -frp ${ExtDir}/deps/lib/*.so* ${OutDir}
else
    cp -frp ${ExtDir}/deps/debug/lib/*.so* ${OutDir}
    cp -fp ${ExtDir}/deps/lib/libassimp.so* ${OutDir}
    cp -fp ${ExtDir}/deps/lib/libtbb.so* ${OutDir}
fi

cp -fp ${ExtDir}/python/lib/libpython*.so* ${OutDir}
mkdir -p ${OutDir}/pythondist
cp -frp ${ExtDir}/python/* ${OutDir}/pythondist

# Copy slang
cp -f ${ExtDir}/slang/bin/linux-x64/${SlangDir}/lib*.so ${OutDir}

# Copy RTXDI SDK shaders
RtxdiSDKDir=${ExtDir}/rtxdi/rtxdi-sdk/include/rtxdi
RtxdiSDKTargetDir=${OutDir}/shaders/rtxdi
if [ -d ${RtxdiSDKDir} ]; then
    mkdir -p ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/ResamplingFunctions.hlsli ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/Reservoir.hlsli ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/RtxdiHelpers.hlsli ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/RtxdiMath.hlsli ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/RtxdiParameters.h ${RtxdiSDKTargetDir}
    cp ${RtxdiSDKDir}/RtxdiTypes.h ${RtxdiSDKTargetDir}
fi

# Copy NanoVDB
NanoVDBDir=${ExtDir}/nanovdb
NanoVDBTargetDir=${OutDir}/shaders/nanovdb
if [ -d ${NanoVDBDir} ]; then
    mkdir -p ${NanoVDBTargetDir}
    cp ${NanoVDBDir}/include/nanovdb/PNanoVDB.h ${NanoVDBTargetDir}
fi

# Copy NVTT
cp ${ExtDir}/nvtt/libcudart.so.11.0 ${OutDir}
cp ${ExtDir}/nvtt/libnvtt.so ${OutDir}
