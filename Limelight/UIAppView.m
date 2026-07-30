//
//  UIAppView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIAppView.h"
#import "AppAssetManager.h"
#import "Utils.h"

static const float REFRESH_CYCLE = 1.0f;

@implementation UIAppView {
    TemporaryApp* _app;
    UILabel* _appLabel;
    UIImageView* _appOverlay;
    UIImageView* _appImage;
    NSCache* _artCache;
    id<AppCallback> _callback;
#if !TARGET_OS_TV
    UILabel* _nameLabel;
    UILabel* _badgeLabel;
    UIVisualEffectView* _badgeGlass;
#endif
}

static UIImage* noImage;

- (id) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback {
    self = [super init];
    _app = app;
    _callback = callback;
    _artCache = cache;

#if TARGET_OS_TV
    // Cache the NoAppImage ourselves to avoid
    // having to load it each time
    if (noImage == nil) {
        noImage = [UIImage imageNamed:@"NoAppImage"];
    }

    self.frame = CGRectMake(0, 0, 200, 265);

    [self setAlpha:app.hidden ? 0.4 : 1.0];

    _appImage = [[UIImageView alloc] initWithFrame:self.frame];
    [_appImage setImage:noImage];
    [self addSubview:_appImage];
#else
    [self buildLayout];
#endif

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
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }

    [self addTarget:self action:@selector(appClicked:) forControlEvents:UIControlEventPrimaryActionTriggered];

    [self addTarget:self action:@selector(buttonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(buttonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

#if TARGET_OS_TV
    _appImage.adjustsImageWhenAncestorFocused = YES;
#else
    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif

    [self updateAppImage];

    return self;
}

#if !TARGET_OS_TV
- (void) buildLayout {
    _appImage = [[UIImageView alloc] init];
    _appImage.contentMode = UIViewContentModeScaleAspectFill;
    _appImage.clipsToBounds = YES;
    _appImage.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _appImage.layer.cornerRadius = [MoonlightTheme tileCornerRadius];
    _appImage.layer.cornerCurve = kCACornerCurveContinuous;
    _appImage.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_appImage];

    // Shown inside the art when there is no box art to show.
    _appLabel = [[UILabel alloc] init];
    _appLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _appLabel.textColor = [UIColor labelColor];
    _appLabel.textAlignment = NSTextAlignmentCenter;
    _appLabel.numberOfLines = 0;
    _appLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_appImage addSubview:_appLabel];

    // Always-visible name beneath the tile. The old design only ever showed a
    // name when box art was missing, which left arted grids unreadable.
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    _nameLabel.adjustsFontForContentSizeCategory = YES;
    _nameLabel.textColor = [UIColor labelColor];
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.numberOfLines = 2;
    _nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_nameLabel];

    _appOverlay = [[UIImageView alloc] init];
    _appOverlay.contentMode = UIViewContentModeScaleAspectFit;
    _appOverlay.tintColor = [UIColor whiteColor];
    _appOverlay.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightSemibold];
    _appOverlay.layer.shadowColor = [UIColor blackColor].CGColor;
    _appOverlay.layer.shadowOffset = CGSizeZero;
    _appOverlay.layer.shadowOpacity = 1.0f;
    _appOverlay.layer.shadowRadius = 6.0f;
    _appOverlay.hidden = YES;
    _appOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [_appImage addSubview:_appOverlay];

    _badgeGlass = [MoonlightTheme glassViewWithTint:nil];
    _badgeGlass.layer.cornerRadius = 9.0f;
    _badgeGlass.layer.cornerCurve = kCACornerCurveContinuous;
    _badgeGlass.hidden = YES;
    _badgeGlass.translatesAutoresizingMaskIntoConstraints = NO;
    [_appImage addSubview:_badgeGlass];

    _badgeLabel = [[UILabel alloc] init];
    _badgeLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption2];
    _badgeLabel.textColor = [UIColor labelColor];
    _badgeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_badgeGlass.contentView addSubview:_badgeLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_appImage.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_appImage.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_appImage.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_appImage.heightAnchor constraintEqualToAnchor:_appImage.widthAnchor multiplier:4.0f / 3.0f],

        [_nameLabel.topAnchor constraintEqualToAnchor:_appImage.bottomAnchor constant:6],
        [_nameLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:2],
        [_nameLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-2],

        [_appLabel.leadingAnchor constraintEqualToAnchor:_appImage.leadingAnchor constant:8],
        [_appLabel.trailingAnchor constraintEqualToAnchor:_appImage.trailingAnchor constant:-8],
        [_appLabel.centerYAnchor constraintEqualToAnchor:_appImage.centerYAnchor],

        [_appOverlay.centerXAnchor constraintEqualToAnchor:_appImage.centerXAnchor],
        [_appOverlay.centerYAnchor constraintEqualToAnchor:_appImage.centerYAnchor],

        [_badgeGlass.topAnchor constraintEqualToAnchor:_appImage.topAnchor constant:8],
        [_badgeGlass.trailingAnchor constraintEqualToAnchor:_appImage.trailingAnchor constant:-8],
        [_badgeLabel.topAnchor constraintEqualToAnchor:_badgeGlass.contentView.topAnchor constant:3],
        [_badgeLabel.bottomAnchor constraintEqualToAnchor:_badgeGlass.contentView.bottomAnchor constant:-3],
        [_badgeLabel.leadingAnchor constraintEqualToAnchor:_badgeGlass.contentView.leadingAnchor constant:7],
        [_badgeLabel.trailingAnchor constraintEqualToAnchor:_badgeGlass.contentView.trailingAnchor constant:-7],
    ]];
}
#endif

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil) {
        [self updateLoop];
    }
}

- (void) appClicked:(UIView *)view {
    [_callback appClicked:_app view:view];
}

- (void) appLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback appLongClicked:_app view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];

    [_callback appLongClicked:_app view:self];
    return nil;
}
#endif

#if !TARGET_OS_TV
- (void) updateAppImage {
    BOOL noAppImage = NO;

    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }

    if (appImage != nil &&
        // These sizes are the blank placeholder art GameStream returns.
        !(appImage.size.width == 130.f && appImage.size.height == 180.f) &&   // GFE 2.0
        !(appImage.size.width == 628.f && appImage.size.height == 888.f)) {   // GFE 3.0
        _appImage.image = appImage;
    }
    else {
        _appImage.image = nil;
        noAppImage = YES;
    }

    _appLabel.text = noAppImage ? _app.name : nil;
    _appLabel.hidden = !noAppImage;

    _nameLabel.text = _app.name;

    BOOL running = [_app.id isEqualToString:_app.host.currentGame];
    _appOverlay.image = running ? [UIImage systemImageNamed:@"play.circle.fill"] : nil;
    _appOverlay.hidden = !running;

    if (_app.hidden) {
        _badgeLabel.text = @"HIDDEN";
        _badgeGlass.hidden = NO;
    }
    else if (_app.hdrSupported) {
        _badgeLabel.text = @"HDR";
        _badgeGlass.hidden = NO;
    }
    else {
        _badgeGlass.hidden = YES;
    }

    self.alpha = _app.hidden ? 0.45f : 1.0f;
}
#else
- (void) updateAppImage {
    if (_appOverlay != nil) {
        [_appOverlay removeFromSuperview];
        _appOverlay = nil;
    }
    if (_appLabel != nil) {
        [_appLabel removeFromSuperview];
        _appLabel = nil;
    }

    BOOL noAppImage = false;

    // First check the memory cache
    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        // Next try to load from the on disk cache
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }

    if (appImage != nil) {
        // This size of image might be blank image received from GameStream.
        // TODO: Improve no-app image detection
        if (!(appImage.size.width == 130.f && appImage.size.height == 180.f) && // GFE 2.0
            !(appImage.size.width == 628.f && appImage.size.height == 888.f)) { // GFE 3.0
            [_appImage setImage:appImage];
        } else {
            noAppImage = true;
        }
    } else {
        noAppImage = true;
    }

    if ([_app.id isEqualToString:_app.host.currentGame]) {
        // Only create the app overlay if needed
        _appOverlay = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Play"]];
        _appOverlay.layer.shadowColor = [UIColor blackColor].CGColor;
        _appOverlay.layer.shadowOffset = CGSizeMake(0, 0);
        _appOverlay.layer.shadowOpacity = 1;
        _appOverlay.layer.shadowRadius = 4.0;
        _appOverlay.contentMode = UIViewContentModeScaleAspectFit;
    }

    if (noAppImage) {
        _appLabel = [[UILabel alloc] init];
        [_appLabel setTextColor:[UIColor whiteColor]];
        [_appLabel setText:_app.name];
        [_appLabel setFont:[UIFont systemFontOfSize:24]];
        [_appLabel setBaselineAdjustment:UIBaselineAdjustmentAlignCenters];
        [_appLabel setTextAlignment:NSTextAlignmentCenter];
        [_appLabel setLineBreakMode:NSLineBreakByWordWrapping];
        [_appLabel setNumberOfLines:0];
    }

    [self positionSubviews];

    [_appImage.overlayContentView addSubview:_appLabel];
    [_appImage.overlayContentView addSubview:_appOverlay];
}
#endif

#if !TARGET_OS_TV
- (void) buttonSelected:(id)sender {
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = CGAffineTransformMakeScale(0.95f, 0.95f);
    }];
}

- (void) buttonDeselected:(id)sender {
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = CGAffineTransformIdentity;
    }];
}
#else
- (void) buttonSelected:(id)sender {
    _appImage.layer.opacity = 0.5f;
}
- (void) buttonDeselected:(id)sender {
    _appImage.layer.opacity = 1.0f;
}

- (void) positionSubviews {
    CGFloat padding = 5.f;
    CGSize frameSize = _appImage.frame.size;
    CGPoint center = _appImage.center;

    if (_appLabel != nil) {
        if (_appOverlay != nil) {
            _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 3, frameSize.width / 3);
            _appOverlay.center = CGPointMake(frameSize.width / 2, padding + _appOverlay.frame.size.height / 2);

            [_appLabel setFrame:CGRectMake(padding, _appOverlay.frame.size.height + padding, frameSize.width - 2 * padding, frameSize.height - _appOverlay.frame.size.height - 2 * padding)];
        }
        else {
            [_appLabel setFrame:CGRectMake(padding, padding, frameSize.width - 2 * padding, frameSize.height - 2 * padding)];
        }
    }
    else if (_appOverlay != nil) {
        _appOverlay.frame = CGRectMake(0, 0, frameSize.width / 2, frameSize.width / 2);
        _appOverlay.center = center;
    }
}
#endif

- (void) updateLoop {
    if (self.superview == nil) {
        return;
    }

#if !TARGET_OS_TV
    [self updateAppImage];
#else
    // Update the app image if neccessary
    if ((_appOverlay != nil && ![_app.id isEqualToString:_app.host.currentGame]) ||
        (_appOverlay == nil && [_app.id isEqualToString:_app.host.currentGame])) {
        [self updateAppImage];
    }

    self.superview.layer.shadowOpacity = _app.hidden ? 0.0f : 0.5f;
    [self setAlpha:_app.hidden ? 0.4 : 1.0];
#endif

    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

@end
