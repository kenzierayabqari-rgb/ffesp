#import "Menu.h"
#import "ESP.h"
#import "Obfuscate.h"

@implementation FFMenu {
    UIView* _panel;
    UIButton* _espBtn;
    UIButton* _lineBtn;
    UIButton* _aimBtn;
    UIButton* _floatBtn;   // tombol kecil floating
    NSTimer* _attachTimer;
    BOOL _panelVisible;
}

+ (instancetype)shared {
    static FFMenu* s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[FFMenu alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _panelVisible = YES;
    [self buildUI];
    return self;
}

- (UIWindow*)gameWindow {
    for (UIWindow* w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
    UIWindow* found = nil;
    for (UIWindow* w in [UIApplication sharedApplication].windows) {
        if (w.hidden) continue;
        if (w.windowLevel != UIWindowLevelNormal) continue;
        found = w;
    }
    return found;
}

- (UIButton*)mk:(NSString*)t y:(CGFloat)y sel:(SEL)s {
    UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(15, y, 200, 42);
    [b setTitle:t forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
    b.layer.cornerRadius = 8;
    b.userInteractionEnabled = YES;
    [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildUI {
    // ---------- PANEL UTAMA ----------
    _panel = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 230, 260)];
    _panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    _panel.layer.cornerRadius = 14;
    _panel.userInteractionEnabled = YES;
    _panel.hidden = NO;

    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, 230, 26)];
    t.text = @"FF ESP";
    t.textColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:1];
    t.textAlignment = NSTextAlignmentCenter;
    t.font = [UIFont boldSystemFontOfSize:18];
    [_panel addSubview:t];

    _espBtn  = [self mk:@"ESP: OFF"    y:52  sel:@selector(onESP)];
    _lineBtn = [self mk:@"LINE: ON"    y:100 sel:@selector(onLine)];
    _aimBtn  = [self mk:@"AIMBOT: OFF" y:148 sel:@selector(onAim)];
    UIButton* h = [self mk:@"HIDE"     y:196 sel:@selector(onHide)];

    [_panel addSubview:_espBtn];
    [_panel addSubview:_lineBtn];
    [_panel addSubview:_aimBtn];
    [_panel addSubview:h];

    UIPanGestureRecognizer* pan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [_panel addGestureRecognizer:pan];

    // ---------- TOMBOL FLOATING (selalu tampil) ----------
    _floatBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _floatBtn.frame = CGRectMake(0, 0, 44, 44);  // posisi di-set nanti
    [_floatBtn setTitle:@"⚙" forState:UIControlStateNormal];
    [_floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _floatBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    _floatBtn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _floatBtn.layer.cornerRadius = 22;
    _floatBtn.layer.borderWidth = 1;
    _floatBtn.layer.borderColor = [UIColor colorWithRed:0 green:1 blue:0.5 alpha:0.7].CGColor;
    _floatBtn.userInteractionEnabled = YES;
    [_floatBtn addTarget:self action:@selector(onFloatTap) forControlEvents:UIControlEventTouchUpInside];

    // Drag untuk tombol floating
    UIPanGestureRecognizer* fpan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onFloatPan:)];
    [_floatBtn addGestureRecognizer:fpan];
}

- (void)attachToGame {
    UIWindow* w = [self gameWindow];
    if (!w) return;

    if (_panel.superview != w) {
        [_panel removeFromSuperview];
        [w addSubview:_panel];
    }
    if (_floatBtn.superview != w) {
        [_floatBtn removeFromSuperview];
        [w addSubview:_floatBtn];
        // Posisi default: kanan atas
        _floatBtn.center = CGPointMake(w.bounds.size.width - 40, 120);
    }
    [w bringSubviewToFront:_floatBtn];
    [w bringSubviewToFront:_panel];
}

- (void)onESP {
    BOOL v = !ESP::IsESP();
    ESP::SetESP(v);
    [_espBtn setTitle:(v?@"ESP: ON":@"ESP: OFF") forState:UIControlStateNormal];
    NSLog(@"[FFESP] ESP=%d", v);
}

- (void)onLine {
    BOOL v = !ESP::IsLine();
    ESP::SetLine(v);
    [_lineBtn setTitle:(v?@"LINE: ON":@"LINE: OFF") forState:UIControlStateNormal];
    NSLog(@"[FFESP] LINE=%d", v);
}

- (void)onAim {
    BOOL v = !ESP::IsAimbot();
    ESP::SetAimbot(v);
    [_aimBtn setTitle:(v?@"AIMBOT: ON":@"AIMBOT: OFF") forState:UIControlStateNormal];
    NSLog(@"[FFESP] AIM=%d", v);
}

// HIDE panel — tombol floating tetap ada
- (void)onHide {
    _panel.hidden = YES;
    _panelVisible = NO;
    NSLog(@"[FFESP] panel hidden");
}

// Tap tombol floating — toggle panel
- (void)onFloatTap {
    _panelVisible = !_panelVisible;
    _panel.hidden = !_panelVisible;
    NSLog(@"[FFESP] panel visible=%d", _panelVisible);
}

- (void)onPan:(UIPanGestureRecognizer*)g {
    CGPoint t = [g translationInView:_panel.superview];
    _panel.center = CGPointMake(_panel.center.x + t.x,
                                _panel.center.y + t.y);
    [g setTranslation:CGPointZero inView:_panel.superview];
}

- (void)onFloatPan:(UIPanGestureRecognizer*)g {
    CGPoint t = [g translationInView:_floatBtn.superview];
    _floatBtn.center = CGPointMake(_floatBtn.center.x + t.x,
                                   _floatBtn.center.y + t.y);
    [g setTranslation:CGPointZero inView:_floatBtn.superview];
}

- (void)show {
    _panel.hidden = NO;
    _panelVisible = YES;
    [self attachToGame];
    if (_attachTimer) [_attachTimer invalidate];
    _attachTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                    target:self
                                                  selector:@selector(attachToGame)
                                                  userInfo:nil
                                                   repeats:YES];
    NSLog(@"[FFESP] menu shown");
}

- (void)hide {
    _panel.hidden = YES;
    _floatBtn.hidden = YES;
    if (_attachTimer) { [_attachTimer invalidate]; _attachTimer = nil; }
}
@end
