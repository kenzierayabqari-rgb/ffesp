#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>
#include "ESP.h"
#include "il2cpp.h"
#include "offsets.h"
#include <thread>
#include <chrono>
#include <cmath>
#include <vector>
#include <cstdio>
#include <cstring>

static volatile bool g_esp   = false;
static volatile bool g_line  = true;
static volatile bool g_name  = true;
static volatile bool g_aim   = false;

static CAShapeLayer* g_overlay = nil;

struct Vec3 { float x, y, z; };
static std::vector<Vec3> g_players;
static Vec3 g_local = {0,0,0};

// ============================================================
// OVERLAY
// ============================================================
static UIWindow* gameWindow() {
    for (UIWindow* w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
    for (UIWindow* w in [UIApplication sharedApplication].windows)
        if (!w.hidden && w.windowLevel == UIWindowLevelNormal) return w;
    return nil;
}

static void EnsureOverlay() {
    if (g_overlay && g_overlay.superlayer) return;
    UIWindow* w = gameWindow();
    if (!w) return;
    g_overlay = [CAShapeLayer layer];
    g_overlay.frame = w.bounds;
    g_overlay.backgroundColor = [UIColor clearColor].CGColor;
    g_overlay.zPosition = 99998;
    [w.layer addSublayer:g_overlay];
}

static void ClearOverlay() {
    if (!g_overlay) return;
    NSArray* subs = [g_overlay.sublayers copy];
    for (CALayer* l in subs) [l removeFromSuperlayer];
}

static void DrawLine(CGPoint a, CGPoint b, UIColor* c, CGFloat w) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* p = [UIBezierPath bezierPath];
    [p moveToPoint:a]; [p addLineToPoint:b];
    l.path = p.CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = w;
    [g_overlay addSublayer:l];
}

static void DrawDot(CGPoint p, UIColor* c, CGFloat r) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* path = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(p.x - r, p.y - r, r*2, r*2)];
    l.path = path.CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor colorWithWhite:1 alpha:0.8].CGColor;
    l.lineWidth = 1.5;
    [g_overlay addSublayer:l];
}

static void DrawText(CGPoint pt, NSString* txt) {
    CATextLayer* t = [CATextLayer layer];
    t.string = txt;
    t.fontSize = 11;
    t.foregroundColor = [UIColor whiteColor].CGColor;
    t.alignmentMode = kCAAlignmentCenter;
    t.contentsScale = [UIScreen mainScreen].scale;
    t.frame = CGRectMake(pt.x - 80, pt.y, 160, 14);
    t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5].CGColor;
    [g_overlay addSublayer:t];
}

// ============================================================
// MATH
// ============================================================
static bool WorldToScreen(const Vec3& w, const float* m, float sw, float sh, CGPoint* out) {
    float x = m[0]*w.x + m[4]*w.y + m[8]*w.z  + m[12];
    float y = m[1]*w.x + m[5]*w.y + m[9]*w.z  + m[13];
    float z = m[2]*w.x + m[6]*w.y + m[10]*w.z + m[14];
    float ww= m[3]*w.x + m[7]*w.y + m[11]*w.z + m[15];
    if (ww < 0.01f) return false;
    out->x = (x/ww) * 0.5f * sw + sw * 0.5f;
    out->y = (-y/ww) * 0.5f * sh + sh * 0.5f;
    return true;
}

// ============================================================
// AUTO SCAN — ITERATE SEMUA KELAS DI ASSEMBLY-CSHARP
// ============================================================
static char g_debugClass[128] = "scanning...";
static int  g_debugFound = 0;

static void* g_findMethod   = nullptr;
static void* g_playerCls    = nullptr;
static void* g_getTransform = nullptr;
static void* g_getPosition  = nullptr;
static int   g_classCount   = 0;

// Cek apakah kelas punya method dengan nama tertentu
static bool classHasMethod(void* klass, const char* name) {
    if (!klass || !api.class_get_method_from_name) return false;
    void* m = api.class_get_method_from_name(klass, name, 0);
    return m != nullptr;
}

// Cek apakah kelas punya field dengan nama tertentu
static bool classHasField(void* klass, const char* name) {
    if (!klass || !api.class_get_field_from_name) return false;
    void* f = api.class_get_field_from_name(klass, name);
    return f != nullptr;
}

// Cari kelas player dengan scan semua kelas di assembly
static void* findPlayerClassByScan() {
    void* img = Il2CppImage();
    if (!img) {
        os_log(OS_LOG_DEFAULT, "[FFESP] no image");
        return nullptr;
    }
    if (!api.image_get_class_count || !api.image_get_class) {
        os_log(OS_LOG_DEFAULT, "[FFESP] no class count API");
        return nullptr;
    }

    size_t count = api.image_get_class_count ? (size_t)api.image_get_class_count(img) : 0;
    g_classCount = (int)count;
    os_log(OS_LOG_DEFAULT, "[FFESP] total classes: %zu", count);

    void* bestMatch = nullptr;
    int bestScore = 0;

    for (size_t i = 0; i < count; i++) {
        void* klass = api.image_get_class ? api.image_get_class(img, i) : nullptr;
        if (!klass) continue;

        int score = 0;

        // Cek method get_transform (wajib ada di MonoBehaviour)
        if (classHasMethod(klass, "get_transform")) score += 3;

        // Cek method get_position (kadang ada di player)
        if (classHasMethod(klass, "get_position")) score += 2;

        // Cek field yang khas player
        if (classHasField(klass, "m_Position")) score += 2;
        if (classHasField(klass, "m_Team")) score += 2;
        if (classHasField(klass, "m_IsDead")) score += 2;
        if (classHasField(klass, "m_Health")) score += 2;
        if (classHasField(klass, "m_HP")) score += 1;
        if (classHasField(klass, "m_Name")) score += 1;
        if (classHasField(klass, "m_PlayerID")) score += 1;

        if (score > bestScore) {
            bestScore = score;
            bestMatch = klass;
            // Debug: cetak nama kelas
            if (api.class_get_name) {
                void* namePtr = api.class_get_name(klass);
                if (namePtr && api.string_to_utf8) {
                    char* cname = api.string_to_utf8(namePtr);
                    if (cname) {
                        os_log(OS_LOG_DEFAULT, "[FFESP] candidate: %{public}s (score=%d)",
                               cname, score);
                    }
                }
            }
        }
    }

    os_log(OS_LOG_DEFAULT, "[FFESP] best score: %d", bestScore);

    if (bestScore >= 5) {
        return bestMatch;
    }
    return nullptr;
}

static bool InitScan() {
    snprintf(g_debugClass, sizeof(g_debugClass), "scanning...");
    os_log(OS_LOG_DEFAULT, "[FFESP] scanning all classes...");

    // Coba scan otomatis dulu
    g_playerCls = findPlayerClassByScan();

    if (g_playerCls && api.class_get_name) {
        void* namePtr = api.class_get_name(g_playerCls);
        if (namePtr && api.string_to_utf8) {
            char* cname = api.string_to_utf8(namePtr);
            if (cname) {
                snprintf(g_debugClass, sizeof(g_debugClass),
                         "FOUND:%s(%dcls)", cname, g_classCount);
            }
        }
    }

    if (!g_playerCls) {
        // Fallback: coba nama kandidat
        const char* names[] = {
            "Player", "PlayerEntity", "AvatarEntity",
            "LocalPlayer", "Character", nullptr
        };
        for (int i = 0; names[i]; i++) {
            void* k = Il2CppFindClass("COW.GamePlay", names[i]);
            if (k) { g_playerCls = k; break; }
            k = Il2CppFindClass("", names[i]);
            if (k) { g_playerCls = k; break; }
        }
    }

    if (!g_playerCls) {
        snprintf(g_debugClass, sizeof(g_debugClass), "NO CLASS(%d)", g_classCount);
        return false;
    }

    // Cari FindObjectsOfType
    void* objCls = Il2CppFindClass("UnityEngine", "Object");
    if (objCls) {
        g_findMethod = Il2CppFindMethod(objCls, "FindObjectsOfType", 1);
    }

    // Transform methods
    void* transformCls = Il2CppFindClass("UnityEngine", "Transform");
    if (transformCls) {
        g_getPosition = Il2CppFindMethod(transformCls, "get_position", 0);
    }
    g_getTransform = Il2CppFindMethod(g_playerCls, "get_transform", 0);

    os_log(OS_LOG_DEFAULT, "[FFESP] find=%p transform=%p pos=%p",
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

    void* type = api.class_get_type(g_playerCls);
    if (!type) return;
    void* typeObj = api.type_get_object(type);
    if (!typeObj) return;

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

// ============================================================
// RUNTIME
// ============================================================
namespace ESP {

void SetESP(bool v)    { g_esp = v; }
bool IsESP()           { return g_esp; }
void SetLine(bool v)   { g_line = v; }
bool IsLine()          { return g_line; }
void SetName(bool v)   { g_name = v; }
bool IsName()          { return g_name; }
void SetAimbot(bool v) { g_aim = v; }
bool IsAimbot()        { return g_aim; }

static void Worker() {
    api.thread_attach(api.domain_get());
    std::this_thread::sleep_for(std::chrono::seconds(10));

    bool scanReady = InitScan();
    os_log(OS_LOG_DEFAULT, "[FFESP] ScanReady=%d", scanReady);

    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1000/Offsets::FPS));

        if (!g_esp && !g_aim) {
            dispatch_async(dispatch_get_main_queue(), ^{ ClearOverlay(); });
            continue;
        }

        if (scanReady) ScanPlayers();

        auto players = g_players;
        bool esp = g_esp, line = g_line, name = g_name;
        int count = (int)players.size();
        NSString* debugStr = [NSString stringWithUTF8String:g_debugClass];

        dispatch_async(dispatch_get_main_queue(), ^{
            EnsureOverlay();
            ClearOverlay();

            UIWindow* w = gameWindow();
            if (!w) return;
            CGFloat sw = w.bounds.size.width;
            CGFloat sh = w.bounds.size.height;

            // Debug di kanan atas
            DrawText(CGPointMake(sw - 100, 40),
                     [NSString stringWithFormat:@"T:%d", count]);
            DrawText(CGPointMake(sw - 100, 60), debugStr);

            float view[16] = {0};
            Vec3 local = g_local;

            for (const Vec3& p : players) {
                float d = 0;
                float dx = p.x - local.x, dy = p.y - local.y, dz = p.z - local.z;
                d = sqrtf(dx*dx + dy*dy + dz*dz);
                if (d > Offsets::MAX_DIST) continue;

                CGPoint s;
                if (!WorldToScreen(p, view, sw, sh, &s)) continue;

                // Gaya seperti referensi: garis dari atas layar ke player + dot + jarak
                if (esp) {
                    UIColor* col = [UIColor colorWithRed:0 green:1 blue:0.4 alpha:1];
                    DrawLine(CGPointMake(s.x, 0), s, col, 1.0);
                    DrawDot(s, col, 4.0);
                    DrawText(CGPointMake(s.x, s.y - 20),
                             [NSString stringWithFormat:@"%.0fm", d]);
                }
            }
        });
    }
}

void Init() {
    if (!Il2CppInit()) {
        os_log(OS_LOG_DEFAULT, "[FFESP] il2cpp init gagal");
        return;
    }
    std::thread(Worker).detach();
}

} // namespace ESP
