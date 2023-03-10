#import <Foundation/Foundation.h>
typedef struct {int a;int b;} Bar;

int m1(Bar in){return in.a*in.b;           }
Bar m2(Bar in){in.a*=2; in.b*=2; return in;}

@interface Foo : NSObject
- (int) m0:(int) x;
- (int) m1:(Bar) x;
- (Bar) m2:(Bar) x;
@end
@implementation Foo {}
- (int) m0:(int) x {return 2*x              ;}
- (int) m1:(Bar) x {return x.a*x.b          ;}
- (Bar) m2:(Bar) x {x.a*=2; x.b*=2; return x;}
@end

int main(int argc, const char * argv[]) {
    //@autoreleasepool {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // insert code here...
    NSLog(@"Hello, World!");
    Foo* foo = [Foo new];
    NSLog(@"%d", [foo m0:4]);
    Bar b = {3,4};
    NSLog(@"%d", [foo m1:b]);
    Bar b2 = [foo m2:b];
    NSLog(@"%d, %d", b2.a, b2.b);

    [pool drain];
    //[pool release];
    [foo release];

    return 0;

}