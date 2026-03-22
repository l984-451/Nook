//
//  HTSymbolHook.m
//  HTSymbolHook
//
//  Copyright (c) 2013 hetima.
//  MIT License
//
//  SECURITY: Stubbed out — runtime symbol hooking and mach_override are no longer
//  needed. On macOS 15.5+ the _setPageMuted: API is always available, so
//  MuteableWKWebView uses it directly via MethodSwizzler instead.
//

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC
#endif

#import "HTSymbolHook.h"

@implementation HTSymbolHook {
    NSString *_imageName;
}

@synthesize imageName = _imageName;

- (BOOL)valid {
    return NO;
}

+ (id)symbolHookWithImageName:(NSString *)name {
    return nil;
}

+ (id)symbolHookWithImageNameSuffix:(NSString *)name {
    return nil;
}

- (void *)symbolPtrWithSymbolName:(NSString *)symbolName {
    return NULL;
}

- (BOOL)overrideSymbol:(NSString *)symbolName withPtr:(void *)ptr reentryIsland:(void **)island {
    return NO;
}

- (BOOL)overrideSymbol:(NSString *)symbolName withPtr:(void *)ptr reentryIsland:(void **)island symbolIndexHint:(UInt32)seekStartIndex {
    return NO;
}

- (UInt32)indexOfSymbol:(NSString *)symbolName {
    return 0;
}

- (void *)symbolPtrWithSymbolName:(NSString *)symbolName startOffset:(UInt32)from endOffset:(UInt32)to {
    return NULL;
}

@end
