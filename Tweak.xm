#import <UIKit/UIKit.h>
#import "Menu.h"
#import "ESP.h"

__attribute__((constructor))
static void ffesp_boot() {
    NSLog(@"[FFESP] loaded");
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            ESP::Init();
            [[FFMenu shared] show];
        });
}
