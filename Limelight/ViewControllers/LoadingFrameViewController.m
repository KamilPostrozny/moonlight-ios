//
//  LoadingFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/24/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "LoadingFrameViewController.h"
#import "Utils.h"

@implementation LoadingFrameViewController {
    BOOL presented;
};

- (void)viewDidLoad {
    [super viewDidLoad];

#if !TARGET_OS_TV
    self.view.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.25f];

    UIVisualEffectView* card = [MoonlightTheme glassViewWithTint:nil];
    card.layer.cornerRadius = [MoonlightTheme cardCornerRadius];
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:card];

    // The spinner comes from the storyboard; re-parent it into the card.
    [self.loadingSpinner removeFromSuperview];
    self.loadingSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingSpinner.color = [UIColor labelColor];
    [card.contentView addSubview:self.loadingSpinner];

    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:96],
        [card.heightAnchor constraintEqualToConstant:96],
        [self.loadingSpinner.centerXAnchor constraintEqualToAnchor:card.contentView.centerXAnchor],
        [self.loadingSpinner.centerYAnchor constraintEqualToAnchor:card.contentView.centerYAnchor],
    ]];
#else
    self.loadingSpinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
#endif
}

- (UIViewController*) activeViewController {
    UIViewController *topController = [UIApplication sharedApplication].keyWindow.rootViewController;
    
    while (topController.presentedViewController) {
        topController = topController.presentedViewController;
    }
    
    return topController;
}

- (void)showLoadingFrame:(void (^)(void))completion {
    if (!presented) {
        Log(LOG_I, @"Loading frame presenting start");
        presented = YES;
        [[self activeViewController] presentViewController:self animated:NO completion:^{
            Log(LOG_I, @"Loading frame presenting complete");
            if (completion) {
                completion();
            }
        }];
    }
    else if (completion) {
        Log(LOG_E, @"Loading frame already shown!");
        completion();
    }
}

- (void)dismissLoadingFrame:(void (^)(void))completion {
    if (presented) {
        Log(LOG_I, @"Loading frame hiding start");
        [self dismissViewControllerAnimated:NO completion:^{
            Log(LOG_I, @"Loading frame hiding complete");
            
            // Since presented is set to NO here rather than
            // immediately in dismissLoadingFrame, we may
            // falsely avoid displaying the loading frame if
            // a dismiss is in progress while attempting to show
            // the frame. That's preferable to crashing due to
            // displaying the same VC twice though.
            //
            // This scenario can happen if the app is suspended
            // while the dismiss is in progress then on resume
            // it attempts to display it again before the dismiss
            // completes. It can be reproduced by rapidly pressing
            // Home and switching back to Moonlight while in the app grid.
            // It reproduces more easily if the VC transitions are animated.
            self->presented = NO;
            
            if (completion) {
                completion();
            }
        }];
    }
    else if (completion) {
        completion();
    }
}

- (BOOL)isShown {
    return presented;
}

@end
