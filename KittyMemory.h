#pragma once
#include <cstdint>
#include <cstddef>
#include <string>

namespace KittyMemory {
    bool memWrite(void* addr, const void* data, size_t len);
    bool memRead(void* addr, void* out, size_t len);
    bool memPatch(void* addr, const void* data, size_t len);
    uintptr_t getBase(const std::string& module);
}
