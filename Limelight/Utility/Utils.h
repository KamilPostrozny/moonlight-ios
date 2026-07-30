//
//  Utils.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@interface Utils : NSObject

typedef NS_ENUM(int, PairState) {
    PairStateUnknown,
    PairStateUnpaired,
    PairStatePaired
};

typedef NS_ENUM(int, State) {
    StateUnknown,
    StateOffline,
    StateOnline
};

FOUNDATION_EXPORT NSString *const deviceName;

+ (NSData*) randomBytes:(NSInteger)length;
+ (NSString*) bytesToHex:(NSData*)data;
+ (NSData*) hexToBytes:(NSString*) hex;
+ (void) addHelpOptionToDialog:(UIAlertController*)dialog;
+ (BOOL) isActiveNetworkVPN;
+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port;
+ (NSString*) addressPortStringToAddress:(NSString*)addressPort;
+ (unsigned short) addressPortStringToPort:(NSString*)addressPort;
+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port;

#if !TARGET_OS_TV
+ (void) launchUrl:(NSString*)urlString;
#endif

@end

#if !TARGET_OS_TV

// Design tokens and Liquid Glass helpers.
//
// Every UIGlassEffect / glass UIButtonConfiguration call in the app goes
// through here. Development happens without a local compiler, so keeping the
// iOS 26-only API surface in one file means a wrong symbol is a single-site
// fix and one CI round trip.
@interface MoonlightTheme : NSObject

+ (UIColor*) accentColor;

+ (CGFloat) tileCornerRadius;
+ (CGFloat) cardCornerRadius;

// A glass-backed container. Pass nil for an untinted effect.
+ (UIVisualEffectView*) glassViewWithTint:(UIColor*)tint;

// Retints an existing glass view in place. UIGlassEffect is immutable once
// installed, so this swaps in a fresh effect.
+ (void) applyGlassTint:(UIColor*)tint toView:(UIVisualEffectView*)view;

+ (UIButtonConfiguration*) glassButtonWithTitle:(NSString*)title
                                          image:(UIImage*)image
                                      prominent:(BOOL)prominent;

// Average colour of an image, saturation-boosted and brightness-clamped so it
// works as an ambient background tint. Returns nil for a nil image.
+ (UIColor*) ambientColorForImage:(UIImage*)image;

@end

#endif

@interface NSString (NSStringWithTrim)

- (NSString*) trim;

@end
