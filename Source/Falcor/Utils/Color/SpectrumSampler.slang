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

import Utils.HWSS;
import Utils.Color.SpectrumUtils;

struct SpectrumSampler
{
    static const float minWavelength = SpectrumUtils.minWavelength;
    static const float maxWavelength = SpectrumUtils.maxWavelength;

    // Samples a single wavelengths, in uniform
    static float sampleOne(const float rndSeed) {
        const float spanWavelength = maxWavelength - minWavelength;
        return minWavelength + rndSeed*spanWavelength;
    }

    // Given a hero wavelength, fill the rest
    static hwss_t hwssWavelengths(const float hero) {
        const float spanWavelength = maxWavelength - minWavelength;

        hwss_t hwss = .0f;
        for (int i = 0; i < hwss_samples; ++i)
            hwss[i] = float(i);
        hwss = hwss_t(hero) + hwss * (spanWavelength / float(hwss_samples));
        hwss -= hwss > hwss_t(maxWavelength) ? hwss_t(spanWavelength) : hwss_t(.0f);

        return hwss;
    }
};
