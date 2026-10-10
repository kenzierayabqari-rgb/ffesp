// ---------- DEBUG STATE (tampil di layar) ----------
static char g_debugClass[64] = "scanning...";
static int  g_debugFound = 0;

static void* g_findMethod   = nullptr;
static void* g_playerCls    = nullptr;
static void* g_getTransform = nullptr;
static void* g_getPosition  = nullptr;

static bool InitScan() {
    // Kandidat nama kelas — makin banyak makin baik
    const char* candidates[] = {
        "Player", "PlayerAvatar", "Avatar", "AvatarEntity",
        "PlayerEntity", "Character", "CharacterEntity",
        "FFPlayer", "PlayerController", "LocalPlayer",
        "PlayerManager", "GamePlayer", "HumanPlayer",
        nullptr
    };

    for (int i = 0; candidates[i]; i++) {
        void* k = Il2CppFindClass("", candidates[i]);
        if (k) {
            g_playerCls = k;
            snprintf(g_debugClass, sizeof(g_debugClass), "OK: %s", candidates[i]);
            os_log(OS_LOG_DEFAULT, "[FFESP] Player class FOUND: %{public}s",
                   candidates[i]);
            break;
        }
    }

    if (!g_playerCls) {
        snprintf(g_debugClass, sizeof(g_debugClass), "NO CLASS");
        os_log(OS_LOG_DEFAULT, "[FFESP] Player class not found in list");
        return false;
    }

    // Cari method FindObjectsOfType di UnityEngine.Object
    void* objCls = Il2CppFindClass("UnityEngine", "Object");
    if (objCls) {
        g_findMethod = Il2CppFindMethod(objCls, "FindObjectsOfType", 1);
    }

    // Cari method transform di Player
    void* transformCls = Il2CppFindClass("UnityEngine", "Transform");
    if (transformCls) {
        g_getPosition = Il2CppFindMethod(transformCls, "get_position", 0);
    }
    g_getTransform = Il2CppFindMethod(g_playerCls, "get_transform", 0);

    os_log(OS_LOG_DEFAULT,
           "[FFESP] find=%p transform=%p pos=%p",
           g_findMethod, g_getTransform, g_getPosition);

    return g_findMethod && g_getTransform && g_getPosition;
}

static Vec3 InvokeGetPosition(void* instance) {
    Vec3 out = {0,0,0};
    if (!g_getPosition || !instance) return out;

    uint8_t buf[32] = {0};
    void* args[] = { buf };
    void* exc = nullptr;
    api.runtime_invoke(g_getPosition, instance, args, &exc);
    if (exc) return out;

    out.x = *(float*)(buf);
    out.y = *(float*)(buf + 4);
    out.z = *(float*)(buf + 8);
    return out;
}

static void ScanPlayers() {
    g_players.clear();
    g_debugFound = 0;

    if (!g_findMethod || !g_playerCls) return;
    if (!api.class_get_type || !api.type_get_object) return;

    // Kelas -> Il2CppType* -> System.Type (Il2CppObject*)
    void* type = api.class_get_type(g_playerCls);
    if (!type) return;
    void* typeObj = api.type_get_object(type);
    if (!typeObj) return;

    // FindObjectsOfType(type)
    void* args[] = { typeObj };
    void* exc = nullptr;
    void* result = api.runtime_invoke(g_findMethod, nullptr, args, &exc);
    if (exc || !result) return;

    int len = api.array_length ? api.array_length(result) : 0;
    if (len <= 0 || len > 256) {
        g_debugFound = len;
        return;
    }

    for (int i = 0; i < len; i++) {
        void* player = api.array_get ? api.array_get(result, i) : nullptr;
        if (!player) continue;

        uint8_t tbuf[16] = {0};
        void* targs[] = { tbuf };
        void* texc = nullptr;
        api.runtime_invoke(g_getTransform, player, targs, &texc);
        if (texc) continue;
        void* transform = *(void**)tbuf;
        if (!transform) continue;

        Vec3 pos = InvokeGetPosition(transform);
        if (pos.x == 0 && pos.y == 0 && pos.z == 0) continue;
        g_players.push_back(pos);
    }
    g_debugFound = (int)g_players.size();
}
