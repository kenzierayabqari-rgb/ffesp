#include "il2cpp.h"
#include <dlfcn.h>
#include <os/log.h>

Il2CppApi api = {};

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
    BIND(runtime_invoke);
    BIND(class_get_type);
    BIND(type_get_object);
    BIND(array_length);
    BIND(array_get);
    BIND(domain_get_assemblies);
    #undef BIND

    if (!api.domain_get || !api.class_from_name) return false;
    api.thread_attach(api.domain_get());
    return true;
}

void* Il2CppFindClass(const char* ns, const char* name) {
    if (!api.domain_get_assemblies) return nullptr;

    size_t count = 0;
    void** assemblies = (void**)api.domain_get_assemblies(api.domain_get(), &count);
    if (!assemblies || count == 0) return nullptr;

    os_log(OS_LOG_DEFAULT, "[FFESP] assemblies: %zu", count);

    for (size_t i = 0; i < count; i++) {
        if (!assemblies[i]) continue;
        void* img = api.assembly_get_image(assemblies[i]);
        if (!img) continue;
        void* cls = api.class_from_name(img, ns, name);
        if (cls) {
            os_log(OS_LOG_DEFAULT, "[FFESP] found in #%zu", i);
            return cls;
        }
    }
    return nullptr;
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
