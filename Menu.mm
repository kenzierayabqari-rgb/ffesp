#import "Menu.h"
#import "ESP.h"
#import "Obfuscate.h"

@implementation FFMenu {
    UIView* _panel;
    UIButton* _espBtn;
    UIButton* _lineBtn;
    UIButton* _aimBtn;
    NSTimer* _attachTimer;
}

+ (instancetype)shared {
    static FFMenu* s; static dispatch_once_t t;
    dispatch_once(&t, ^{ s = [[FFMenu alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [self buildUI];
    return self;
}

- (UIWindow*)gameWindow {
    for (UIWindow* w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) return w;
    }
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
    _panel = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 230, 260)];
    _panel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
    _panel.layer.cornerRadius = 14;
    _panel.userInteractionEnabled = YES;
    _panel.hidden = YES;

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
}

- (void)attachToGame {
    UIWindow* w = [self gameWindow];
    if (!w) return;
    if (_panel.superview == w) return;
    [_panel removeFromSuperview];
    [w addSubview:_panel];
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

- (void)onHide {
    _panel.hidden = YES;
    NSLog(@"[FFESP] menu hidden");
}

- (void)onPan:(UIPanGestureRecognizer*)g {
    CGPoint t = [g translationInView:_panel.superview];
    _panel.center = CGPointMake(_panel.center.x + t.x,
                                _panel.center.y + t.y);
    [g setTranslation:CGPointZero inView:_panel.superview];
}

- (void)show {
    _panel.hidden = NO;
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
    if (_attachTimer) { [_attachTimer invalidate]; _attachTimer = nil; }
}
@end
