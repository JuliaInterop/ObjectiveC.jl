
typedef struct {int a;int b;} Bar;

int m1(Bar in){return in.a*in.b;           }
Bar m2(Bar in){in.a*=2; in.b*=2; return in;}

@class SomeClass;
@protocol SomeProtocol;

@interface Foo 
- (int) m0:(int) x;
- (int) m1:(Bar) x;
- (Bar) m2:(Bar) x;
@end
@implementation Foo {}
- (int) m0:(int) x {return 2*x              ;}
- (int) m1:(Bar) x {return x.a*x.b          ;}
- (Bar) m2:(Bar) x {x.a*=2; x.b*=2; return x;}
@end

