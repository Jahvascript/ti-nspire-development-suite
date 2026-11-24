#import <Cocoa/Cocoa.h>
int main(void) { @autoreleasepool {
    NSView *left = [[NSView alloc] initWithFrame:NSZeroRect];
    NSView *right = [[NSView alloc] initWithFrame:NSZeroRect];
    NSLayoutConstraint *height = [right.heightAnchor constraintEqualToAnchor:left.heightAnchor];
    BOOL rejected = NO;
    @try { height.active = YES; }
    @catch (NSException *exception) { rejected=YES; printf("Reproduced startup error: %s\n", exception.reason.UTF8String); }
    if (!rejected) return 1;
    NSStackView *parent = [NSStackView stackViewWithViews:@[left,right]];
    parent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    height.active=YES;
    if (!height.active) return 2;
    puts("PASS: shared-height constraint succeeds after the panels share a parent.");
} return 0; }
