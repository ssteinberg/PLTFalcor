#pragma once

#include "Falcor.h"

#include <fstream>

namespace Falcor
{
    namespace Mitsuba
    {
        class Hair
        {
        public:
            using SharedPtr = std::shared_ptr<Hair>;

            static SharedPtr createFromFile(const std::string& filename, float radius)
            {
                auto pHair = SharedPtr(new Hair());
                return pHair->loadFromFile(filename, radius) ? pHair : nullptr;
            }

            const std::vector<float3>& getVertices() const { return mVertices; }
            const std::vector<float>& getRadii() const { return mRadii; }
            const std::vector<float2>& getTexCoords() const { return mTexCoords; }
            const std::vector<uint32_t>& getIndices() const { return mIndices; }

        private:
            Hair() = default;

            bool loadFromFile(const std::string& filename, float radius)
            {
                std::ifstream ifs(filename, std::ios::in | std::ios::binary);

                if (ifs.fail())
                {
                    logWarning("Failed to open hair file '{}'.", filename);
                    return false;
                }

                const char *binaryHeader = "BINARY_HAIR";
                char header[11];
                ifs.read(header, 11);
                bool isBinaryFormat = memcmp(header, binaryHeader, 11) == 0;

                if (isBinaryFormat)
                {
                    uint32_t vertexCount;
                    ifs.read(reinterpret_cast<char*>(&vertexCount), sizeof(uint32_t));

                    mVertices.reserve(vertexCount);
                    mRadii.resize(vertexCount, radius);
                    mTexCoords.resize(vertexCount, float2(0.f));

                    uint32_t prevIndex = 0;

                    while (mVertices.size() < vertexCount)
                    {
                        // Read vertex.
                        bool skipVertex = false;
                        float3 vertex;
                        ifs.read(reinterpret_cast<char*>(&vertex), sizeof(float3));
                        if (std::isinf(vertex.x))
                        {
                            vertex.xy = vertex.yz;
                            ifs.read(reinterpret_cast<char*>(&vertex.z), sizeof(float));
                            skipVertex = true;
                        }

                        uint32_t curIndex = (uint32_t)mVertices.size();
                        mVertices.push_back(vertex);

                        if (!skipVertex && curIndex != prevIndex)
                        {
                            mIndices.push_back(prevIndex);
                        }

                        prevIndex = curIndex;

                        if (!ifs.good())
                        {
                            logWarning("Failed to load binary hair data from '{}'.", filename);
                            return false;
                        }
                    }
                }
                else
                {
                    // TODO text format
                }

                return true;
            }

            std::vector<float3> mVertices;
            std::vector<float> mRadii;
            std::vector<float2> mTexCoords;
            std::vector<uint32_t> mIndices;
        };


    }
}
