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
#pragma once
#include "Types.h"
#include "Core/Errors.h"
#include "Utils/Logger.h"
#include <fmt/format.h>
#include <string_view>

namespace Falcor::pbrt
{

template<typename... Args>
[[noreturn]] inline void throwError(fmt::format_string<Args...> format, Args&&... args)
{
    throw RuntimeError(format, std::forward<Args>(args)...);
}

template<typename... Args>
[[noreturn]] inline void throwError(const FileLoc& loc, fmt::format_string<Args...> format, Args&&... args)
{
    auto msg = fmt::format(format, std::forward<Args>(args)...);
    throw RuntimeError("{}: {}", loc.toString(), msg);
}

template<typename... Args>
inline void logWarning(const FileLoc& loc, fmt::format_string<Args...> format, Args&&... args)
{
    auto msg = fmt::format(format, std::forward<Args>(args)...);
    Falcor::logWarning("{}: {}", loc.toString(), msg);
}

} // namespace Falcor::pbrt
