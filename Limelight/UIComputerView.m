//
//  UIComputerView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIComputerView.h"
#import "TemporaryApp.h"
#import "Utils.h"

@implementation UIComputerView {
    TemporaryHost* _host;
    id<HostCallback> _callback;
#if !TARGET_OS_TV
    UIVisualEffectView* _glass;
    UIImageView* _symbolView;
    UILabel* _nameLabel;
    UILabel* _statusLabel;
    UIActivityIndicatorView* _spinner;
#else
    UIImageView* _hostIcon;
    UILabel* _hostLabel;
    UIImageView* _hostOverlay;
    UIActivityIndicatorView* _hostSpinner;
    CGSize _labelSize;
#endif
}
static const float REFRESH_CYCLE = 2.0f;

#if TARGET_OS_TV
static const int ITEM_PADDING = 50;
static const int LABEL_DY = 40;
#else
static const int ITEM_PADDING = 0;
static const int LABEL_DY = 20;
#endif

#if TARGET_OS_TV
- (id) init {
    self = [super init];

    self.frame = CGRectMake(0, 0, 400, 400);

    _hostIcon = [[UIImageView alloc] initWithFrame:self.frame];
    [_hostIcon setImage:[UIImage imageNamed:@"Computer"]];

    self.layer.shadowColor = [[UIColor blackColor] CGColor];
    self.layer.shadowOffset = CGSizeMake(5,8);
    self.layer.shadowOpacity = 0.3;

    [self addTarget:self action:@selector(hostButtonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(hostButtonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

    _hostLabel = [[UILabel alloc] init];
    _hostLabel.textColor = [UIColor whiteColor];

    _hostOverlay = [[UIImageView alloc] initWithFrame:CGRectMake(self.frame.size.width / 3, _hostIcon.frame.size.height / 4, _hostIcon.frame.size.width / 3, self.frame.size.height / 3)];
    _hostSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [_hostSpinner setFrame:_hostOverlay.frame];
    _hostSpinner.userInteractionEnabled = NO;
    _hostSpinner.hidesWhenStopped = YES;

    [self addSubview:_hostLabel];
    [self addSubview:_hostIcon];

    _hostIcon.clipsToBounds = NO;
    _hostIcon.adjustsImageWhenAncestorFocused = YES;
    _hostIcon.masksFocusEffectToContents = YES;

    self.adjustsImageWhenHighlighted = NO;

    _hostOverlay.masksFocusEffectToContents = YES;
    _hostOverlay.adjustsImageWhenAncestorFocused = NO;

    [_hostIcon.overlayContentView addSubview:_hostOverlay];
    [_hostIcon.overlayContentView addSubview:_hostSpinner];

    return self;
}

- (void) hostButtonSelected:(id)sender {
    _hostIcon.layer.opacity = 0.5f;
    _hostSpinner.layer.opacity = 0.5f;
    _hostOverlay.layer.opacity = 0.5f;
}
- (void) hostButtonDeselected:(id)sender {
    _hostIcon.layer.opacity = 1.0f;
    _hostSpinner.layer.opacity = 1.0f;
    _hostOverlay.layer.opacity = 1.0f;
}
#else
- (id) init {
    self = [super init];

    _glass = [MoonlightTheme glassViewWithTint:nil];
    _glass.userInteractionEnabled = NO;
    _glass.layer.cornerRadius = [MoonlightTheme cardCornerRadius];
    _glass.layer.cornerCurve = kCACornerCurveContinuous;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_glass];

    _symbolView = [[UIImageView alloc] init];
    _symbolView.contentMode = UIViewContentModeScaleAspectFit;
    _symbolView.tintColor = [MoonlightTheme accentColor];
    _symbolView.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightMedium];
    [_symbolView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _nameLabel.textColor = [UIColor labelColor];
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.hidesWhenStopped = YES;
    [_spinner setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView* textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _statusLabel]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.spacing = 2;

    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[_symbolView, textStack, _spinner]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];

    [self addTarget:self action:@selector(hostButtonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(hostButtonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

    self.pointerInteractionEnabled = YES;

    return self;
}

- (void) hostButtonSelected:(id)sender {
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = CGAffineTransformMakeScale(0.96f, 0.96f);
    }];
}

- (void) hostButtonDeselected:(id)sender {
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void) setHostSelected:(BOOL)selected {
    [MoonlightTheme applyGlassTint:(selected ? [MoonlightTheme accentColor] : nil) toView:_glass];
}
#endif

#if TARGET_OS_TV
- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;

    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    [_hostLabel setText:@"Add Host Manually"];
    [_hostLabel sizeToFit];

    [_hostOverlay setImage:[UIImage imageNamed:@"AddOverlayIcon"]];

    [self updateBounds];

    return self;
}
#else
- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;

    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    _nameLabel.text = @"Add PC";
    _statusLabel.text = @"Enter an IP address";
    _symbolView.image = [UIImage systemImageNamed:@"plus"];

    return self;
}
#endif

- (id) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback {
    self = [self init];
    _host = host;
    _callback = callback;

    // Use UIContextMenuInteraction on iOS 13.0+ and a standard UILongPressGestureRecognizer
    // for tvOS devices and iOS prior to 13.0.
#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hostLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }

    [self addTarget:self action:@selector(hostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    [self updateContentsForHost:host];

    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil && _host != nil) {
        [self updateLoop];
    }
}

#if TARGET_OS_TV
- (void) updateBounds {
    float x = FLT_MAX;
    float y = FLT_MAX;
    float width = 0;
    float height;

    float iconX = _hostIcon.frame.origin.x + _hostIcon.frame.size.width / 2;
    _hostLabel.center = CGPointMake(iconX, _hostIcon.frame.origin.y + _hostIcon.frame.size.height + LABEL_DY);

    x = MIN(x, _hostIcon.frame.origin.x);
    x = MIN(x, _hostLabel.frame.origin.x);

    y = MIN(y, _hostIcon.frame.origin.y);
    y = MIN(y, _hostLabel.frame.origin.y);

    width = MAX(width, _hostIcon.frame.size.width);
    width = MAX(width, _hostLabel.frame.size.width);

    height = _hostIcon.frame.size.height +
        _hostLabel.frame.size.height +
        LABEL_DY / 2;

    self.bounds = CGRectMake(x - ITEM_PADDING, y - ITEM_PADDING, width + 2 * ITEM_PADDING, height + 2 * ITEM_PADDING);
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    _hostLabel.text = _host.name;
    [_hostLabel sizeToFit];

    if (host.state == StateOnline) {
        [_hostSpinner stopAnimating];

        if (host.pairState == PairStateUnpaired) {
            [_hostOverlay setImage:[UIImage imageNamed:@"LockedOverlayIcon"]];
        }
        else {
            [_hostOverlay setImage:nil];
        }
    }
    else if (host.state == StateOffline) {
        [_hostSpinner stopAnimating];
        [_hostOverlay setImage:[UIImage imageNamed:@"ErrorOverlayIcon"]];
    }
    else {
        [_hostSpinner startAnimating];
    }

    [self updateBounds];
}
#else
- (NSString*) symbolNameForHost:(TemporaryHost*)host {
    if (host.state == StateOffline) {
        return @"desktopcomputer.trianglebadge.exclamationmark";
    }
    if (host.state == StateOnline && host.pairState != PairStatePaired) {
        return @"lock.desktopcomputer";
    }
    return @"desktopcomputer";
}

- (NSString*) statusTextForHost:(TemporaryHost*)host {
    if (host.state == StateOffline) {
        return @"Offline";
    }
    if (host.state == StateUnknown) {
        return @"Connecting…";
    }
    if (host.pairState != PairStatePaired) {
        return @"Not paired";
    }

    for (TemporaryApp* app in host.appList) {
        if ([app.id isEqualToString:host.currentGame]) {
            return [NSString stringWithFormat:@"Playing %@", app.name];
        }
    }

    return @"Paired";
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    _nameLabel.text = host.name;
    _statusLabel.text = [self statusTextForHost:host];
    _symbolView.image = [UIImage systemImageNamed:[self symbolNameForHost:host]];
    _symbolView.tintColor = (host.state == StateOffline) ? [UIColor systemGrayColor] : [MoonlightTheme accentColor];

    if (host.state == StateUnknown) {
        [_spinner startAnimating];
    }
    else {
        [_spinner stopAnimating];
    }
}
#endif

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }

    [self updateContentsForHost:_host];

    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

- (void) hostLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback hostLongClicked:_host view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];

    [_callback hostLongClicked:_host view:self];
    return nil;
}
#endif

- (void) hostClicked {
    [_callback hostClicked:_host view:self];
}

- (void) addClicked {
    [_callback addHostClicked];
}

@end
