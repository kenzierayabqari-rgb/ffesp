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

// ============================================================
// OVERLAY
// ============================================================
static UIWindow* keyWindow() {
    for (UIWindow* w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
    return nil;
}

static void EnsureOverlay() {
    if (g_overlay) return;
    UIWindow* w = keyWindow();
    if (!w) return;
    g_overlay = [CAShapeLayer layer];
    g_overlay.frame = w.bounds;
    g_overlay.backgroundColor = [UIColor clearColor].CGColor;
    g_overlay.zPosition = 99999;
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

// ============================================================
// MATH
// ============================================================
struct Vec3 { float x, y, z; };

static float dist3(const Vec3& a, const Vec3& b) {
    float dx = a.x-b.x, dy = a.y-b.y, dz = a.z-b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

static bool WorldToScreen(const Vec3& w, const float* m, float sw, float sh,
                          CGPoint* out)
{
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
// PLAYER SCAN — ISI SETELAH DUMP
// ============================================================
static std::vector<Vec3> g_players;

static void ScanPlayers() {
    g_players.clear();

    // ----------------------------------------------------------
    // GANTI BAGIAN INI dengan hasil dump FF versi DENI.
    // Contoh alur:
    //
    // void* gmCls  = Il2CppFindClass("", Offsets::CLS_GAME_MANAGER);
    // void* gmInst = ...; // instance via static field
    // void* list   = *(void**)((uint8_t*)gmInst + OFFSET_LIST);
    // int   cnt    = *(int*)((uint8_t*)list + 0x18);
    // void* arr    = *(void**)((uint8_t*)list + 0x10);
    //
    // for (int i = 0; i < cnt; i++) {
    //     void* p = *(void**)((uint8_t*)arr + 0x20 + i*8);
    //     if (!p) continue;
    //     if (*(bool*)((uint8_t*)p + OFFSET_DEAD)) continue;
    //     Vec3 pos = *(Vec3*)((uint8_t*)p + OFFSET_POS);
    //     g_players.push_back(pos);
    // }
    // ----------------------------------------------------------
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

    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1000/Offsets::FPS));

        if (!g_esp && !g_aim) {
            dispatch_async(dispatch_get_main_queue(), ^{ ClearOverlay(); });
            continue;
        }

        ScanPlayers();

        dispatch_async(dispatch_get_main_queue(), ^{
            EnsureOverlay();
            ClearOverlay();

            UIWindow* w = keyWindow();
            if (!w) return;
            CGFloat sw = w.bounds.size.width;
            CGFloat sh = w.bounds.size.height;

            float view[16] = {0}; // isi dari Camera.main.worldToCameraMatrix
            Vec3 local = {0,0,0}; // posisi lokal

            for (const Vec3& p : g_players) {
                float d = dist3(p, local);
                if (d > Offsets::MAX_DIST) continue;

                CGPoint s;
                if (!WorldToScreen(p, view, sw, sh, &s)) continue;

                if (g_esp) {
                    CGFloat h = 10000.0 / d;
                    CGFloat bw = h * 0.5;
                    DrawBox(CGRectMake(s.x - bw/2, s.y - h, bw, h));
                }
                if (g_line) {
                    DrawLine(CGPointMake(sw/2, sh), s);
                }
                if (g_name) {
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
