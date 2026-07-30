//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

@import AVFoundation;

#import "StreamView.h"
#include <Limelight.h>
#import "DataManager.h"
#import "ControllerSupport.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"
#import "AbsoluteTouchHandler.h"
#import "KeyboardInputField.h"
#import "Utils.h"

static const double X1_MOUSE_SPEED_DIVISOR = 2.5;

@implementation StreamView {
    OnScreenControls* onScreenControls;
    
    KeyboardInputField* keyInputField;
    BOOL isInputingText;
    NSMutableSet* keysDown;
    
    float streamAspectRatio;
    
    // iOS 13.4 mouse support
    NSInteger lastMouseButtonMask;
    float lastMouseX;
    float lastMouseY;
    CGPoint lastScrollTranslation;
    
    // Citrix X1 mouse support
    X1Mouse* x1mouse;
    double accumulatedMouseDeltaX;
    double accumulatedMouseDeltaY;
    
    UIResponder* touchHandler;
    
    id<UserInteractionDelegate> interactionDelegate;
    NSTimer* interactionTimer;
    BOOL hasUserInteracted;
    
    NSDictionary<NSString *, NSNumber *> *dictCodes;
}

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                  config:(StreamConfiguration*)streamConfig {
    self->interactionDelegate = interactionDelegate;
    self->streamAspectRatio = (float)streamConfig.width / (float)streamConfig.height;
    
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    
    keysDown = [[NSMutableSet alloc] init];
    keyInputField = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    [keyInputField setKeyboardType:UIKeyboardTypeDefault];
    [keyInputField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [keyInputField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyInputField setSpellCheckingType:UITextSpellCheckingTypeNo];
    [self addSubview:keyInputField];
    
#if TARGET_OS_TV
    // tvOS requires RelativeTouchHandler to manage Apple Remote input
    self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
#else
    // iOS uses RelativeTouchHandler or AbsoluteTouchHandler depending on user preference
    if (settings.absoluteTouchMode) {
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self];
    }
    else {
        self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
    }
    
    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (settings.absoluteTouchMode) {
        Log(LOG_I, @"On-screen controls disabled in absolute touch mode");
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
    
    // It would be nice to just use GCMouse on iOS 14+ and the older API on iOS 13
    // but unfortunately that isn't possible today. GCMouse doesn't recognize many
    // mice correctly, but UIKit does. We will register for both and ignore UIKit
    // events if a GCMouse is connected.
    if (@available(iOS 13.4, *)) {
        [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
        
        UIPanGestureRecognizer *discreteMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedDiscrete:)];
        discreteMouseWheelRecognizer.maximumNumberOfTouches = 0;
        discreteMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
        discreteMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:discreteMouseWheelRecognizer];
        
        UIPanGestureRecognizer *continuousMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedContinuous:)];
        continuousMouseWheelRecognizer.maximumNumberOfTouches = 0;
        continuousMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
        continuousMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:continuousMouseWheelRecognizer];
    }
    
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        UIHoverGestureRecognizer *stylusHoverRecognizer = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(sendStylusHoverEvent:)];
        stylusHoverRecognizer.allowedTouchTypes = @[@(UITouchTypePencil)];
        [self addGestureRecognizer:stylusHoverRecognizer];
    }
#endif
#endif
    
    x1mouse = [[X1Mouse alloc] init];
    x1mouse.delegate = self;
    
    if (settings.btMouseSupport) {
        [x1mouse start];
    }
    
    // This is critical to ensure keyboard events are delivered to this
    // StreamView and not our parent UIView, especially on tvOS.
    [self becomeFirstResponder];
}

- (void)startInteractionTimer {
    // Restart user interaction tracking
    hasUserInteracted = NO;
    
    BOOL timerAlreadyRunning = interactionTimer != nil;
    
    // Start/restart the timer
    [interactionTimer invalidate];
    interactionTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                        target:self
                        selector:@selector(interactionTimerExpired:)
                        userInfo:nil
                        repeats:NO];
    
    // Notify the delegate if this was a new user interaction
    if (!timerAlreadyRunning) {
        [interactionDelegate userInteractionBegan];
    }
}

- (void)interactionTimerExpired:(NSTimer *)timer {
    if (!hasUserInteracted) {
        // User has finished touching the screen
        interactionTimer = nil;
        [interactionDelegate userInteractionEnded];
    }
    else {
        // User is still touching the screen. Restart the timer.
        [self startInteractionTimer];
    }
}

- (void) showOnScreenControls {
#if !TARGET_OS_TV
    [onScreenControls show];
#endif
}

- (OnScreenControlsLevel) getCurrentOscState {
    if (onScreenControls == nil) {
        return OnScreenControlsLevelOff;
    }
    else {
        return [onScreenControls getLevel];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // VideoDecoderRenderer sizes its AVSampleBufferDisplayLayer once, at setup,
    // from our bounds at that moment. CALayer sublayers don't autoresize, so any
    // later bounds change — rotation, or the forced switch to landscape when a
    // stream starts in portrait — leaves the video off-centre. The renderer is a
    // static inside Connection.m and isn't reachable from here, but the layer is
    // our own sublayer, so re-apply its own sizing rule.
    //
    // ponytail: searches sublayers by class because the renderer isn't reachable
    // from here; the tidier fix is for VideoDecoderRenderer to expose a re-layout
    // method once something owns a reference to it.
    if (streamAspectRatio <= 0) {
        return;
    }

    for (CALayer* layer in self.layer.sublayers) {
        if (![layer isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
            continue;
        }

        CGSize videoSize = [self getVideoAreaSize];

        // No implicit animation — the layer would visibly slide into place on
        // every rotation.
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        layer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
        layer.bounds = CGRectMake(0, 0, videoSize.width, videoSize.height);
        [CATransaction commit];
    }
}

- (CGSize) getVideoAreaSize {
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        return CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        return CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
}

- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point {
    // These are now relative to the StreamView, however we need to scale them
    // further to make them relative to the actual video portion.
    float x = point.x - self.bounds.origin.x;
    float y = point.y - self.bounds.origin.y;
    
    // For some reason, we don't seem to always get to the bounds of the window
    // so we'll subtract 1 pixel if we're to the left/below of the origin and
    // and add 1 pixel if we're to the right/above. It should be imperceptible
    // to the user but it will allow activation of gestures that require contact
    // with the edge of the screen (like Aero Snap).
    if (x < self.bounds.size.width / 2) {
        x--;
    }
    else {
        x++;
    }
    if (y < self.bounds.size.height / 2) {
        y--;
    }
    else {
        y++;
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize = [self getVideoAreaSize];
    CGPoint videoOrigin = CGPointMake(self.bounds.size.width / 2 - videoSize.width / 2,
                                      self.bounds.size.height / 2 - videoSize.height / 2);
    
    // Confine the cursor to the video region. We don't just discard events outside
    // the region because we won't always get one exactly when the mouse leaves the region.
    return CGPointMake(MIN(MAX(x, videoOrigin.x), videoOrigin.x + videoSize.width) - videoOrigin.x,
                       MIN(MAX(y, videoOrigin.y), videoOrigin.y + videoSize.height) - videoOrigin.y);
}

#if !TARGET_OS_TV

- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle {
    // iOS reports azimuth of 0 when the stylus is pointing west, but Moonlight expects
    // rotation of 0 to mean the stylus is pointing north. Rotate the azimuth angle
    // clockwise by 90 degrees to convert from iOS to Moonlight rotation conventions.
    int32_t rotationAngle = (azimuthAngle - M_PI_2) * (180.f / M_PI);
    if (rotationAngle < 0) {
        rotationAngle += 360;
    }
    return (uint16_t)rotationAngle;
}

- (uint8_t)getTiltFromAltitudeAngle:(float)altitudeAngle {
    // iOS reports an altitude of 0 when the stylus is parallel to the touch surface,
    // while Moonlight expects a tilt of 0 when the stylus is perpendicular to the surface.
    // Subtract the tilt angle from 90 to convert from iOS to Moonlight tilt conventions.
    uint8_t altitudeDegs = abs((int16_t)(altitudeAngle * (180.f / M_PI)));
    return 90 - MIN(90, altitudeDegs);
}

- (BOOL)sendStylusEvent:(UITouch*)event {
    uint8_t type;
    
    // Don't touch stylus events if the host doesn't support them. We want to pass
    // them as normal touches for legacy hosts that don't understand pen events.
    if (!(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    
    switch (event.phase) {
        case UITouchPhaseBegan:
            type = LI_TOUCH_EVENT_DOWN;
            break;
        case UITouchPhaseMoved:
            type = LI_TOUCH_EVENT_MOVE;
            break;
        case UITouchPhaseEnded:
            type = LI_TOUCH_EVENT_UP;
            break;
        case UITouchPhaseCancelled:
            type = LI_TOUCH_EVENT_CANCEL;
            break;
        default:
            return YES;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[event locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    return LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                          (event.force / event.maximumPossibleForce) / sin(event.altitudeAngle),
                          0.0f, 0.0f,
                          [self getRotationFromAzimuthAngle:[event azimuthAngleInView:self]],
                          [self getTiltFromAltitudeAngle:event.altitudeAngle]) != LI_ERR_UNSUPPORTED;
}

- (void)sendStylusHoverEvent:(UIHoverGestureRecognizer*)gesture API_AVAILABLE(ios(13.0)) {
    uint8_t type;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            type = LI_TOUCH_EVENT_HOVER;
            break;

        case UIGestureRecognizerStateEnded:
            type = LI_TOUCH_EVENT_HOVER_LEAVE;
            break;

        default:
            return;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[gesture locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    float distance = 0.0f;
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        distance = gesture.zOffset;
    }
#endif
    
    uint16_t rotationAngle = LI_ROT_UNKNOWN;
    uint8_t tiltAngle = LI_TILT_UNKNOWN;
#if defined(__IPHONE_16_4) || defined(__TVOS_16_4)
    if (@available(iOS 16.4, *)) {
        rotationAngle = [self getRotationFromAzimuthAngle:[gesture azimuthAngleInView:self]];
        tiltAngle = [self getTiltFromAltitudeAngle:gesture.altitudeAngle];
    }
#endif
    
    LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                   distance, 0.0f, 0.0f, rotationAngle, tiltAngle);
}

#endif

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_PRESS
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch down");
    
    // Notify of user interaction and start expiration timer
    [self startInteractionTimer];
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchDownEvent:touches]) {
        // We still inform the touch handler even if we're going trigger the
        // keyboard activation gesture. This is important to ensure the touch
        // handler has a consistent view of touch events to correctly suppress
        // activation of one or two finger gestures when a three finger gesture
        // is triggered.
        [touchHandler touchesBegan:touches withEvent:event];
        
        if ([[event allTouches] count] == 3) {
            if (isInputingText) {
                Log(LOG_D, @"Closing the keyboard");
                [keyInputField resignFirstResponder];
                isInputingText = false;
            } else {
                Log(LOG_D, @"Opening the keyboard");
                // Prepare the textbox used to capture keyboard events.
                keyInputField.delegate = self;
                keyInputField.text = @"0";
#if !TARGET_OS_TV
                // Prepare the two-row scrollable accessory above the keyboard for more options.
                // Rebuilt from scratch on every keyboard open, so button "isOn" state (set via
                // objc_setAssociatedObject below) always starts fresh/off here -- see
                // textFieldDidEndEditing: for why that's safe (it releases any held keysDown
                // when the keyboard closes, so host-side state and this fresh "off" agree).
                keyInputField.inputAccessoryView = [self buildKeyboardAccessoryView];
#endif
                [keyInputField becomeFirstResponder];
                [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
                
                // Undo causes issues for our state management, so turn it off
                [keyInputField.undoManager disableUndoRegistration];
                
                isInputingText = true;
            }
        }
    }
}

// Builds the two-row scrollable keyboard accessory: row 1 is modifiers/navigation,
// row 2 is the function keys. Each row is an independently-scrolling UIScrollView so
// keys can never clip off screen regardless of orientation or key count (the old
// UIToolbar-based bar clipped its first/last items under the iOS 26 Liquid Glass
// toolbar layout).
- (UIView *)buildKeyboardAccessoryView {
    const CGFloat rowHeight = 44.0;
    const CGFloat rowGap = 4.0;
    const CGFloat topPadding = 4.0;
    const CGFloat totalHeight = topPadding + rowHeight + rowGap + rowHeight;

    UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, totalHeight)];
    accessory.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    accessory.backgroundColor = [UIColor clearColor];

    NSArray<UIButton *> *row1 = @[
        [self createKeyButtonWithTitle:nil symbolName:@"keyboard.chevron.compact.down" keyCode:0x00 isToggleable:NO],
        [self createKeyButtonWithTitle:@"Win" symbolName:nil keyCode:0x5B isToggleable:YES],
        [self createKeyButtonWithTitle:@"Esc" symbolName:nil keyCode:0x1B isToggleable:NO],
        [self createKeyButtonWithTitle:@"Tab" symbolName:nil keyCode:0x09 isToggleable:NO],
        [self createKeyButtonWithTitle:@"⇧ L" symbolName:nil keyCode:0xA0 isToggleable:YES],
        [self createKeyButtonWithTitle:@"⇧ R" symbolName:nil keyCode:0xA1 isToggleable:YES],
        [self createKeyButtonWithTitle:@"Ctrl" symbolName:nil keyCode:0xA2 isToggleable:YES],
        [self createKeyButtonWithTitle:@"Alt" symbolName:nil keyCode:0xA4 isToggleable:YES],
        [self createKeyButtonWithTitle:@"Del" symbolName:nil keyCode:0x2E isToggleable:NO],
        [self createKeyButtonWithTitle:nil symbolName:@"arrow.left" keyCode:0x25 isToggleable:NO],
        [self createKeyButtonWithTitle:nil symbolName:@"arrow.up" keyCode:0x26 isToggleable:NO],
        [self createKeyButtonWithTitle:nil symbolName:@"arrow.down" keyCode:0x28 isToggleable:NO],
        [self createKeyButtonWithTitle:nil symbolName:@"arrow.right" keyCode:0x27 isToggleable:NO],
    ];

    NSMutableArray<UIButton *> *row2 = [NSMutableArray arrayWithCapacity:12];
    for (NSInteger i = 0; i < 12; i++) {
        NSString *title = [NSString stringWithFormat:@"F%ld", (long)(i + 1)];
        [row2 addObject:[self createKeyButtonWithTitle:title symbolName:nil keyCode:(0x70 + i) isToggleable:NO]];
    }

    UIScrollView *row1Scroll = [self buildScrollRowWithButtons:row1];
    UIScrollView *row2Scroll = [self buildScrollRowWithButtons:row2];
    row1Scroll.translatesAutoresizingMaskIntoConstraints = NO;
    row2Scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [accessory addSubview:row1Scroll];
    [accessory addSubview:row2Scroll];

    [NSLayoutConstraint activateConstraints:@[
        [row1Scroll.topAnchor constraintEqualToAnchor:accessory.topAnchor constant:topPadding],
        [row1Scroll.leadingAnchor constraintEqualToAnchor:accessory.leadingAnchor],
        [row1Scroll.trailingAnchor constraintEqualToAnchor:accessory.trailingAnchor],
        [row1Scroll.heightAnchor constraintEqualToConstant:rowHeight],

        [row2Scroll.topAnchor constraintEqualToAnchor:row1Scroll.bottomAnchor constant:rowGap],
        [row2Scroll.leadingAnchor constraintEqualToAnchor:accessory.leadingAnchor],
        [row2Scroll.trailingAnchor constraintEqualToAnchor:accessory.trailingAnchor],
        [row2Scroll.heightAnchor constraintEqualToConstant:rowHeight],
    ]];

    return accessory;
}

// Wraps a row of key buttons in a horizontally-scrolling, non-clipping UIScrollView.
// Horizontal content insets respect the view's safe area so keys never land under a
// notch/Dynamic Island in landscape.
- (UIScrollView *)buildScrollRowWithButtons:(NSArray<UIButton *> *)buttons {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentFill;
    stack.distribution = UIStackViewDistributionEqualSpacing;
    stack.spacing = 8.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIButton *button in buttons) {
        [stack addArrangedSubview:button];
    }

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.showsHorizontalScrollIndicator = NO;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.alwaysBounceHorizontal = YES;
    [scroll addSubview:stack];

    CGFloat leftInset = MAX(self.safeAreaInsets.left, 8.0);
    CGFloat rightInset = MAX(self.safeAreaInsets.right, 8.0);
    scroll.contentInset = UIEdgeInsetsMake(0, leftInset, 0, rightInset);

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
    ]];

    return scroll;
}

// Builds one key button. Pass either a title (text key) or an SF Symbol name (Done/arrows),
// never both. Uses a UIButtonConfiguration instead of colouring imageView/imageEdgeInsets --
// that old approach is what broke under the iOS 26 Liquid Glass toolbar layout.
- (UIButton *)createKeyButtonWithTitle:(NSString *)title symbolName:(NSString *)symbolName keyCode:(NSInteger)keyCode isToggleable:(BOOL)isToggleable {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration grayButtonConfiguration];
    config.contentInsets = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);

    if (symbolName) {
        config.image = [UIImage systemImageNamed:symbolName];
    } else {
        // Monospaced digits keep F1 and F12 at consistent widths.
        UIFont *font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
        config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: font}];
    }

    button.configuration = config;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    [button addTarget:self action:@selector(toolbarButtonClicked:) forControlEvents:UIControlEventTouchUpInside];

    objc_setAssociatedObject(button, "keyCode", @(keyCode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isToggleable", @(isToggleable), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isOn", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return button;
}

- (void)toolbarButtonClicked:(UIButton *)sender {
    BOOL isToggleable = [objc_getAssociatedObject(sender, "isToggleable") boolValue];
    BOOL isOn = [objc_getAssociatedObject(sender, "isOn") boolValue];
    if (isToggleable){
        isOn = !isOn;
        // Update the button's appearance based on its new state. (Buttons are now built
        // with a UIButtonConfiguration -- see createKeyButtonWithTitle:symbolName:keyCode:isToggleable:
        // -- so the on/off colour is set via the configuration rather than imageView.backgroundColor.)
#if !TARGET_OS_TV
        UIButtonConfiguration *config = sender.configuration;
        config.baseBackgroundColor = isOn ? [MoonlightTheme accentColor] : nil;
        sender.configuration = config;
#endif
    }
    // Update the new on/off state of the button
    objc_setAssociatedObject(sender, "isOn", @(isOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Get the keyCode parameter and convert to short for key press event
    short keyCode = [objc_getAssociatedObject(sender, "keyCode") shortValue];
    // Close keyboard if done button clicked
    if (!keyCode) {
        [keyInputField resignFirstResponder];
        isInputingText = false;
    }
    else {
        // Send key press event using keyCode parameter, toggle if necessary
        if (isToggleable){
            if (isOn){
                LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
                [keysDown addObject:@(keyCode)];
            } else {
                LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
                [keysDown removeObject:@(keyCode)];
            }
        }
        else {
            LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
        }
    }
}

- (BOOL)handleMouseButtonEvent:(int)buttonAction forTouches:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        UITouch* touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return YES;
                }
            }
            
            UIEventButtonMask normalizedButtonMask;
            
            // iOS 14 includes the released button in the buttonMask for the release
            // event, while iOS 13 does not. Normalize that behavior here.
            if (@available(iOS 14.0, *)) {
                if (buttonAction == BUTTON_ACTION_RELEASE) {
                    normalizedButtonMask = lastMouseButtonMask & ~event.buttonMask;
                }
                else {
                    normalizedButtonMask = event.buttonMask;
                }
            }
            else {
                normalizedButtonMask = event.buttonMask;
            }
            
            UIEventButtonMask changedButtons = lastMouseButtonMask ^ normalizedButtonMask;
                        
            for (int i = BUTTON_LEFT; i <= BUTTON_X2; i++) {
                UIEventButtonMask buttonFlag;
                
                switch (i) {
                    // Right and Middle are reversed from what iOS uses
                    case BUTTON_RIGHT:
                        buttonFlag = UIEventButtonMaskForButtonNumber(2);
                        break;
                    case BUTTON_MIDDLE:
                        buttonFlag = UIEventButtonMaskForButtonNumber(3);
                        break;
                        
                    default:
                        buttonFlag = UIEventButtonMaskForButtonNumber(i);
                        break;
                }
                
                if (changedButtons & buttonFlag) {
                    LiSendMouseButtonEvent(buttonAction, i);
                }
            }
            
            lastMouseButtonMask = normalizedButtonMask;
            return YES;
        }
    }
#endif
    
    return NO;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
        
        UITouch *touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return;
                }
            }
            
            // We must handle this event to properly support
            // drags while the middle, X1, or X2 mouse buttons are
            // held down. For some reason, left and right buttons
            // don't require this, but we do it anyway for them too.
            // Cursor movement without a button held down is handled
            // in pointerInteraction:regionForRequest:defaultRegion.
            [self updateCursorLocation:[touch locationInView:self] isMouse:YES];
            return;
        }
    }
#endif
    
    hasUserInteracted = YES;
    
    if (![onScreenControls handleTouchMovedEvent:touches]) {
        [touchHandler touchesMoved:touches withEvent:event];
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:YES]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch up");
    
    hasUserInteracted = YES;
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchUpEvent:touches]) {
        [touchHandler touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [touchHandler touchesCancelled:touches withEvent:event];
    [self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                      forTouches:touches
                       withEvent:event];
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                [self sendStylusEvent:touch];
            }
        }
    }
#endif
}

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {
    CGPoint normalizedLocation = [self adjustCoordinatesForVideoArea:location];
    CGSize videoSize = [self getVideoAreaSize];
    
    // Send the mouse position relative to the video region if it has changed
    // if we're receiving coordinates from a real mouse.
    //
    // NB: It is important for functionality (not just optimization) to only
    // send it if the value has changed. We will receive one of these events
    // any time the user presses a modifier key, which can result in errant
    // mouse motion when using a Citrix X1 mouse.
    if (normalizedLocation.x != lastMouseX || normalizedLocation.y != lastMouseY || !isMouse) {
        if (lastMouseX != 0 || lastMouseY != 0 || !isMouse) {
            LiSendMousePositionEvent(normalizedLocation.x, normalizedLocation.y, videoSize.width, videoSize.height);
        }
        
        if (isMouse) {
            lastMouseX = normalizedLocation.x;
            lastMouseY = normalizedLocation.y;
        }
    }
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    if (@available(iOS 14.0, *)) {
        if ([GCMouse current] != nil) {
            // We'll handle this with GCMouse. Do nothing here.
            return nil;
        }
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGSize videoSize;
    CGPoint videoOrigin;
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        videoSize = CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        videoSize = CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
    videoOrigin = CGPointMake(self.bounds.size.width / 2 - videoSize.width / 2,
                              self.bounds.size.height / 2 - videoSize.height / 2);
    
    // Move the cursor on the host if no buttons are pressed.
    // Motion with buttons pressed in handled in touchesMoved:
    if (lastMouseButtonMask == 0) {
        [self updateCursorLocation:request.location isMouse:YES];
    }
    
    // The pointer interaction should cover the video region only
    return [UIPointerRegion regionWithRect:CGRectMake(videoOrigin.x, videoOrigin.y, videoSize.width, videoSize.height) identifier:nil];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region  API_AVAILABLE(ios(13.4)) {
    // Always hide the mouse cursor over our stream view
    return [UIPointerStyle hiddenPointerStyle];
}

- (void)mouseWheelMovedContinuous:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    const short translationMultiplier = 120 * 20; // WHEEL_DELTA * 20
    
    {
        short translationDeltaY = ((currentScrollTranslation.y - lastScrollTranslation.y) / self.bounds.size.height) * translationMultiplier;
        if (translationDeltaY != 0) {
            LiSendHighResScrollEvent(translationDeltaY);
            lastScrollTranslation = currentScrollTranslation;
        }
    }

    {
        short translationDeltaX = ((currentScrollTranslation.x - lastScrollTranslation.x) / self.bounds.size.width) * translationMultiplier;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-translationDeltaX);
            lastScrollTranslation = currentScrollTranslation;
        }
    }
}

- (void)mouseWheelMovedDiscrete:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    // Using velocityInView is 0 for discrete scroll events
    // when scrolling very slowly, but translationInView does work.
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    
    {
        short translationDeltaY = currentScrollTranslation.y - lastScrollTranslation.y;
        if (translationDeltaY != 0) {
            LiSendScrollEvent(translationDeltaY > 0 ? 1 : -1);
        }
    }

    {
        short translationDeltaX = currentScrollTranslation.x - lastScrollTranslation.x;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHScrollEvent(translationDeltaX < 0 ? 1 : -1);
        }
    }
    
    lastScrollTranslation = currentScrollTranslation;
}

#endif

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (@available(iOS 13.0, *)) {
        // Disable the 3 finger tap gestures that trigger the copy/paste/undo toolbar on iOS 13+
        return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
    }
    else {
        return YES;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    // This method is called when the "Return" key is pressed.
    LiSendKeyboardEvent(0x0d, KEY_ACTION_DOWN, 0);
    usleep(50 * 1000);
    LiSendKeyboardEvent(0x0d, KEY_ACTION_UP, 0);
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    for (NSNumber* keyCode in keysDown) {
        LiSendKeyboardEvent([keyCode shortValue], KEY_ACTION_UP, 0);
    }
    [keysDown removeAllObjects];
}

- (void)onKeyboardPressed:(UITextField *)textField {
    NSString* inputText = textField.text;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // If the text became empty, we know the user pressed the backspace key.
        if ([inputText isEqual:@""]) {
            LiSendKeyboardEvent(0x08, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(0x08, KEY_ACTION_UP, 0);
        } else {
            // Character 0 will be our known sentinel value
            
            // Check if any characters exist which can't be represented in a basic key event
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                if (event.keycode == 0) {
                    // We found an unknown key, so send the entire string as UTF-8
                    const char* utf8String = [inputText UTF8String];
                    
                    // Skip the first character which is our sentinel
                    LiSendUtf8TextEvent(utf8String + 1, (int)strlen(utf8String) - 1);
                    return;
                }
            }
            
            // We didn't find any unknown characters, so send them all as basic key events
            for (int i = 1; i < [inputText length]; i++) {
                struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
                assert(event.keycode != 0);
                [self sendLowLevelEvent:event];
            }
        }
    });
    
    // Reset text field back to known state
    textField.text = @"0";
    
    // Move the insertion point back to the end of the text box
    UITextRange *textRange = [textField textRangeFromPosition:textField.endOfDocument toPosition:textField.endOfDocument];
    [textField setSelectedTextRange:textRange];
}

- (void)specialCharPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:0x20 withModifierFlags:[cmd modifierFlags]];
    event.keycode = [[dictCodes valueForKey:[cmd input]] intValue];
    [self sendLowLevelEvent:event];
}

- (void)keyPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:[[cmd input] characterAtIndex:0] withModifierFlags:[cmd modifierFlags]];
    [self sendLowLevelEvent:event];
}

- (void)sendLowLevelEvent:(struct KeyEvent)event {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        // When we want to send a modified key (like uppercase letters) we need to send the
        // modifier ("shift") seperately from the key itself.
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
        }
        // Let the host know these are not (necessarily) normalized to US English scancodes
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        usleep(50 * 1000);
        LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, SS_KBE_FLAG_NON_NORMALIZED);
        if (event.modifier != 0) {
            LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
        }
    });
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSString *charset = @"qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= ";
    
    NSMutableArray<UIKeyCommand *> * commands = [NSMutableArray<UIKeyCommand *> array];
    dictCodes = [[NSDictionary alloc] initWithObjectsAndKeys: [NSNumber numberWithInt: 0x0d], @"\r", [NSNumber numberWithInt: 0x08], @"\b", [NSNumber numberWithInt: 0x1b], UIKeyInputEscape, [NSNumber numberWithInt: 0x28], UIKeyInputDownArrow, [NSNumber numberWithInt: 0x26], UIKeyInputUpArrow, [NSNumber numberWithInt: 0x25], UIKeyInputLeftArrow, [NSNumber numberWithInt: 0x27], UIKeyInputRightArrow, nil];
    
    [charset enumerateSubstringsInRange:NSMakeRange(0, charset.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:0 action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierShift action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierControl action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierAlternate action:@selector(keyPressed:)]];
                             }];
    
    for (NSString *c in [dictCodes keyEnumerator]) {
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:0
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
    }
    
    return commands;
}

- (void)connectedStateDidChangeWithIdentifier:(NSUUID * _Nonnull)identifier isConnected:(BOOL)isConnected {
    NSLog(@"Citrix X1 mouse state change: %@ -> %s",
          identifier, isConnected ? "connected" : "disconnected");
}

- (void)mouseDidMoveWithIdentifier:(NSUUID * _Nonnull)identifier deltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    accumulatedMouseDeltaX += deltaX / X1_MOUSE_SPEED_DIVISOR;
    accumulatedMouseDeltaY += deltaY / X1_MOUSE_SPEED_DIVISOR;
    
    short shortX = (short)accumulatedMouseDeltaX;
    short shortY = (short)accumulatedMouseDeltaY;
    
    if (shortX == 0 && shortY == 0) {
        return;
    }
    
    LiSendMouseMoveEvent(shortX, shortY);
    
    accumulatedMouseDeltaX -= shortX;
    accumulatedMouseDeltaY -= shortY;
}

- (int) buttonFromX1ButtonCode:(enum X1MouseButton)button {
    switch (button) {
        case X1MouseButtonLeft:
            return BUTTON_LEFT;
        case X1MouseButtonRight:
            return BUTTON_RIGHT;
        case X1MouseButtonMiddle:
            return BUTTON_MIDDLE;
        default:
            return -1;
    }
}

- (void)mouseDownWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, [self buttonFromX1ButtonCode:button]);
}

- (void)mouseUpWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, [self buttonFromX1ButtonCode:button]);
}

- (void)wheelDidScrollWithIdentifier:(NSUUID * _Nonnull)identifier deltaZ:(int8_t)deltaZ {
    LiSendScrollEvent(deltaZ);
}

#if !TARGET_OS_TV
- (BOOL)isMultipleTouchEnabled {
    return YES;
}
#endif

@end
