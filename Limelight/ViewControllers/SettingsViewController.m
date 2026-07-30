//
//  SettingsViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "SettingsViewController.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "Utils.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

// One row of the settings list. `accessory` is a control shown on the trailing
// edge (a switch, or a pop-up button); `custom` replaces the whole cell body
// (the bitrate slider).
@interface MoonlightSettingsRow : NSObject
@property (nonatomic, copy) NSString* title;
@property (nonatomic, copy) NSString* subtitle;
@property (nonatomic, strong) UIView* accessory;
@property (nonatomic, strong) UIView* custom;
@property (nonatomic, copy) void (^action)(void);
@end

@implementation MoonlightSettingsRow
@end

@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@end

@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;

    UITableView* _tableView;
    NSArray<NSString*>* _sectionTitles;
    NSArray<NSArray<MoonlightSettingsRow*>*>* _rows;

    UILabel* _bitrateValueLabel;
    UISlider* _bitrateSlider;
    UIButton* _resolutionButton;
    UIButton* _framerateButton;
    UIButton* _codecButton;
    UIButton* _onscreenControlsButton;
    UIButton* _framePacingButton;
    UISegmentedControl* _touchModeControl;

    NSInteger _resolutionIndex;
    NSInteger _framerate;
    NSInteger _onscreenControls;
    uint32_t  _codecPref;
    BOOL _optimizeGames;
    BOOL _multiController;
    BOOL _swapABXYButtons;
    BOOL _audioOnPC;
    BOOL _btMouseSupport;
    BOOL _useFramePacing;
    BOOL _absoluteTouchMode;
    BOOL _statsOverlay;
    BOOL _enableHdr;
    BOOL _hdrSupported;
    BOOL _hevcSupported;
    BOOL _av1Supported;
    BOOL _support120Fps;
}

static const int bitrateTable[] = {
    500,
    1000,
    1500,
    2000,
    2500,
    3000,
    4000,
    5000,
    6000,
    7000,
    8000,
    9000,
    10000,
    12000,
    15000,
    18000,
    20000,
    30000,
    40000,
    50000,
    60000,
    70000,
    80000,
    100000,
    120000,
    150000,
};

const int RESOLUTION_TABLE_SIZE = 7;
const int RESOLUTION_TABLE_CUSTOM_INDEX = RESOLUTION_TABLE_SIZE - 1;
CGSize resolutionTable[RESOLUTION_TABLE_SIZE];

-(int)getSliderValueForBitrate:(NSInteger)bitrate {
    int i;

    for (i = 0; i < (sizeof(bitrateTable) / sizeof(*bitrateTable)); i++) {
        if (bitrate <= bitrateTable[i]) {
            return i;
        }
    }

    // Return the last entry in the table
    return i - 1;
}

BOOL isCustomResolution(CGSize res) {
    if (res.width == 0 && res.height == 0) {
        return NO;
    }

    for (int i = 0; i < RESOLUTION_TABLE_CUSTOM_INDEX; i++) {
        if (res.width == resolutionTable[i].width && res.height == resolutionTable[i].height) {
            return NO;
        }
    }

    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* currentSettings = [dataMan getSettings];

    // Ensure we pick a bitrate that falls exactly onto a slider notch
    _bitrate = bitrateTable[[self getSliderValueForBitrate:[currentSettings.bitrate intValue]]];

    // Get the size of the screen with and without safe area insets.
    //
    // Streaming is always landscape, but this view (browsing) now rotates, so
    // window.frame's width/height swap depending on the device's current
    // orientation. Derive the streaming width/height from the window's
    // long/short axis instead of "whichever is currently .width" — otherwise
    // a resolution picked in one orientation stops matching in the other and
    // the row silently falls through to the custom entry.
    UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
    CGFloat screenScale = window.screen.scale;
    CGFloat rawWidth = window.frame.size.width;
    CGFloat rawHeight = window.frame.size.height;
    CGFloat streamWidthPoints = MAX(rawWidth, rawHeight);
    CGFloat streamHeightPoints = MIN(rawWidth, rawHeight);

    CGFloat safeAreaWidth = (streamWidthPoints - window.safeAreaInsets.left - window.safeAreaInsets.right) * screenScale;
    CGFloat fullScreenWidth = streamWidthPoints * screenScale;
    CGFloat fullScreenHeight = streamHeightPoints * screenScale;

    resolutionTable[0] = CGSizeMake(640, 360);
    resolutionTable[1] = CGSizeMake(1280, 720);
    resolutionTable[2] = CGSizeMake(1920, 1080);
    resolutionTable[3] = CGSizeMake(3840, 2160);
    resolutionTable[4] = CGSizeMake(safeAreaWidth, fullScreenHeight);
    resolutionTable[5] = CGSizeMake(fullScreenWidth, fullScreenHeight);
    resolutionTable[6] = CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]); // custom initial value

    // Don't populate the custom entry unless we have a custom resolution
    if (!isCustomResolution(resolutionTable[6])) {
        resolutionTable[6] = CGSizeMake(0, 0);
    }

    _hevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC);
    _av1Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
    _hdrSupported = _hevcSupported && (AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10) != 0;
    _support120Fps = [UIScreen mainScreen].maximumFramesPerSecond > 62;

    _framerate = [currentSettings.framerate integerValue];
    if (_framerate != 30 && _framerate != 60 && _framerate != 120) {
        _framerate = 60;
    }

    _resolutionIndex = 1;
    for (int i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
        if ((int)resolutionTable[i].height == [currentSettings.height intValue] &&
            (int)resolutionTable[i].width == [currentSettings.width intValue]) {
            _resolutionIndex = i;
            break;
        }
    }
    _lastSelectedResolutionIndex = _resolutionIndex;

    _codecPref = currentSettings.preferredCodec;
    _onscreenControls = [currentSettings.onscreenControls integerValue];
    if (_onscreenControls < 0 || _onscreenControls > 3) {
        // Guard against out-of-range persisted data (bad migration, manual DB edit,
        // a rollback from a version with more options) — controlTitles[] in
        // rebuildRows is a fixed 4-element array and would throw otherwise.
        _onscreenControls = 1;   // Auto
    }
    _optimizeGames = currentSettings.optimizeGames;
    _multiController = currentSettings.multiController;
    _swapABXYButtons = currentSettings.swapABXYButtons;
    _audioOnPC = currentSettings.playAudioOnPC;
    _btMouseSupport = currentSettings.btMouseSupport;
    _useFramePacing = currentSettings.useFramePacing;
    _absoluteTouchMode = currentSettings.absoluteTouchMode;
    _statsOverlay = currentSettings.statsOverlay;
    _enableHdr = currentSettings.enableHdr && _hdrSupported;

    [self buildTableView];
    [self rebuildRows];

    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
}

- (void) doneTapped {
    [self saveSettings];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void) buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"row"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"customRow"];
    [self.view addSubview:_tableView];
}

- (UISwitch*) switchForValue:(BOOL)value action:(SEL)action {
    UISwitch* toggle = [[UISwitch alloc] init];
    toggle.on = value;
    toggle.onTintColor = [MoonlightTheme accentColor];
    [toggle addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return toggle;
}

// A pop-up row control: shows the current value, taps open a menu.
- (UIButton*) menuButtonWithTitle:(NSString*)title menu:(UIMenu*)menu {
    UIButton* button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration* config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = title;
    config.baseForegroundColor = [UIColor secondaryLabelColor];
    config.contentInsets = NSDirectionalEdgeInsetsZero;

    // Give the row the standard pop-up affordance so it reads as tappable
    // rather than static text.
    config.image = [UIImage systemImageNamed:@"chevron.up.chevron.down"];
    config.imagePlacement = NSDirectionalRectEdgeTrailing;
    config.imagePadding = 6.0f;
    config.preferredSymbolConfigurationForImage =
        [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightSemibold];

    button.configuration = config;
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;

    // accessoryView is laid out from its frame, not by Auto Layout, and a
    // button from buttonWithType: starts at CGRectZero.
    button.frame = (CGRect){CGPointZero, [button systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]};

    return button;
}

- (MoonlightSettingsRow*) rowWithTitle:(NSString*)title accessory:(UIView*)accessory {
    MoonlightSettingsRow* row = [[MoonlightSettingsRow alloc] init];
    row.title = title;
    row.accessory = accessory;
    return row;
}

// The row's displayed value: plain names for the fixed entries, but actual
// pixel dimensions for the two device-derived entries (Safe Area, Full
// Screen) and the custom entry, since "Safe Area" on its own doesn't tell
// the user what they picked.
- (NSString*) resolutionTitleForIndex:(NSInteger)index {
    NSArray<NSString*>* names = @[@"360p", @"720p", @"1080p", @"4K"];
    if (index < names.count) {
        return names[index];
    }
    return [NSString stringWithFormat:@"%d × %d",
            (int)resolutionTable[index].width,
            (int)resolutionTable[index].height];
}

// The menu's entry label: keeps "Safe Area" / "Full Screen" understandable
// as choices, even though the row itself now shows their dimensions.
- (NSString*) resolutionMenuTitleForIndex:(NSInteger)index {
    NSArray<NSString*>* names = @[@"360p", @"720p", @"1080p", @"4K", @"Safe Area", @"Full Screen"];
    if (index < names.count) {
        return names[index];
    }
    return [self resolutionTitleForIndex:index];
}

- (UIMenu*) resolutionMenu {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    for (NSInteger i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
        // 4K needs an A9 or later, which we judge by HEVC decode support.
        if (i == 3 && !_hevcSupported) {
            continue;
        }

        NSString* title = (i == RESOLUTION_TABLE_CUSTOM_INDEX) ? @"Custom…" : [self resolutionMenuTitleForIndex:i];
        UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction* a) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            if (i == RESOLUTION_TABLE_CUSTOM_INDEX) {
                [strongSelf promptCustomResolutionDialog];
                return;
            }
            strongSelf->_resolutionIndex = i;
            strongSelf->_lastSelectedResolutionIndex = i;
            [strongSelf updateBitrate];
            [strongSelf settingsChanged];
        }];
        action.state = (_resolutionIndex == i) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu menuWithTitle:@"" children:actions];
}

- (UIMenu*) framerateMenu {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    for (NSNumber* fps in (_support120Fps ? @[@30, @60, @120] : @[@30, @60])) {
        UIAction* action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ FPS", fps]
                                               image:nil identifier:nil handler:^(UIAction* a) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf->_framerate = fps.integerValue;
            [strongSelf updateBitrate];
            [strongSelf settingsChanged];
        }];
        action.state = (_framerate == fps.integerValue) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu menuWithTitle:@"" children:actions];
}

- (NSString*) codecTitleForPref:(uint32_t)pref {
    switch (pref) {
        case CODEC_PREF_H264: return @"H.264";
        case CODEC_PREF_HEVC: return @"HEVC";
        case CODEC_PREF_AV1:  return @"AV1";
        default:              return @"Automatic";
    }
}

- (UIMenu*) codecMenu {
    NSMutableArray<NSNumber*>* prefs = [NSMutableArray arrayWithObject:@(CODEC_PREF_H264)];
    if (_hevcSupported) {
        [prefs addObject:@(CODEC_PREF_HEVC)];
    }
    if (_av1Supported) {
        [prefs addObject:@(CODEC_PREF_AV1)];
    }
    [prefs addObject:@(CODEC_PREF_AUTO)];

    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSNumber* pref in prefs) {
        uint32_t value = (uint32_t)pref.unsignedIntValue;
        UIAction* action = [UIAction actionWithTitle:[self codecTitleForPref:value]
                                               image:nil identifier:nil handler:^(UIAction* a) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            strongSelf->_codecPref = value;
            [strongSelf settingsChanged];
        }];
        action.state = (_codecPref == value) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu menuWithTitle:@"" children:actions];
}

- (UIMenu*) indexMenuWithTitles:(NSArray<NSString*>*)titles
                        current:(NSInteger)current
                         setter:(void (^)(NSInteger))setter {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;

    [titles enumerateObjectsUsingBlock:^(NSString* title, NSUInteger index, BOOL* stop) {
        UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction* a) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            setter(index);
            [strongSelf settingsChanged];
        }];
        action.state = (current == (NSInteger)index) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }];

    return [UIMenu menuWithTitle:@"" children:actions];
}

- (UIView*) bitrateRowView {
    UIView* container = [[UIView alloc] init];

    UILabel* caption = [[UILabel alloc] init];
    caption.text = @"Bitrate";
    caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    caption.textColor = [UIColor labelColor];

    _bitrateValueLabel = [[UILabel alloc] init];
    _bitrateValueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
    _bitrateValueLabel.textColor = [UIColor secondaryLabelColor];
    _bitrateValueLabel.textAlignment = NSTextAlignmentRight;

    _bitrateSlider = [[UISlider alloc] init];
    _bitrateSlider.minimumValue = 0;
    _bitrateSlider.maximumValue = (sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1;
    _bitrateSlider.value = [self getSliderValueForBitrate:_bitrate];
    _bitrateSlider.minimumTrackTintColor = [MoonlightTheme accentColor];
    [_bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [_bitrateSlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];

    UIStackView* header = [[UIStackView alloc] initWithArrangedSubviews:@[caption, _bitrateValueLabel]];
    header.axis = UILayoutConstraintAxisHorizontal;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, _bitrateSlider]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:10],
        [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10],
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    ]];

    [self updateBitrateText];
    return container;
}

- (void) rebuildRows {
    __weak typeof(self) weakSelf = self;

    _resolutionButton = [self menuButtonWithTitle:[self resolutionTitleForIndex:_resolutionIndex] menu:[self resolutionMenu]];
    _framerateButton = [self menuButtonWithTitle:[NSString stringWithFormat:@"%ld FPS", (long)_framerate] menu:[self framerateMenu]];
    _codecButton = [self menuButtonWithTitle:[self codecTitleForPref:_codecPref] menu:[self codecMenu]];

    NSArray<NSString*>* controlTitles = @[@"Off", @"Auto", @"Simple", @"Full"];
    _onscreenControlsButton = [self menuButtonWithTitle:controlTitles[_onscreenControls]
                                                   menu:[self indexMenuWithTitles:controlTitles
                                                                          current:_onscreenControls
                                                                           setter:^(NSInteger index) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf->_onscreenControls = index;
    }]];
    // On-screen controls are meaningless when touch acts as a touchscreen.
    _onscreenControlsButton.enabled = !_absoluteTouchMode;

    NSArray<NSString*>* pacingTitles = @[@"Lowest Latency", @"Smoothest Video"];
    _framePacingButton = [self menuButtonWithTitle:pacingTitles[_useFramePacing ? 1 : 0]
                                              menu:[self indexMenuWithTitles:pacingTitles
                                                                     current:(_useFramePacing ? 1 : 0)
                                                                      setter:^(NSInteger index) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        strongSelf->_useFramePacing = (index == 1);
    }]];

    _touchModeControl = [[UISegmentedControl alloc] initWithItems:@[@"Touchpad", @"Touchscreen"]];
    _touchModeControl.selectedSegmentIndex = _absoluteTouchMode ? 1 : 0;
    _touchModeControl.selectedSegmentTintColor = [MoonlightTheme accentColor];
    [_touchModeControl addTarget:self action:@selector(touchModeChanged) forControlEvents:UIControlEventValueChanged];

    MoonlightSettingsRow* bitrateRow = [[MoonlightSettingsRow alloc] init];
    bitrateRow.custom = [self bitrateRowView];

    MoonlightSettingsRow* hdrRow;
    if (_hdrSupported) {
        hdrRow = [self rowWithTitle:@"HDR" accessory:[self switchForValue:_enableHdr action:@selector(hdrChanged:)]];
    }
    else {
        hdrRow = [self rowWithTitle:@"HDR" accessory:nil];
        hdrRow.subtitle = @"Unsupported on this device";
    }

    MoonlightSettingsRow* setupGuide = [self rowWithTitle:@"Setup Guide" accessory:nil];
    setupGuide.action = ^{
        [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"];
    };

    MoonlightSettingsRow* troubleshooting = [self rowWithTitle:@"Troubleshooting" accessory:nil];
    troubleshooting.action = ^{
        [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"];
    };

    MoonlightSettingsRow* version = [self rowWithTitle:@"Version" accessory:nil];
    version.subtitle = [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"];

    _sectionTitles = @[@"Video", @"Audio", @"Input", @"Advanced", @"About"];
    _rows = @[
        @[
            [self rowWithTitle:@"Resolution" accessory:_resolutionButton],
            [self rowWithTitle:@"Frame Rate" accessory:_framerateButton],
            bitrateRow,
            hdrRow,
            [self rowWithTitle:@"Codec" accessory:_codecButton],
            [self rowWithTitle:@"Optimize Game Settings" accessory:[self switchForValue:_optimizeGames action:@selector(optimizeChanged:)]],
        ],
        @[
            [self rowWithTitle:@"Play Audio on PC" accessory:[self switchForValue:_audioOnPC action:@selector(audioOnPCChanged:)]],
        ],
        @[
            [self rowWithTitle:@"Touch Mode" accessory:_touchModeControl],
            [self rowWithTitle:@"On-Screen Controls" accessory:_onscreenControlsButton],
            [self rowWithTitle:@"Multi-Controller" accessory:[self switchForValue:_multiController action:@selector(multiControllerChanged:)]],
            [self rowWithTitle:@"Swap A/B and X/Y" accessory:[self switchForValue:_swapABXYButtons action:@selector(swapABXYChanged:)]],
            [self rowWithTitle:@"Citrix X1 Mouse" accessory:[self switchForValue:_btMouseSupport action:@selector(btMouseChanged:)]],
        ],
        @[
            [self rowWithTitle:@"Frame Pacing" accessory:_framePacingButton],
            [self rowWithTitle:@"Statistics Overlay" accessory:[self switchForValue:_statsOverlay action:@selector(statsOverlayChanged:)]],
        ],
        @[version, setupGuide, troubleshooting],
    ];

    [_tableView reloadData];
}

// Persist immediately. The old code only saved when the reveal drawer finished
// closing, which made correctness depend on animation timing.
- (void) settingsChanged {
    [self saveSettings];
    [self rebuildRows];
}

- (void) hdrChanged:(UISwitch*)sender          { _enableHdr = sender.isOn;       [self settingsChanged]; }
- (void) optimizeChanged:(UISwitch*)sender     { _optimizeGames = sender.isOn;   [self settingsChanged]; }
- (void) audioOnPCChanged:(UISwitch*)sender    { _audioOnPC = sender.isOn;       [self settingsChanged]; }
- (void) multiControllerChanged:(UISwitch*)sender { _multiController = sender.isOn; [self settingsChanged]; }
- (void) swapABXYChanged:(UISwitch*)sender     { _swapABXYButtons = sender.isOn; [self settingsChanged]; }
- (void) btMouseChanged:(UISwitch*)sender      { _btMouseSupport = sender.isOn;  [self settingsChanged]; }
- (void) statsOverlayChanged:(UISwitch*)sender { _statsOverlay = sender.isOn;    [self settingsChanged]; }

- (void) touchModeChanged {
    _absoluteTouchMode = (_touchModeControl.selectedSegmentIndex == 1);
    [self settingsChanged];
}

- (void) updateBitrate {
    NSInteger fps = [self getChosenFrameRate];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger defaultBitrate;

    // This logic is shamelessly stolen from Moonlight Qt:
    // https://github.com/moonlight-stream/moonlight-qt/blob/master/app/settings/streamingpreferences.cpp

    // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
    // bitrate increase for frame rate once we get to values that high.
    float frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60.f) * 60.f)) / 30.f;

    // TODO: Collect some empirical data to see if these defaults make sense.
    // We're just using the values that the Shield used, as we have for years.
    struct {
        NSInteger pixels;
        int factor;
    } resTable[] = {
        { 640 * 360, 1 },
        { 854 * 480, 2 },
        { 1280 * 720, 5 },
        { 1920 * 1080, 10 },
        { 2560 * 1440, 20 },
        { 3840 * 2160, 40 },
        { -1, -1 }
    };

    // Calculate the resolution factor by linear interpolation of the resolution table
    float resolutionFactor;
    NSInteger pixels = width * height;
    for (int i = 0;; i++) {
        if (pixels == resTable[i].pixels) {
            // We can bail immediately for exact matches
            resolutionFactor = resTable[i].factor;
            break;
        }
        else if (pixels < resTable[i].pixels) {
            if (i == 0) {
                // Never go below the lowest resolution entry
                resolutionFactor = resTable[i].factor;
            }
            else {
                // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                resolutionFactor = ((float)(pixels - resTable[i-1].pixels) / (resTable[i].pixels - resTable[i-1].pixels)) * (resTable[i].factor - resTable[i-1].factor) + resTable[i-1].factor;
            }
            break;
        }
        else if (resTable[i].pixels == -1) {
            // Never go above the highest resolution entry
            resolutionFactor = resTable[i-1].factor;
            break;
        }
    }

    defaultBitrate = round(resolutionFactor * frameRateFactor) * 1000;
    // Snap to a real slider notch now, not just at load time — otherwise an
    // arbitrary capped value (e.g. 52000) gets persisted, and reloading it
    // through getSliderValueForBitrate: (which rounds up to the next notch,
    // 60000) makes the bitrate ratchet upward on every Settings reopen.
    _bitrate = bitrateTable[[self getSliderValueForBitrate:MIN(defaultBitrate, 100000)]];
    _bitrateSlider.value = [self getSliderValueForBitrate:_bitrate];

    [self updateBitrateText];
}

- (void) promptCustomResolutionDialog {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter Custom Resolution" message:nil preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Width";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;

        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width];
        }
    }];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Height";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;

        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height];
        }
    }];

    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray * textfields = alertController.textFields;
        UITextField *widthField = textfields[0];
        UITextField *heightField = textfields[1];

        long width = [widthField.text integerValue];
        long height = [heightField.text integerValue];
        if (width <= 0 || height <= 0) {
            // Restore the previous selection
            self->_resolutionIndex = self->_lastSelectedResolutionIndex;
            [self rebuildRows];
            return;
        }

        // H.264 maximum
        int maxResolutionDimension = 4096;
        if (@available(iOS 11.0, tvOS 11.0, *)) {
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                // HEVC maximum
                maxResolutionDimension = 8192;
            }
        }

        // Cap to maximum valid dimensions
        width = MIN(width, maxResolutionDimension);
        height = MIN(height, maxResolutionDimension);

        // Cap to minimum valid dimensions
        width = MAX(width, 256);
        height = MAX(height, 256);

        resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX] = CGSizeMake(width, height);
        // _resolutionIndex must point at the custom entry before updateBitrate reads
        // getChosenStreamWidth/Height, or the default bitrate is computed against the
        // previously-selected resolution instead of the one just entered. (In the old
        // segmented-control code this was implicit: the control's selection was already
        // on the custom segment by the time this handler ran.)
        self->_resolutionIndex = RESOLUTION_TABLE_CUSTOM_INDEX;
        self->_lastSelectedResolutionIndex = RESOLUTION_TABLE_CUSTOM_INDEX;
        [self updateBitrate];
        [self settingsChanged];

        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Custom Resolution Selected" message: @"Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        // Restore the previous selection
        self->_resolutionIndex = self->_lastSelectedResolutionIndex;
        [self rebuildRows];
    }]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void) bitrateSliderMoved {
    assert(_bitrateSlider.value < (sizeof(bitrateTable) / sizeof(*bitrateTable)));
    _bitrate = bitrateTable[(int)_bitrateSlider.value];
    [self updateBitrateText];
}

- (void) updateBitrateText {
    _bitrateValueLabel.text = [NSString stringWithFormat:@"%.1f Mbps", _bitrate / 1000.];
}

- (NSInteger) getChosenFrameRate {
    return _framerate;
}

- (uint32_t) getChosenCodecPreference {
    return _codecPref;
}

- (NSInteger) getChosenStreamHeight {
    return resolutionTable[_resolutionIndex].height;
}

- (NSInteger) getChosenStreamWidth {
    return resolutionTable[_resolutionIndex].width;
}

- (void) saveSettings {
    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan saveSettingsWithBitrate:_bitrate
                           framerate:[self getChosenFrameRate]
                              height:[self getChosenStreamHeight]
                               width:[self getChosenStreamWidth]
                         audioConfig:2 // Stereo
                    onscreenControls:_onscreenControls
                       optimizeGames:_optimizeGames
                     multiController:_multiController
                     swapABXYButtons:_swapABXYButtons
                           audioOnPC:_audioOnPC
                      preferredCodec:_codecPref
                      useFramePacing:_useFramePacing
                           enableHdr:_enableHdr
                      btMouseSupport:_btMouseSupport
                   absoluteTouchMode:_absoluteTouchMode
                        statsOverlay:_statsOverlay];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
}


#pragma mark - UITableViewDataSource / UITableViewDelegate

- (NSInteger) numberOfSectionsInTableView:(UITableView*)tableView {
    return _rows.count;
}

- (NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return _rows[section].count;
}

- (NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
    return _sectionTitles[section];
}

- (UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    MoonlightSettingsRow* row = _rows[indexPath.section][indexPath.row];

    // Custom rows and configuration rows use separate reuse identifiers. Reusing
    // one as the other means clearing contentView, which destroys the
    // UIListContentView UIKit installs for a contentConfiguration and leaves the
    // row blank.
    if (row.custom != nil) {
        UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"customRow" forIndexPath:indexPath];
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        // A reused "customRow" cell may still hold a *previous* row's custom
        // view (e.g. an earlier bitrateRowView instance from before
        // rebuildRows rebuilt it). Strip anything that isn't the current
        // row's view. This is safe here — and only here — because the
        // "customRow" identifier is never used for a contentConfiguration
        // cell, so there's no UIListContentView to destroy.
        for (UIView* subview in [cell.contentView.subviews copy]) {
            if (subview != row.custom) {
                [subview removeFromSuperview];
            }
        }

        if (row.custom.superview != cell.contentView) {
            [row.custom removeFromSuperview];
            row.custom.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:row.custom];
            [NSLayoutConstraint activateConstraints:@[
                [row.custom.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                [row.custom.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
                [row.custom.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                [row.custom.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            ]];
        }
        return cell;
    }

    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];

    UIListContentConfiguration* content = [UIListContentConfiguration valueCellConfiguration];
    content.text = row.title;
    content.secondaryText = row.subtitle;
    cell.contentConfiguration = content;
    cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;

    // Defensive: any accessory that still has no frame gets sized here.
    UIView* accessory = row.accessory;
    if (accessory != nil && CGRectIsEmpty(accessory.frame)) {
        accessory.frame = (CGRect){CGPointZero, [accessory systemLayoutSizeFittingSize:UILayoutFittingCompressedSize]};
    }
    cell.accessoryView = accessory;

    return cell;
}

- (void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MoonlightSettingsRow* row = _rows[indexPath.section][indexPath.row];
    if (row.action) {
        row.action();
    }
}

@end
