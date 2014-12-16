#include "Cocoa/Cocoa.h"

// Shims to work around lack of struct support

NSRect* nsmakerect(float x, float y, float w, float h) {
  NSRect* rect = malloc(sizeof(NSRect));
  *rect = NSMakeRect(x, y, w, h);
  return rect;
}

@implementation NSWindow (StructExtensions)
- (NSWindow*) initWithContentRectRef:(void*) rect // NSRect, TODO: support struct type encoding
                           styleMask:(long long) style
                             backing:(long long) backing
                               defer:(BOOL) defer {
  [self initWithContentRect:*((NSRect*)rect)
                  styleMask:style
                    backing:backing
                      defer:defer];
  free(rect);
  return self;
}

- (void) cascadeTopLeftFromX:(float)x Y:(float)y {
  [self cascadeTopLeftFromPoint:NSMakePoint(x, y)];
}
@end
