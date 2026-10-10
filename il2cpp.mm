#include "il2cpp.h"
#include <dlfcn.h>
#include <os/log.h>

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
    BIND(array_length);
    BIND(array_get);
    BIND(object_get_class);
    #undef BIND

    if (!api.domain_get || !api.class_from_name) return false;
    api.thread_attach(api.domain_get());
    return true;
}

void* Il2CppImage() {
    if (g_image) return g_image;
    auto domain = api.domain_get();
    const char* names[] = { "Assembly-CSharp.dll", "Assembly-CSharp", nullptr };
    for (int i = 0; names[i]; i++) {
        void* asm_ = api.domain_assembly_open(domain, names[i]);
        if (!asm_) continue;
        g_image = api.assembly_get_image(asm_);
        if (g_image) return g_image;
    }
    return nullptr;
}

void* Il2CppFindClass(const char* ns, const char* name) {
    void* img = Il2CppImage();
    if (!img) return nullptr;
    return api.class_from_name(img, ns, name);
}

void* Il2CppFindMethod(void* klass, const char* method, int argc) {
    if (!klass) return nullptr;
    return api.class_get_method_from_name(klass, method, argc);
}

size_t Il2CppFieldOffset(void* klass, const char* field) {
    if (!klass) return 0;
    void* f = api.class_get_field_from_name(klass, field);
    if (!f) return 0;
    return api.field_get_offset(f);
}
