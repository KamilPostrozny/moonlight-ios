//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

typedef NS_ENUM(int, FramePacingMode) {
    // Submit every frame that's ready as soon as the display link ticks. Frames
    // that pile up get collapsed into one presentation, but nothing is ever
    // held back.
    FramePacingModeLowestLatency = 0,

    // Keep one frame queued so there's always something to show at the next
    // tick, at the cost of one frame of latency.
    FramePacingModeSmoothestVideo = 1,

    // Lowest latency, but with the display link driven by the stream's actual
    // cadence rather than pinned to the negotiated frame rate. Needs a panel
    // with refresh headroom (ProMotion) and iOS/tvOS 15; falls back to plain
    // lowest latency without them.
    FramePacingModeLowestLatencyVrr = 2,
};

@interface StreamConfiguration : NSObject

@property NSString* host;
@property unsigned short httpsPort;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property NSString* rtspSessionUrl;
@property int serverCodecModeSupport;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property BOOL swapABXYButtons;
@property int audioConfiguration;
@property int supportedVideoFormats;
@property BOOL multiController;
@property FramePacingMode framePacingMode;
@property NSData* serverCert;

@end
