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

static volatile bool g_esp  = false;
static volatile bool g_line = true;

static CAShapeLayer* g_overlay = nil;

struct Vec3 { float x, y, z; };
static std::vector<Vec3> g_players;

static UIWindow* gameWindow() {
    for (UIWindow* w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
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

static void DrawLine(CGPoint a, CGPoint b, UIColor* c) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* p = [UIBezierPath bezierPath];
    [p moveToPoint:a];
    [p addLineToPoint:b];
    l.path = p.CGPath;
    l.strokeColor = c.CGColor;
    l.fillColor = [UIColor clearColor].CGColor;
    l.lineWidth = 1.0;
    [g_overlay addSublayer:l];
}

static void DrawDot(CGPoint p, UIColor* c) {
    CAShapeLayer* l = [CAShapeLayer layer];
    UIBezierPath* path = [UIBezierPath bezierPathWithOvalInRect:
        CGRectMake(p.x - 4, p.y - 4, 8, 8)];
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

static char g_dbg[128] = "init";
static void* g_findMethod   = nullptr;
static void* g_playerCls    = nullptr;
static void* g_getTransform = nullptr;
static void* g_getPosition  = nullptr;
static void* g_isLocal      = nullptr;

static bool InitScan() {
    const char* nsList[]   = { "COW.GamePlay", "COW", "" };
    const char* nameList[] = { "Player", "PlayerEntity", "LocalPlayer" };

    for (int i = 0; i < 3 && !g_playerCls; i++) {
        for (int j = 0; j < 3 && !g_playerCls; j++) {
            void* k = Il2CppFindClass(nsList[i], nameList[j]);
            if (k) {
                g_playerCls = k;
                snprintf(g_dbg, sizeof(g_dbg), "OK:%s.%s",
                         nsList[i], nameList[j]);
                break;
            }
        }
    }

    if (!g_playerCls) {
        snprintf(g_dbg, sizeof(g_dbg), "NO CLASS");
        return false;
    }

    void* objCls = Il2CppFindClass("UnityEngine", "Object");
    if (objCls) g_findMethod = Il2CppFindMethod(objCls, "FindObjectsOfType", 1);

    void* trCls = Il2CppFindClass("UnityEngine", "Transform");
    if (trCls) g_getPosition = Il2CppFindMethod(trCls, "get_position", 0);

    g_getTransform = Il2CppFindMethod(g_playerCls, "get_transform", 0);
    g_isLocal      = Il2CppFindMethod(g_playerCls, "IsLocalPlayer", 0);

    snprintf(g_dbg, sizeof(g_dbg), "M f:%d x:%d p:%d L:%d",
             g_findMethod ? 1 : 0,
             g_getTransform ? 1 : 0,
             g_getPosition ? 1 : 0,
             g_isLocal ? 1 : 0);

    return g_findMethod && g_getTransform && g_getPosition;
}

static Vec3 getPos(void* instance) {
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

static bool checkLocal(void* player) {
    if (!g_isLocal || !player) return false;
    uint8_t buf[8] = {0};
    void* args[] = { buf };
    void* exc = nullptr;
    api.runtime_invoke(g_isLocal, player, args, &exc);
    if (exc) return false;
    return *(bool*)buf;
}

static void ScanPlayers() {
    g_players.clear();
    if (!g_findMethod || !g_playerCls) return;

    void* type = api.class_get_type(g_playerCls);
    if (!type) return;
    void* typeObj = api.type_get_object(type);
    if (!typeObj) return;

    void* args[] = { typeObj };
    void* exc = nullptr;
    void* result = api.runtime_invoke(g_findMethod, nullptr, args, &exc);
    if (exc || !result) return;

    int len = api.array_length ? api.array_length(result) : 0;
    if (len <= 0 || len > 512) return;

    int drawn = 0;
    for (int i = 0; i < len; i++) {
        void* player = api.array_get ? api.array_get(result, i) : nullptr;
        if (!player) continue;
        if (checkLocal(player)) continue;

        uint8_t tbuf[16] = {0};
        void* targs[] = { tbuf };
        void* texc = nullptr;
        api.runtime_invoke(g_getTransform, player, targs, &texc);
        if (texc) continue;
        void* transform = *(void**)tbuf;
        if (!transform) continue;

        Vec3 pos = getPos(transform);
        if (pos.x == 0 && pos.y == 0 && pos.z == 0) continue;
        g_players.push_back(pos);
        drawn++;
    }

    snprintf(g_dbg, sizeof(g_dbg), "T:%d/%d", drawn, len);
}

namespace ESP {

void SetESP(bool v) { g_esp = v; }
bool IsESP() { return g_esp; }
void SetLine(bool v) { g_line = v; }
bool IsLine() { return g_line; }
void SetName(bool v) {}
bool IsName() { return true; }
void SetAimbot(bool v) {}
bool IsAimbot() { return false; }

static void Worker() {
    api.thread_attach(api.domain_get());
    std::this_thread::sleep_for(std::chrono::seconds(8));

    bool ready = InitScan();
    os_log(OS_LOG_DEFAULT, "[FFESP] ready=%d", ready);

    while (true) {
        std::this_thread::sleep_for(std::chrono::milliseconds(33));

        if (!g_esp) {
            dispatch_async(dispatch_get_main_queue(), ^{
                ClearOverlay();
            });
            continue;
        }

        if (ready) ScanPlayers();

        std::vector<Vec3> players = g_players;
        int count = (int)players.size();
        NSString* dbg = [NSString stringWithUTF8String:g_dbg];

        dispatch_async(dispatch_get_main_queue(), ^{
            EnsureOverlay();
            ClearOverlay();

            UIWindow* win = gameWindow();
            if (!win) return;

            CGFloat sw = win.bounds.size.width;
            CGFloat sh = win.bounds.size.height;

            DrawText(CGPointMake(sw - 100, 40),
                     [NSString stringWithFormat:@"P:%d", count]);
            DrawText(CGPointMake(sw - 100, 60), dbg);

            UIColor* col = [UIColor colorWithRed:0 green:1 blue:0.4 alpha:1];

            for (size_t i = 0; i < players.size(); i++) {
                Vec3 p = players[i];
                float d = sqrtf(p.x*p.x + p.y*p.y + p.z*p.z);
                CGPoint s = CGPointMake(sw * 0.5f, sh * 0.4f + (i * 20));

                if (g_line) DrawLine(CGPointMake(sw * 0.5f, sh), s, col);
                DrawDot(s, col);
                DrawText(CGPointMake(s.x, s.y - 20),
                         [NSString stringWithFormat:@"%.0f", d]);
            }
        });
    }
}

void Init() {
    if (!Il2CppInit()) return;
    std::thread(Worker).detach();
}

} // namespace ESP
