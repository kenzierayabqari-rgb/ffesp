#pragma once
#include <cstddef>
#include <cstring>
#include <cstdlib>

template <int N>
struct ObfString {
    char data[N];
    constexpr ObfString(const char (&s)[N]) : data{} {
        for (int i = 0; i < N; i++)
            data[i] = s[i] ^ 0x5A;
    }
    const char* get() const {
        char* tmp = (char*)malloc(N);
        for (int i = 0; i < N; i++)
            tmp[i] = data[i] ^ 0x5A;
        return tmp;
    }
};

#define OBFUSCATE(s) (ObfString<sizeof(s)>(s).get())
