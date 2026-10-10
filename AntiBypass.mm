#import <Foundation/Foundation.h>
#import <os/log.h>
#include "AntiBypass.h"
#include "KittyMemory.h"
#include "Obfuscate.h"
#include <mach/mach.h>
#include <cstring>
#include <dlfcn.h>

// ARM64 snippets
static const uint8_t RET_TRUE[]  = { 0x20, 0x00, 0x80, 0x52, 0xC0, 0x03, 0x5F, 0xD6 };
static const uint8_t RET_FALSE[] = { 0x00, 0x00, 0x80, 0x52, 0xC0, 0x03, 0x5F, 0xD6 };
static const uint8_t RET_VOID[]  = { 0xC0, 0x03, 0x5F, 0xD6 };

namespace AntiBypass {

static bool g_active = false;
bool IsActive() { return g_active; }

// Scan region executable UnityFramework untuk signature anti-cheat
// Ini versi kerangka — offset konkret didapat dari dump il2cpp.
static uintptr_t FindACEExport(const char* name) {
    uintptr_t base = KittyMemory::getBase("UnityFramework");
    if (!base) return 0;
    void* h = dlopen("@rpath/UnityFramework.framework/UnityFramework",
                     RTLD_NOW | RTLD_GLOBAL);
    if (!h) h = RTLD_DEFAULT;
    void* p = dlsym(h, name);
    return (uintptr_t)p;
}

void Install() {
    os_log(OS_LOG_DEFAULT, "[AntiBypass] install start");

    struct Target {
        const char* sym;
        const uint8_t* patch;
        size_t len;
    };

    // Simbol umum anti-cheat di UnityFramework
    Target targets[] = {
        { "ACE_Report",     RET_VOID,  sizeof(RET_VOID)  },
        { "ACE_Check",      RET_TRUE,  sizeof(RET_TRUE)  },
        { "CheckMemory",    RET_TRUE,  sizeof(RET_TRUE)  },
        { "VerifyFileHash", RET_TRUE,  sizeof(RET_TRUE)  },
        { "DetectHook",     RET_FALSE, sizeof(RET_FALSE) },
        { nullptr, nullptr, 0 }
    };

    int patched = 0;
    for (int i = 0; targets[i].sym; i++) {
        uintptr_t a = FindACEExport(targets[i].sym);
        if (!a) continue;
        if (KittyMemory::memPatch((void*)a, targets[i].patch, targets[i].len)) {
            os_log(OS_LOG_DEFAULT, "[AntiBypass] patched %{public}s @ %p",
                   targets[i].sym, (void*)a);
            patched++;
        }
    }

    g_active = (patched > 0);
    os_log(OS_LOG_DEFAULT, "[AntiBypass] done — %d patched", patched);
}

} // namespace AntiBypass
