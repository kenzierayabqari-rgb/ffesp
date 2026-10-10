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

static volatile bool g_esp   = false;
static volatile bool g_line  = true;
static volatile bool g_name  = true;
static volatile bool g_aim   = false;

static CAShapeLayer* g_overlay = nil;

struct Vec3 { float x, y, z; };
static std::vector<Vec3> g_players;
static Vec3 g_local = {0,0,0};

// ---------- OVERLAY ----------
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

static void DrawBox(CGRect r) {
    CAShapeLayer* l = [CAShapeLayer layer];
    l.path = [UIBezierPath bezierPathWithRect:r].CGPath;
    l.strokeColor = [UIColor colorWithRed:0 green:1 blue:0.53 alpha:1].CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = 1.5;
    [g_overlay addSublayer:l];
}

static void DrawLine(CGPoint a, CGPoint b) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* p = [UIBezierPath bezierPath];
    [p moveToPoint:a]; [p addLineToPoint:b];
    l.path = p.CGPath;
    l.strokeColor = [UIColor colorWithRed:1 green:0.2 blue:0.3 alpha:1].CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = 1.2;
    [g_overlay addSublayer:l];
}

static void DrawText(CGPoint pt, NSString* txt) {
    CATextLayer* t = [CATextLayer layer];
    t.string = txt;
    t.fontSize = 11;
    t.foregroundColor = [UIColor whiteColor].CGColor;
    t.alignmentMode = kCAAlignmentCenter;
    t.contentsScale = [UIScreen mainScreen].scale;
    t.frame = CGRectMake(pt.x - 60, pt.y, 120, 14);
    t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35].CGColor;
    [g_overlay addSublayer:t];
}

// ---------- MATH ----------
static float dist3(const Vec3& a, const Vec3& b) {
    float dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

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

// ---------- SCAN PLAYER ----------
// Pendekatan: pakai UnityEngine.Object.FindObjectsOfType(Player.class)
// Tidak butuh offset field — hanya nama kelas & method.

static void* g_findMethod   = nullptr;
static void* g_playerCls    = nullptr;
static void* g_getTransform = nullptr;
static void* g_getPosition  = nullptr;
static void* g_localPlayer  = nullptr;

static bool InitScan() {
    // Cari kelas Player — coba beberapa nama alternatif
    const char* candidates[] = { "Player", "Character", "Avatar",
                                 "PlayerEntity", "AvatarEntity", nullptr };
    for (int i = 0; candidates[i]; i++) {
        g_playerCls = Il2CppFindClass("", candidates[i]);
        if (g_playerCls) {
            os_log(OS_LOG_DEFAULT, "[FFESP] Player class: %{public}s",
                   candidates[i]);
            break;
        }
    }
    if (!g_playerCls) {
        os_log(OS_LOG_DEFAULT, "[FFESP] Player class tidak ditemukan");
        return false;
    }

    // Cari method FindObjectsOfType di UnityEngine.Object
    void* objCls = Il2CppFindClass("UnityEngine", "Object");
    if (objCls)
        g_findMethod = Il2CppFindMethod(objCls, "FindObjectsOfType", 1);

    // Cari method transform & position di Player
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
    if (!g_findMethod || !g_playerCls) return;

    // Dapatkan System.Type dari kelas Player
    void* typeObj = api.class_get_type(g_playerCls);
    if (!typeObj) return;

    // Panggil FindObjectsOfType(type)
    void* args[] = { typeObj };
    void* exc = nullptr;
    void* result = api.runtime_invoke(g_findMethod, nullptr, args, &exc);
    if (exc || !result) return;

    int len = api.array_length(result);
    if (len <= 0 || len > 256) return;

    for (int i = 0; i < len; i++) {
        void* player = api.array_get(result, i);
        if (!player) continue;

        // Panggil get_transform(player) → Transform*
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
}

// ---------- RUNTIME ----------
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

    // Tunggu Unity siap
    std::this_thread::sleep_for(std::chrono::seconds(8));
    bool scanReady = InitScan();
    os_log(OS_LOG_DEFAULT, "[FFESP] ScanReady=%d", scanReady);

    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1000/Offsets::FPS));

        if (!g_esp && !g_aim) {
            dispatch_async(dispatch_get_main_queue(), ^{ ClearOverlay(); });
            continue;
        }

        if (scanReady) ScanPlayers();

        // Snapshot untuk render
        auto players = g_players;
        bool esp = g_esp, line = g_line, name = g_name;
        int count = (int)players.size();

        dispatch_async(dispatch_get_main_queue(), ^{
            EnsureOverlay();
            ClearOverlay();

            UIWindow* w = gameWindow();
            if (!w) return;
            CGFloat sw = w.bounds.size.width;
            CGFloat sh = w.bounds.size.height;

            // Debug: tampilkan jumlah target di kanan atas
            DrawText(CGPointMake(sw - 60, 40),
                     [NSString stringWithFormat:@"T:%d", count]);

            float view[16] = {0};
            Vec3 local = g_local;

            for (const Vec3& p : players) {
                float d = dist3(p, local);
                if (d > Offsets::MAX_DIST) continue;

                CGPoint s;
                if (!WorldToScreen(p, view, sw, sh, &s)) continue;

                if (esp) {
                    CGFloat h = 10000.0 / d;
                    CGFloat bw = h * 0.5;
                    DrawBox(CGRectMake(s.x - bw/2, s.y - h, bw, h));
                }
                if (line) {
                    DrawLine(CGPointMake(sw/2, sh), s);
                }
                if (name) {
                    DrawText(CGPointMake(s.x, s.y - 30),
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
