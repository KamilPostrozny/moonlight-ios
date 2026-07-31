//
//  Utils.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "Utils.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>

@implementation Utils
NSString *const deviceName = @"roth";

+ (NSData*) randomBytes:(NSInteger)length {
    char* bytes = malloc(length);
    arc4random_buf(bytes, length);
    NSData* randomData = [NSData dataWithBytes:bytes length:length];
    free(bytes);
    return randomData;
}

+ (NSData*) hexToBytes:(NSString*) hex {
    unsigned long len = [hex length];
    NSMutableData* data = [NSMutableData dataWithCapacity:len / 2];
    char byteChars[3] = {'\0','\0','\0'};
    unsigned long wholeByte;
    
    const char *chars = [hex UTF8String];
    int i = 0;
    while (i < len) {
        byteChars[0] = chars[i++];
        byteChars[1] = chars[i++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }
    
    return data;
}

+ (NSString*) bytesToHex:(NSData*)data {
    const unsigned char* bytes = [data bytes];
    NSMutableString *hex = [[NSMutableString alloc] init];
    for (int i = 0; i < [data length]; i++) {
        [hex appendFormat:@"%02X" , bytes[i]];
    }
    return hex;
}

+ (BOOL)isActiveNetworkVPN {
    NSDictionary *dict = CFBridgingRelease(CFNetworkCopySystemProxySettings());
    NSArray *keys = [dict[@"__SCOPED__"] allKeys];
    for (NSString *key in keys) {
        if ([key containsString:@"tap"] ||
            [key containsString:@"tun"] ||
            [key containsString:@"ppp"] ||
            [key containsString:@"ipsec"]) {
            return YES;
        }
    }
    return NO;
}

#if !TARGET_OS_TV
+ (void) launchUrl:(NSString*)urlString {
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString] options:@{} completionHandler:nil];
}
#endif

+ (void) addHelpOptionToDialog:(UIAlertController*)dialog {
#if !TARGET_OS_TV
    // tvOS doesn't have a browser
    [dialog addAction:[UIAlertAction actionWithTitle:@"Help" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
        [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"];
    }]];
#endif
}

+ (BOOL) parseAddressPortString:(NSString*)addressPort address:(NSRange*)address port:(NSRange*)port {
    if (![addressPort containsString:@":"]) {
        // If there's no port or IPv6 separator, the whole thing is an address
        *address = NSMakeRange(0, [addressPort length]);
        *port = NSMakeRange(NSNotFound, 0);
        return TRUE;
    }
    
    NSInteger locationOfOpeningBracket = [addressPort rangeOfString:@"["].location;
    NSInteger locationOfClosingBracket = [addressPort rangeOfString:@"]"].location;
    if (locationOfOpeningBracket != NSNotFound || locationOfClosingBracket != NSNotFound) {
        // If we have brackets, it's an IPv6 address
        if (locationOfOpeningBracket == NSNotFound || locationOfClosingBracket == NSNotFound ||
            locationOfClosingBracket < locationOfOpeningBracket) {
            // Invalid address format
            return FALSE;
        }
        
        // Cut at the brackets
        *address = NSMakeRange(locationOfOpeningBracket + 1, locationOfClosingBracket - locationOfOpeningBracket - 1);
    }
    else {
        // It's an IPv4 address, so just cut at the port separator
        *address = NSMakeRange(0, [addressPort rangeOfString:@":"].location);
    }
    
    NSUInteger remainingStringLocation = address->location + address->length;
    NSRange remainingStringRange = NSMakeRange(remainingStringLocation, [addressPort length] - remainingStringLocation);
    NSInteger locationOfPortSeparator = [addressPort rangeOfString:@":" options:0 range:remainingStringRange].location;
    if (locationOfPortSeparator != NSNotFound) {
        *port = NSMakeRange(locationOfPortSeparator + 1, [addressPort length] - locationOfPortSeparator - 1);
    }
    else {
        *port = NSMakeRange(NSNotFound, 0);
    }
    
    return TRUE;
}

+ (NSString*) addressPortStringToAddress:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange]) {
        return nil;
    }
    
    return [addressPort substringWithRange:addressRange];
}

+ (unsigned short) addressPortStringToPort:(NSString*)addressPort {
    NSRange addressRange, portRange;
    if (![self parseAddressPortString:addressPort address:&addressRange port:&portRange] || portRange.location == NSNotFound) {
        return 47989;
    }
    
    return [[addressPort substringWithRange:portRange] integerValue];
}

+ (NSString*) addressAndPortToAddressPortString:(NSString*)address port:(unsigned short)port {
    if ([address containsString:@":"]) {
        // IPv6 addresses require escaping
        return [NSString stringWithFormat:@"[%@]:%u", address, port];
    }
    else {
        return [NSString stringWithFormat:@"%@:%u", address, port];
    }
}

@end

#if !TARGET_OS_TV

@implementation MoonlightTheme

+ (UIColor*) accentColor {
    return [UIColor colorWithRed:0.67f green:0.62f blue:1.0f alpha:1.0f];
}

+ (CGFloat) tileCornerRadius {
    return 14.0f;
}

+ (CGFloat) cardCornerRadius {
    return 22.0f;
}

+ (UIVisualEffectView*) glassViewWithTint:(UIColor*)tint {
    UIGlassEffect* effect = [[UIGlassEffect alloc] init];
    effect.tintColor = tint;

    UIVisualEffectView* view = [[UIVisualEffectView alloc] initWithEffect:effect];
    view.clipsToBounds = YES;
    return view;
}

+ (void) applyGlassTint:(UIColor*)tint toView:(UIVisualEffectView*)view {
    UIGlassEffect* effect = [[UIGlassEffect alloc] init];
    effect.tintColor = tint;
    view.effect = effect;
}

+ (UIButtonConfiguration*) glassButtonWithTitle:(NSString*)title
                                          image:(UIImage*)image
                                      prominent:(BOOL)prominent {
    UIButtonConfiguration* config = prominent
        ? [UIButtonConfiguration prominentGlassButtonConfiguration]
        : [UIButtonConfiguration glassButtonConfiguration];

    config.title = title;
    config.image = image;
    config.imagePadding = 6.0f;

    if (prominent) {
        config.baseBackgroundColor = [MoonlightTheme accentColor];
    }

    return config;
}

+ (UIColor*) ambientColorForImage:(UIImage*)image {
    CGImageRef cgImage = image.CGImage;
    if (cgImage == NULL) {
        return nil;
    }

    // Drawing the whole image into a 1x1 context makes the hardware do the
    // averaging for us.
    unsigned char pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, colorSpace,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        return nil;
    }

    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), cgImage);
    CGContextRelease(context);

    UIColor* average = [UIColor colorWithRed:pixel[0] / 255.0f
                                       green:pixel[1] / 255.0f
                                        blue:pixel[2] / 255.0f
                                       alpha:1.0f];

    // Averaging washes colour out badly, so push saturation back up. Clamp
    // brightness so a very dark or very bright cover doesn't produce a tint
    // that swallows content or blinds the user.
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if (![average getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
        return nil;
    }

    return [UIColor colorWithHue:hue
                      saturation:MIN(saturation * 2.2f, 0.85f)
                      brightness:MAX(MIN(brightness, 0.55f), 0.22f)
                           alpha:1.0f];
}

@end

#endif

@implementation NSString (NSStringWithTrim)

- (NSString *)trim {
    return [self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@end
