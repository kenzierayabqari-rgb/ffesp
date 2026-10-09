#pragma once
#include <cstdint>
#include <cstddef>

struct Il2CppApi {
    void*  (*domain_get)();
    void*  (*domain_assembly_open)(void*, const char*);
    void*  (*assembly_get_image)(void*);
    void*  (*class_from_name)(void*, const char*, const char*);
    void*  (*class_get_method_from_name)(void*, const char*, int);
    void*  (*class_get_field_from_name)(void*, const char*);
    size_t (*field_get_offset)(void*);
    void*  (*thread_attach)(void*);
    void*  (*object_new)(void*);
    void*  (*runtime_invoke)(void*, void*, void**, void**);
    void*  (*string_new)(const char*);
    char*  (*string_to_utf8)(void*);
};

extern Il2CppApi api;

bool  Il2CppInit();
void* Il2CppImage();
void* Il2CppFindClass(const char* ns, const char* name);
void* Il2CppFindMethod(void* klass, const char* method, int argc);
size_t Il2CppFieldOffset(void* klass, const char* field);
