#pragma once

#include "Falcor.h"
#include <limits>

namespace Falcor
{
    namespace Mitsuba
    {
        // IOR and Abbe number for various dielectrics.
        // Abbe number of infinity means no dispersion, "??" marks compounds with unclear or dubious values.
        // For gases dispersion is ignored (for performance reasons and as these gases are barely dispersive).
        std::map<std::string, std::pair<float, float>> kIORTable = {
            { "vacuum",                { 1.0f,        std::numeric_limits<float>::infinity() } },
            { "helium",                { 1.000036f,   std::numeric_limits<float>::infinity() } },
            { "hydrogen",              { 1.000132f,   std::numeric_limits<float>::infinity() } },
            { "air",                   { 1.000277f,   std::numeric_limits<float>::infinity() } },
            { "carbon dioxide",        { 1.00045f,    std::numeric_limits<float>::infinity() } }, // ??

            { "water",                 { 1.3330f,     55.f } },
            { "acetone",               { 1.36f,       54.f } },
            { "ethanol",               { 1.361f,      59.f } },
            { "carbon tetrachloride",  { 1.461f,      49.f } },
            { "glycerol",              { 1.4729f,     std::numeric_limits<float>::infinity() } },
            { "benzene",               { 1.501f,      30.3f } },
            { "silicone oil",          { 1.52045f,    std::numeric_limits<float>::infinity() } }, // ??
            { "bromine",               { 1.661f,      31.7f } }, // Abbe number for KBr

            { "water ice",             { 1.31f,       64.f } },
            { "fused quartz",          { 1.458f,      67.8f } },
            { "pyrex",                 { 1.470f,      60.f } }, // ??
            { "acrylic glass",         { 1.49f,       std::numeric_limits<float>::infinity() } }, // ??
            { "polypropylene",         { 1.49f,       std::numeric_limits<float>::infinity() } }, // ??
            { "bk7",                   { 1.5046f,     64.f } },
            { "sodium chloride",       { 1.544f,      42.9f } },
            { "amber",                 { 1.55f,       std::numeric_limits<float>::infinity() } }, // ??
            { "pet",                   { 1.5750f,     std::numeric_limits<float>::infinity() } }, // ??
            { "diamond",               { 2.419f,      55.3f } },
        };

        std::pair<float,float> lookupIOR(std::string name)
        {
            std::transform(name.begin(), name.end(), name.begin(), ::tolower);

            auto it = kIORTable.find(name);
            if (it != kIORTable.end()) return it->second;

            std::string list;
            for (const auto& [key, value] : kIORTable)
                list += key + "\n";
            logWarning("'{}' is not a valid IOR name. Valid choises are:\n{}", name, list);

            return kIORTable["air"];
        }
    }
}
