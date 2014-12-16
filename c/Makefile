all: cocoa.dylib

cocoa.dylib: cocoa.m
	clang -dynamiclib cocoa.m -o cocoa.dylib \
	-framework cocoa

clean:
	rm cocoa.dylib
