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

import Utils.Color.ColorHelpers;
import Utils.HWSS;

/** Utilities for converting tristimulus values to/from spectral data.
*/
struct SpectrumUtils
{
    /** Evaluates the 1931 CIE XYZ color matching curves.
        This uses a multi-lobe piecewise Gaussian fit described in:
        Wyman et al., "Simple Analytic Approximations to the CIE XYZ Color
        Matching Functions", JCGT, vol 2(2), 2013.
        \param[in] lambda Wavelength in nm.
        \return XYZ tristimulus values.
    */
    static float3 wavelengthToXYZ(float lambda)
    {
        float x = 0.362f * G(lambda, 442.0f, 0.0624f, 0.0374f) + 1.056f * G(lambda, 599.8f, 0.0264f, 0.0323f) - 0.065f * G(lambda, 501.1f, 0.0490f, 0.0382f);
        float y = 0.821f * G(lambda, 568.8f, 0.0213f, 0.0247f) + 0.286f * G(lambda, 530.9f, 0.0613f, 0.0322f);
        float z = 1.217f * G(lambda, 437.0f, 0.0845f, 0.0278f) + 0.681f * G(lambda, 459.0f, 0.0385f, 0.0725f);
        return float3(x, y, z);
    }


    static const float3 rgbWavelengths = float3(630,532,467);
    static const float meanWavelength = 550.f;

    // Internal
    static const float minWavelength = 380.0f;
    static const float maxWavelength = 720.0f;

    static float G(float x, float lambda, float invSigma1, float invSigma2)
    {
        float t = (x - lambda) * (x < lambda ? invSigma1 : invSigma2);
        return exp(-0.5f * t * t);
    }

    static float wavelengthToD65(float lambda)
    {
        const float D65_5nm[69] = { 49.9755, 52.3118, 54.6482, 68.7015, 82.7549, 87.1204, 91.486, 92.4589, 93.4318, 90.057, 86.6823, 95.7736, 104.865, 110.936,
            117.008, 117.41, 117.812, 116.336, 114.861, 115.392, 115.923, 112.367, 108.811, 109.082, 109.354, 108.578, 107.802, 106.296,
            104.79, 106.239, 107.689, 106.047, 104.405, 104.225, 104.046, 102.023, 100., 98.1671, 96.3342, 96.0611, 95.788, 92.2368, 88.6856,
            89.3459, 90.0062, 89.8026, 89.5991, 88.6489, 87.6987, 85.4936, 83.2886, 83.4939, 83.6992, 81.863, 80.0268, 80.1207, 80.2146,
            81.2462, 82.2778, 80.281, 78.2842, 74.0027, 69.7213, 70.6652, 71.6091, 72.979, 74.349, 67.9765, 61.604 };

        const float wavelengthResize = (lambda - minWavelength) * 0.2f;
        const int wavelength_t = int(ceil(wavelengthResize)+.5f);
        const int wavelength_b = int(floor(wavelengthResize)+.5f);
        const float weight = wavelengthResize - wavelength_b;
        return D65_5nm[wavelength_t] * weight + D65_5nm[wavelength_b] * (1.0f - weight);
    }

    static float luminance(hwss_t spectrum, hwss_t wavelengths)
    {
        float lum = .0f;
        for (int i = 0; i < hwss_samples; i++)
        {
            float3 xyz = wavelengthToXYZ(wavelengths[i]) * wavelengthToD65(wavelengths[i]) * spectrum[i];
            lum += xyz.y;
        }

        return lum;
    }

    static float3 spectrumToRgb(hwss_t spectrum, hwss_t wavelengths, uint samples = hwss_samples)
    {
        float3 result = .0f;
        for (int i = 0; i < samples; i++)
        {
            float3 xyz = wavelengthToXYZ(wavelengths[i]) * wavelengthToD65(wavelengths[i])
            * spectrum[i];
            result += XYZtoRGB_Rec709(xyz);
        }

        const float Y_D65 = 10.5670762f;
        return result / Y_D65;
    }

    static float rgbToSpectrum(float3 rgb, float wavelength)
    {
        const float white_sd[11] = { 1.0000, 1.0000, 0.9999, 0.9993, 0.9992, 0.9998, 1.0000, 1.0000, 1.0000, 1.0000, 0.0 };
        const float cyan_sd[11] = { 0.9710, 0.9426, 1.0007, 1.0007, 1.0007, 1.0007, 0.1564, 0.0000, 0.0000, 0.0000, 0.0 };
        const float magenta_sd[11] = { 1.0000, 1.0000, 0.968,  0.22295, 0.0000, 0.0458, 0.8369, 1.0000, 1.0000, 0.9959, 0.0 };
        const float yellow_sd[11] = { 0.0001, 0.0000, 0.1088, 0.6651, 1.0000, 1.0000, 0.9996, 0.9586, 0.9685, 0.9840, 0.0 };
        const float red_sd[11] = { 0.1012, 0.0515, 0.0000, 0.0000, 0.0000, 0.0000, 0.8325, 1.0149, 1.0149, 1.014, 0.0  };
        const float green_sd[11] = { 0.0000, 0.0000, 0.0273, 0.7937, 1.0000, 0.9418, 0.1719, 0.0000, 0.0000, 0.0025, 0.0 };
        const float blue_sd[11] = { 1.0000, 1.0000, 0.8916, 0.3323, 0.0000, 0.0000, 0.0003, 0.0369, 0.0483, 0.0496, 0.0 };

        float sd = .0f;

        const int b = (int)(clamp((wavelength - minWavelength) / (maxWavelength - minWavelength),.0f,1.f) * 10.f);
        const float white_s   = white_sd[b];
        const float cyan_s    = cyan_sd[b];
        const float magenta_s = magenta_sd[b];
        const float yellow_s  = yellow_sd[b];
        const float red_s     = red_sd[b];
        const float green_s   = green_sd[b];
        const float blue_s    = blue_sd[b];

        if (rgb.r <= rgb.g && rgb.r <= rgb.b)
        {
            sd += white_s * rgb.r;
            if (rgb.g <= rgb.b)
            {
                sd += cyan_s * (rgb.g - rgb.r);
                sd += blue_s * (rgb.b - rgb.g);
            }
            else
            {
                sd += cyan_s * (rgb.b - rgb.r);
                sd += green_s * (rgb.g - rgb.b);
            }
        }
        else if (rgb.g <= rgb.r && rgb.g <= rgb.b)
        {
            sd += white_s * rgb.g;
            if (rgb.r <= rgb.b)
            {
                sd += magenta_s * (rgb.r - rgb.g);
                sd += blue_s * (rgb.b - rgb.r);
            }
            else
            {
                sd += magenta_s * (rgb.b - rgb.g);
                sd += red_s * (rgb.r - rgb.b);
            }
        }
        else
        {
            sd += white_s * rgb.b;
            if (rgb.r <= rgb.g)
            {
                sd += yellow_s * (rgb.r - rgb.b);
                sd += green_s * (rgb.g - rgb.r);
            }
            else
            {
                sd += yellow_s * (rgb.g - rgb.b);
                sd += red_s * (rgb.r - rgb.g);
            }
        }
        return sd;
    }
    static hwss_t rgbToSpectrum(float3 rgb, hwss_t wavelengths)
    {
        const float white_sd[11] = { 1.0000, 1.0000, 0.9999, 0.9993, 0.9992, 0.9998, 1.0000, 1.0000, 1.0000, 1.0000, 0.0 };
        const float cyan_sd[11] = { 0.9710, 0.9426, 1.0007, 1.0007, 1.0007, 1.0007, 0.1564, 0.0000, 0.0000, 0.0000, 0.0 };
        const float magenta_sd[11] = { 1.0000, 1.0000, 0.968,  0.22295, 0.0000, 0.0458, 0.8369, 1.0000, 1.0000, 0.9959, 0.0 };
        const float yellow_sd[11] = { 0.0001, 0.0000, 0.1088, 0.6651, 1.0000, 1.0000, 0.9996, 0.9586, 0.9685, 0.9840, 0.0 };
        const float red_sd[11] = { 0.1012, 0.0515, 0.0000, 0.0000, 0.0000, 0.0000, 0.8325, 1.0149, 1.0149, 1.014, 0.0  };
        const float green_sd[11] = { 0.0000, 0.0000, 0.0273, 0.7937, 1.0000, 0.9418, 0.1719, 0.0000, 0.0000, 0.0025, 0.0 };
        const float blue_sd[11] = { 1.0000, 1.0000, 0.8916, 0.3323, 0.0000, 0.0000, 0.0003, 0.0369, 0.0483, 0.0496, 0.0 };

        hwss_t sd = hwss_t(0.0f);

        hwss_t white_s, cyan_s, magenta_s, yellow_s, red_s, green_s, blue_s;
        for (int i = 0; i < hwss_samples; ++i)
        {
            const int b = (int)(clamp((wavelengths[i] - minWavelength) / (maxWavelength - minWavelength),.0f,1.f) * 10.f);
            white_s[i]   = white_sd[b];
            cyan_s[i]    = cyan_sd[b];
            magenta_s[i] = magenta_sd[b];
            yellow_s[i]  = yellow_sd[b];
            red_s[i]     = red_sd[b];
            green_s[i]   = green_sd[b];
            blue_s[i]    = blue_sd[b];
        }

        if (rgb.r <= rgb.g && rgb.r <= rgb.b)
        {
            sd += white_s * rgb.r;
            if (rgb.g <= rgb.b)
            {
                sd += cyan_s * (rgb.g - rgb.r);
                sd += blue_s * (rgb.b - rgb.g);
            }
            else
            {
                sd += cyan_s * (rgb.b - rgb.r);
                sd += green_s * (rgb.g - rgb.b);
            }
        }
        else if (rgb.g <= rgb.r && rgb.g <= rgb.b)
        {
            sd += white_s * rgb.g;
            if (rgb.r <= rgb.b)
            {
                sd += magenta_s * (rgb.r - rgb.g);
                sd += blue_s * (rgb.b - rgb.r);
            }
            else
            {
                sd += magenta_s * (rgb.b - rgb.g);
                sd += red_s * (rgb.r - rgb.b);
            }
        }
        else
        {
            sd += white_s * rgb.b;
            if (rgb.r <= rgb.g)
            {
                sd += yellow_s * (rgb.r - rgb.b);
                sd += green_s * (rgb.g - rgb.r);
            }
            else
            {
                sd += yellow_s * (rgb.g - rgb.b);
                sd += red_s * (rgb.r - rgb.g);
            }
        }
        return sd;
    }
};
