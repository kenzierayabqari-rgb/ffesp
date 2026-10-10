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

static void DrawLine(CGPoint a, CGPoint b, UIColor* c, CGFloat lw) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* p = [UIBezierPath bezierPath];
    [p moveToPoint:a]; [p addLineToPoint:b];
    l.path = p.CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = lw;
    [g_overlay addSublayer:l];
}

static void DrawBox(CGRect r, UIColor* c) {
    CAShapeLayer* l = [CAShapeLayer layer];
    l.path = [UIBezierPath bezierPathWithRect:r].CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = 1.5;
    [g_overlay addSublayer:l];
}

static void DrawDot(CGPoint p, UIColor* c, CGFloat r) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* path = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(p.x - r, p.y - r, r*2, r*2)];
    l.path = path.CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor whiteColor].CGColor;
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
// SCAN STATE
// ============================================================
static char g_debugClass[128] = "init...";
static int  g_debugFound = 0;

static void* g_findMethod        = nullptr;   // UnityEngine.Object.FindObjectsOfType
static void* g_playerCls         = nullptr;
static void* g_getTransform      = nullptr;
static void* g_getPosition       = nullptr;
static void* g_isLocalMethod     = nullptr;   // IsLocalPlayer
static void* g_getCurHP          = nullptr;   // get_CurHP
static void* g_getMaxHP          = nullptr;   // get_MaxHP
static void* g_getNickName       = nullptr;   // get_NickName
static void* g_isDieing          = nullptr;   // get_IsDieing
static void* g_isTeammate        = nullptr;   // IsLocalTeammate
static void* g_localPlayer       = nullptr;   // cached local player instance

// Dapatkan system type pointer dari kelas
static void* classToTypeObj(void* klass) {
    if (!klass || !api.class_get_type || !api.type_get_object) return nullptr;
    void* type = api.class_get_type(klass);
    if (!type) return nullptr;
    return api.type_get_object(type);
}

// Panggil method no-arg tanpa instance (static)
static void* invokeStatic0(void* method) {
    if (!method || !api.runtime_invoke) return nullptr;
    void* exc = nullptr;
    return api.runtime_invoke(method, nullptr, nullptr, &exc);
}

// Panggil method dengan instance
static void* invokeInstance0(void* method, void* instance) {
    if (!method || !instance || !api.runtime_invoke) return nullptr;
    void* exc = nullptr;
    return api.runtime_invoke(method, instance, nullptr, &exc);
}

// ============================================================
// INIT SCAN — cari kelas COW.GamePlay.Player
// ============================================================
static bool InitScan() {
    os_log(OS_LOG_DEFAULT, "[FFESP] === InitScan ===");

    // Cari kelas Player — dengan namespace yang benar dari dump
    const char* candidatesNs[]   = { "COW.GamePlay", "COW", "" };
    const char* candidatesName[] = { "Player", "PlayerEntity", "LocalPlayer" };

    for (int i = 0; i < 3 && !g_playerCls; i++) {
        for (int j = 0; j < 3 && !g_playerCls; j++) {
            void* k = Il2CppFindClass(candidatesNs[i], candidatesName[j]);
            if (k) {
                g_playerCls = k;
                snprintf(g_debugClass, sizeof(g_debugClass),
                         "OK:%s.%s", candidatesNs[i], candidatesName[j]);
                os_log(OS_LOG_DEFAULT, "[FFESP] FOUND class: %s.%s",
                       candidatesNs[i], candidatesName[j]);
                break;
            }
        }
    }

    if (!g_playerCls) {
        snprintf(g_debugClass, sizeof(g_debugClass), "NO CLASS");
        return false;
    }

    // Ambil method-method penting
    void* objCls = Il2CppFindClass("UnityEngine", "Object");
    if (objCls) {
        g_findMethod = Il2CppFindMethod(objCls, "FindObjectsOfType", 1);
    }

    void* transformCls = Il2CppFindClass("UnityEngine", "Transform");
    if (transformCls) {
        g_getPosition = Il2CppFindMethod(transformCls, "get_position", 0);
    }
    g_getTransform = Il2CppFindMethod(g_playerCls, "get_transform", 0);

    // Method khusus Player (dari dump)
    g_isLocalMethod  = Il2CppFindMethod(g_playerCls, "IsLocalPlayer", 0);
    g_getCurHP       = Il2CppFindMethod(g_playerCls, "get_CurHP", 0);
    g_getMaxHP       = Il2CppFindMethod(g_playerCls, "get_MaxHP", 0);
    g_getNickName    = Il2CppFindMethod(g_playerCls, "get_NickName", 0);
    g_isDieing       = Il2CppFindMethod(g_playerCls, "get_IsDieing", 0);
    g_isTeammate     = Il2CppFindMethod(g_playerCls, "IsLocalTeammate", 0);

    os_log(OS_LOG_DEFAULT,
           "[FFESP] methods: find=%p xform=%p pos=%p isLocal=%p HP=%p name=%p",
           g_findMethod, g_getTransform, g_getPosition,
           g_isLocalMethod, g_getCurHP, g_getNickName);

    snprintf(g_debugClass, sizeof(g_debugClass),
             "M f:%d x:%d p:%d L:%d",
             g_findMethod ? 1 : 0,
             g_getTransform ? 1 : 0,
             g_getPosition ? 1 : 0,
             g_isLocalMethod ? 1 : 0);

    return g_findMethod && g_getTransform && g_getPosition;
}

// ============================================================
// SCAN PLAYERS — pakai FindObjectsOfType
// ============================================================
static Vec3 invokeGetPosition(void* instance) {
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

static bool isLocal(void* player) {
    if (!g_isLocalMethod || !player) return false;
    uint8_t buf[8] = {0};
    void* args[] = { buf };
    void* exc = nullptr;
    api.runtime_invoke(g_isLocalMethod, player, args, &exc);
    if (exc) return false;
    return *(bool*)buf;
}

static void ScanPlayers() {
    g_players.clear();
    g_debugFound = 0;

    if (!g_findMethod || !g_playerCls) return;

    void* typeObj = classToTypeObj(g_playerCls);
    if (!typeObj) {
        snprintf(g_debugClass, sizeof(g_debugClass), "no type obj");
        return;
    }

    void* args[] = { typeObj };
    void* exc = nullptr;
    void* result = api.runtime_invoke(g_findMethod, nullptr, args, &exc);
    if (exc || !result) {
        snprintf(g_debugClass, sizeof(g_debugClass), "invoke fail");
        return;
    }

    int len = api.array_length ? api.array_length(result) : 0;
    if (len <= 0 || len > 512) {
        snprintf(g_debugClass, sizeof(g_debugClass), "arr len=%d", len);
        g_debugFound = len;
        return;
    }

    int drawn = 0;
    for (int i = 0; i < len; i++) {
        void* player = api.array_get ? api.array_get(result, i) : nullptr;
        if (!player) continue;

        // Skip local player
        if (isLocal(player)) continue;

        // Ambil transform
        uint8_t tbuf[16] = {0};
        void* targs[] = { tbuf };
        void* texc = nullptr;
        api.runtime_invoke(g_getTransform, player, targs, &texc);
        if (texc) continue;
        void* transform = *(void**)tbuf;
        if (!transform) continue;

        Vec3 pos = invokeGetPosition(transform);
        if (pos.x == 0 && pos.y == 0 && pos.z == 0) continue;
        g_players.push_back(pos);
        drawn++;
    }

    snprintf(g_debugClass, sizeof(g_debugClass), "T:%d/%d", drawn, len);
    g_debugFound = drawn;
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
    std::this_thread::sleep_for(std::chrono::seconds(8));

    bool scanReady = InitScan();
    os_log(OS_LOG_DEFAULT, "[FFESP] ScanReady=%d", scanReady);

    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(33));

        if (!g_esp) {
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
            CGFloat sh = w.bounds.size.height;

            DrawText(CGPointMake(sw - 100, 40),
                     [NSString stringWithFormat:@"P:%d", count]);
            DrawText(CGPointMake(sw - 100, 60), debugStr);

            if (!esp) return;

            UIColor* col = [UIColor colorWithRed:0 green:1 blue:0.4 alpha:1];
            for (const Vec3& p : players) {
                CGPoint s;
                if (!WorldToScreen(p, nullptr, sw, sh, &s)) {
                    // Tidak pakai matrix dulu — pakai posisi mentah sementara
                    // untuk melihat apakah data masuk
                    continue;
                }
                if (line) DrawLine(CGPointMake(s.x, 0), s, col, 1.0);
                DrawDot(s, col, 4.0);
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
