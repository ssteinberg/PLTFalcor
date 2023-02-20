#pragma once

#include <vector>
#include <filesystem>

namespace Falcor
{
    namespace Mitsuba
    {
        class Resolver {
        public:
            using iterator = std::vector<std::filesystem::path>::iterator;
            using const_iterator = std::vector<std::filesystem::path>::const_iterator;

            size_t size() const { return mPaths.size(); }

            iterator begin() { return mPaths.begin(); }
            iterator end() { return mPaths.end(); }

            const_iterator begin() const { return mPaths.begin(); }
            const_iterator end() const { return mPaths.end(); }

            void erase(iterator it) { mPaths.erase(it); }

            void prepend(const std::filesystem::path& path) { mPaths.insert(mPaths.begin(), path); }
            void append(const std::filesystem::path& path) { mPaths.push_back(path); }
            const std::filesystem::path& operator[](size_t index) const { return mPaths[index]; }
            std::filesystem::path& operator[](size_t index) { return mPaths[index]; }

            std::filesystem::path resolve(const std::filesystem::path& path) const {
                for (const_iterator it = mPaths.begin(); it != mPaths.end(); ++it) {
                    std::filesystem::path combined = *it / path;
                    if (std::filesystem::exists(combined))
                    {
                        return combined;
                    }
                }
                return path;
            }

        private:
            std::vector<std::filesystem::path> mPaths;
        };

    }
}
