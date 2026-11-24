// Test only: PDFKit queries a display scale even when extracting text.
// Return no screen to test text extraction without accessing a window server.
// This object is never linked into the delivered application.
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
static id noScreen(id self, SEL selector) { return nil; }
void studio_test_no_screen(void) {
    Method method = class_getClassMethod(NSScreen.class, @selector(mainScreen));
    method_setImplementation(method, (IMP)noScreen);
}
