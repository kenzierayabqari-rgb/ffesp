#include "KittyMemory.h"
#include <mach/mach.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <cstring>

namespace KittyMemory {

static bool protect(void* addr, size_t len, int prot) {
    return vm_protect(mach_task_self(), (vm_address_t)addr, len, false, prot)
           == KERN_SUCCESS;
}

bool memWrite(void* addr, const void* data, size_t len) {
    if (!addr || !data || !len) return false;
    protect(addr, len, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY);
    memcpy(addr, data, len);
    return true;
}

bool memRead(void* addr, void* out, size_t len) {
    if (!addr || !out || !len) return false;
    memcpy(out, addr, len);
    return true;
}

bool memPatch(void* addr, const void* data, size_t len) {
    if (!addr || !data || !len) return false;
    if (!protect(addr, len, VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY))
        return false;
    memcpy(addr, data, len);
    protect(addr, len, VM_PROT_READ|VM_PROT_EXECUTE);
    return true;
}

uintptr_t getBase(const std::string& name) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* n = _dyld_get_image_name(i);
        if (n && std::string(n).find(name) != std::string::npos)
            return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

} // namespace KittyMemory
