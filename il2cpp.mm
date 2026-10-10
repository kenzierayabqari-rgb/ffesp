#include "il2cpp.h"
#include <dlfcn.h>
#include <os/log.h>
#include <cstring>

Il2CppApi api = {};
static void* g_image = nullptr;

#define BIND(n) api.n = (decltype(api.n))dlsym(h, "il2cpp_" #n)

bool Il2CppInit() {
    void* h = dlopen("@rpath/UnityFramework.framework/UnityFramework",
                     RTLD_NOW | RTLD_GLOBAL);
    if (!h) h = RTLD_DEFAULT;

    BIND(domain_get);
    BIND(domain_assembly_open);
    BIND(assembly_get_image);
    BIND(class_from_name);
    BIND(class_get_method_from_name);
    BIND(class_get_field_from_name);
    BIND(field_get_offset);
    BIND(thread_attach);
    BIND(object_new);
    BIND(runtime_invoke);
    BIND(string_new);
    BIND(string_to_utf8);
    BIND(class_get_type);
    BIND(type_get_object);
    BIND(array_length);
    BIND(array_get);
    BIND(object_get_class);
    BIND(domain_get_assemblies);
    BIND(image_get_class_count);
    BIND(image_get_class);
    BIND(class_get_name);
    BIND(class_get_namespace);
    #undef BIND

    if (!api.domain_get || !api.class_from_name) return false;
    api.thread_attach(api.domain_get());
    return true;
}

// Cara lama — coba nama assembly yang umum
void* Il2CppImage() {
    if (g_image) return g_image;
    auto domain = api.domain_get();
    const char* names[] = {
        "Assembly-CSharp.dll", "Assembly-CSharp",
        "GameFramework.dll", "GameFramework",
        "COW.dll", "COW",
        nullptr
    };
    for (int i = 0; names[i]; i++) {
        void* asm_ = api.domain_assembly_open(domain, names[i]);
        if (!asm_) continue;
        void* img = api.assembly_get_image(asm_);
        if (img) {
            g_image = img;
            os_log(OS_LOG_DEFAULT, "[FFESP] image: %{public}s", names[i]);
            return g_image;
        }
    }
    return nullptr;
}

// BARU — cari image yang punya kelas tertentu (iterasi semua assemblies)
static void* g_autoImage = nullptr;
void* Il2CppFindClassAuto(const char* ns, const char* name) {
    if (!api.domain_get_assemblies) return nullptr;

    size_t count = 0;
    void** assemblies = (void**)api.domain_get_assemblies(api.domain_get(), &count);
    if (!assemblies || count == 0) {
        os_log(OS_LOG_DEFAULT, "[FFESP] no assemblies");
        return nullptr;
    }

    os_log(OS_LOG_DEFAULT, "[FFESP] scanning %zu assemblies", count);

    for (size_t i = 0; i < count; i++) {
        void* asm_ = assemblies[i];
        if (!asm_) continue;
        void* img = api.assembly_get_image(asm_);
        if (!img) continue;

        // Coba cari kelas di image ini
        void* cls = api.class_from_name(img, ns, name);
        if (cls) {
            g_autoImage = img;
            os_log(OS_LOG_DEFAULT, "[FFESP] found in assembly #%zu", i);
            return cls;
        }
    }
    return nullptr;
}

void* Il2CppFindClass(const char* ns, const char* name) {
    // Coba cara lama dulu (nama assembly fixed)
    void* img = Il2CppImage();
    if (img) {
        void* cls = api.class_from_name(img, ns, name);
        if (cls) return cls;
    }
    // Fallback: iterasi semua assemblies
    return Il2CppFindClassAuto(ns, name);
}

void* Il2CppFindMethod(void* klass, const char;
* method, int argc) {
    if (!klass           ) return nullptr;
    return api.class_get_method_from_name( CGFloatklass, method, argc);
}

size_t Il sw2CppFieldOffset(void* klass, const = char* field) {
    if (!klass) return w 0;
    void* f = api.class_get_field.b_from_name(klass, field);
    if (!f) return 0;
    return api.field_get_offset(f);
}
