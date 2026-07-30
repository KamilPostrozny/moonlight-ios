# Liquid Glass Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Moonlight iOS's 2014-era UI with a modern, consistent Liquid Glass design built against the iOS 26 SDK, and fix the UX problems that come with it (unlabeled game tiles, undiscoverable long-press-only actions, an off-screen settings screen).

**Architecture:** `MainFrameViewController` becomes a single screen driven by a `UICollectionViewCompositionalLayout` with three sections (PCs / Continue / Games). `SWRevealViewController` is removed from the view hierarchy and Settings becomes a sheet built in code. All glass API usage funnels through a `MoonlightTheme` helper in `Utils`. No new source files are created — everything lands in files already in the Xcode target.

**Tech Stack:** Objective-C, UIKit, iOS 26 SDK (`UIGlassEffect`, glass `UIButtonConfiguration`, compositional layout), CoreGraphics for box-art colour sampling, Core Data (unchanged).

Source spec: `docs/superpowers/specs/2026-07-30-liquid-glass-redesign-design.md`

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Language: Objective-C only.** The project has no Swift files and no Swift build phase.
- **No new source files.** Adding a file requires `project.pbxproj` surgery, which is the most likely way to break a build that cannot be tested locally. New classes are declared and implemented inside `.m` files already in the target.
- **`project.pbxproj` is edited exactly once**, in Task 1, and only to change `IPHONEOS_DEPLOYMENT_TARGET`. No other task may touch it.
- **Minimum iOS: 26.0.** No `@available` guards, no `UIBlurEffect` fallbacks, no `if (@available(iOS 13.0, *))` in new code. Existing availability checks in untouched code stay as they are.
- **`TVOS_DEPLOYMENT_TARGET` stays 12.0.** Every `#if TARGET_OS_TV` branch is left byte-for-byte intact. All new UI code goes inside `#if !TARGET_OS_TV` or in files that tvOS does not compile.
- **Know which files tvOS compiles.** Verified from the two `Sources` build phases in `project.pbxproj`:
  - **Both targets:** `Utils.m`, `MainFrameViewController.m`, `UIAppView.m`, `UIComputerView.m`, `LoadingFrameViewController.m`, `StreamFrameViewController.m`, `ComputerScrollView.m`. New code in these needs `#if !TARGET_OS_TV`, and deleting an unguarded symbol the tvOS branch still uses breaks that target.
  - **iOS only:** `SettingsViewController.m`, `SWRevealViewController.m`. No guards are needed in these; the `#if TARGET_OS_TV` blocks already inside `SettingsViewController.m` are dead code.
  - Nothing builds the tvOS target, so a break there is invisible. Do not go out of your way to preserve it, but do not break it gratuitously either.
- **Glass API surface is restricted to three names:** `UIGlassEffect`, `+[UIButtonConfiguration glassButtonConfiguration]`, `+[UIButtonConfiguration prominentGlassButtonConfiguration]`. All three are used only inside `MoonlightTheme` (Task 2). Corner rounding uses `layer.cornerRadius` + `layer.cornerCurve = kCACornerCurveContinuous`, **not** `UICornerConfiguration` — this deviates from the spec deliberately to shrink the surface of API names that cannot be checked by a local compiler.
- **Accent colour:** `[UIColor colorWithRed:0.67f green:0.62f blue:1.0f alpha:1.0f]`. Always via `[MoonlightTheme accentColor]`, never inline.
- **Branch:** all work happens on `liquid-glass-redesign`, branched from `master`.
- **Commit trailers:** every commit ends with

  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
  ```

- **Do not modify** networking, discovery, pairing, streaming, or Core Data code. Specifically: `HttpManager`, `DiscoveryManager`, `PairManager`, `Connection`, `StreamManager`, `DataManager`, `AppAssetManager`, `TemporaryHost`, `TemporaryApp`, `TemporarySettings`, `OnScreenControls`.
- **Preserve the `view:` nil convention.** In `MainFrameViewController`, a nil `view:` argument to `hostClicked:view:` / `appClicked:view:` means "programmatic, not a user tap" and changes control flow. Never pass nil from a tap handler, and never call `appLongClicked:view:` with nil (it sets `popoverPresentationController.sourceView` and throws on iPad).

## Verification Protocol

There is no test target, no simulator, and no local compiler — development happens on Linux. **CI is the only compile gate.** Every task ends with this protocol. `<branch>` is `liquid-glass-redesign`.

```bash
# From inside the repo (gh fails outside it with a filesystem-boundary error)
git push -u origin liquid-glass-redesign

# Feature branches do NOT build on push. Dispatch explicitly.
gh workflow run build-ipa.yml --ref liquid-glass-redesign

# Dispatch does not print a run id; look it up — and check the sha it built.
gh run list --branch liquid-glass-redesign --limit 1 --json databaseId,headSha,conclusion
gh run watch <run-id> --exit-status --compact

# Green is not enough. Inspect the artifact.
gh run download <run-id> -D /tmp/claude-1000/-home-kamil-Projects-moonlight-ios/ec9c9ad3-054c-4318-aa7d-5cef4bcf006d/scratchpad/artifact
cd /tmp/claude-1000/-home-kamil-Projects-moonlight-ios/ec9c9ad3-054c-4318-aa7d-5cef4bcf006d/scratchpad/artifact
unzip -o *.ipa
file Payload/Moonlight.app/Moonlight                              # expect: Mach-O 64-bit ... arm64
strings Payload/Moonlight.app/Info.plist | grep -oE "iphoneos[0-9.]+"   # expect: iphoneos26.x
```

**Check the `headSha` of the run you are about to trust.** A green run proves
nothing if it built a commit that predates your work. Task 2's implementer
reported success against a run whose `headSha` was the task's own *base*
commit, because it never pushed — the code in question had never been
compiled. Before reading a conclusion, confirm the run's `headSha` matches the
commit you just made. Both `gh run list --json headSha` and
`git ls-remote origin liquid-glass-redesign` will tell you.

Each task below adds a task-specific `strings` grep proving its new code actually linked, plus a list of what Kamil should look at after sideloading. **Never claim a task works without a green run id whose `headSha` is your commit, and the artifact checks above.**

---

### Task 1: Raise the iOS deployment target to 26.0

Shipped alone. A 26.0 floor can turn deprecated calls in `SWRevealViewController.m` and `OnScreenControls.m` into hard errors; isolating the bump means one CI run tells you whether that happened, with nothing else in the diff to confuse the signal.

**Files:**
- Modify: `Moonlight.xcodeproj/project.pbxproj` (every `IPHONEOS_DEPLOYMENT_TARGET = 12.0;` occurrence)

**Interfaces:**
- Consumes: nothing
- Produces: an iOS 26 build floor, which every later task depends on for unguarded glass API use

- [ ] **Step 1: Create the branch**

```bash
git checkout master
git pull
git checkout -b liquid-glass-redesign
```

- [ ] **Step 2: Confirm which occurrences exist**

```bash
grep -n "IPHONEOS_DEPLOYMENT_TARGET\|TVOS_DEPLOYMENT_TARGET" Moonlight.xcodeproj/project.pbxproj
```

Expected: several `IPHONEOS_DEPLOYMENT_TARGET = 12.0;` lines and several `TVOS_DEPLOYMENT_TARGET = 12.0;` lines. Note the line numbers — you must change only the `IPHONEOS_` ones.

- [ ] **Step 3: Change only the iOS target lines**

```bash
sed -i 's/IPHONEOS_DEPLOYMENT_TARGET = 12\.0;/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/g' Moonlight.xcodeproj/project.pbxproj
```

- [ ] **Step 4: Verify the tvOS target was not touched**

```bash
grep -n "IPHONEOS_DEPLOYMENT_TARGET\|TVOS_DEPLOYMENT_TARGET" Moonlight.xcodeproj/project.pbxproj
```

Expected: all `IPHONEOS_DEPLOYMENT_TARGET = 26.0;`, all `TVOS_DEPLOYMENT_TARGET = 12.0;`. If any `TVOS_` line changed, revert with `git checkout -- Moonlight.xcodeproj/project.pbxproj` and redo Step 3.

- [ ] **Step 5: Commit**

```bash
git add Moonlight.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
Raise the iOS deployment target to 26.0

Liquid Glass is iOS 26-only. Shipping this bump on its own so a CI
failure points at legacy code that stopped compiling under the higher
floor, not at new UI code. tvOS stays at 12.0.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 6: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Info.plist | grep -oE "MinimumOSVersion|26\.0"
```

If CI fails, the failure is in pre-existing code (most likely `SWRevealViewController.m` or `OnScreenControls.m`). Fix the specific errors reported — do not lower the target. Report the errors before fixing so the scope of legacy breakage is visible.

**On-device check after sideload:** app launches and behaves exactly as before. Nothing visual has changed yet.

---

### Task 2: `MoonlightTheme` design tokens and glass helpers

The riskiest unknown in this project is whether the recalled iOS 26 glass API names compile. This task is a cheap probe: it adds the helpers and nothing that uses them, so a CI failure names exactly which symbol is wrong, in one file.

**Files:**
- Modify: `Limelight/Utility/Utils.h` (append a new `@interface` after the `Utils` interface, before the `NSString` category)
- Modify: `Limelight/Utility/Utils.m` (append a new `@implementation` after the `Utils` implementation, before the `NSString` category)

**Interfaces:**
- Consumes: nothing
- Produces:
  - `+[MoonlightTheme accentColor] -> UIColor*`
  - `+[MoonlightTheme tileCornerRadius] -> CGFloat` (14.0)
  - `+[MoonlightTheme cardCornerRadius] -> CGFloat` (22.0)
  - `+[MoonlightTheme glassViewWithTint:(UIColor*)tint] -> UIVisualEffectView*`
  - `+[MoonlightTheme applyGlassTint:(UIColor*)tint toView:(UIVisualEffectView*)view] -> void`
  - `+[MoonlightTheme glassButtonWithTitle:(NSString*)title image:(UIImage*)image prominent:(BOOL)prominent] -> UIButtonConfiguration*`
  - `+[MoonlightTheme ambientColorForImage:(UIImage*)image] -> UIColor*` (nil for nil/invalid input)

- [ ] **Step 1: Append the interface to `Utils.h`**

Insert immediately after the closing `@end` of the `Utils` interface and before `@interface NSString (NSStringWithTrim)`:

```objc
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
```

- [ ] **Step 2: Append the implementation to `Utils.m`**

Insert immediately after the closing `@end` of `@implementation Utils` and before `@implementation NSString (NSStringWithTrim)`:

```objc
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
```

- [ ] **Step 3: Confirm `Utils.h` gets UIKit**

```bash
grep -n "import" Limelight/Utility/Utils.h Limelight/Utility/Utils.m
```

`Utils.h` has no imports and relies on the prefix header for `UIAlertController`. If CI reports unknown `UIColor` / `UIVisualEffectView` / `UIButtonConfiguration` types, add `#import <UIKit/UIKit.h>` at the top of `Utils.h` and rerun. Do not add it pre-emptively — the existing `UIAlertController` use proves UIKit is already reachable.

- [ ] **Step 4: Commit**

```bash
git add Limelight/Utility/Utils.h Limelight/Utility/Utils.m
git commit -m "$(cat <<'EOF'
Add MoonlightTheme design tokens and glass helpers

Single home for every iOS 26 Liquid Glass call: UIGlassEffect, the glass
button configurations, the corner radius scale, the accent colour, and
box-art ambient colour sampling. Nothing uses it yet — landing it alone
turns a wrong API name into one CI failure in one file.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 5: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(ambientColorForImage:|glassViewWithTint:|MoonlightTheme)$"
```

Expected: all three present. If `MoonlightTheme` is absent, the class was dead-stripped — that is fine and expected for a class with no callers; the selector strings are the real proof.

**On-device check after sideload:** no visible change. This task only has to compile.

---

### Task 3: Remove the reveal drawer, rewire the storyboards, force dark appearance

**Files:**
- Modify: `iPhone.storyboard`
- Modify: `iPad.storyboard`
- Modify: `Limelight/Limelight-Info.plist`
- Modify: `Limelight/ViewControllers/MainFrameViewController.h`
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`
- Modify: `Limelight/ViewControllers/StreamFrameViewController.m`
- Modify: `Limelight/ViewControllers/SettingsViewController.h`
- Modify: `Limelight/ViewControllers/SettingsViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2) — not yet used, but must still compile
- Produces:
  - The `UINavigationController` is the storyboard's initial view controller on both idioms
  - Both Settings scenes carry `storyboardIdentifier="settings"`
  - `-[MainFrameViewController showSettings]` presents Settings as a sheet
  - `MainFrameViewController` no longer conforms to `SWRevealViewControllerDelegate` and no longer declares `upButton`
  - `settingsButton` is declared only under `#if TARGET_OS_TV`

After this task the app looks nearly the same but is structurally native: no drawer, a gear button, a dark appearance, and a system-glass navigation bar.

- [ ] **Step 1: Repoint the iPhone storyboard's initial view controller**

In `iPhone.storyboard` line 2, change `initialViewController="DL0-L5-LOv"` to `initialViewController="ftZ-kC-fxI"` (the `UINavigationController`).

- [ ] **Step 2: Delete the iPhone reveal scene**

Delete the whole block from `<!--Reveal View Controller-->` through the `</scene>` that closes `sceneID="QYt-XN-Ojr"` — the `SWRevealViewController` with id `DL0-L5-LOv` and its `sw_rear` / `sw_front` segues.

- [ ] **Step 3: Strip the iPhone Settings scene**

In scene `sceneID="uYM-56-Ivb"`:

- Add `storyboardIdentifier="settings"` to `<viewController id="rYd-e6-cQU" ...>` so it reads:

```xml
<viewController storyboardIdentifier="settings" id="rYd-e6-cQU" userLabel="Side Bar" customClass="SettingsViewController" sceneMemberID="viewController">
```

- Replace the entire `<view key="view" ... customClass="UIScrollView">…</view>` element (every label, segmented control, slider, and the resolution display view) with:

```xml
<view key="view" contentMode="scaleToFill" id="iNk-qF-gIr">
    <rect key="frame" x="0.0" y="0.0" width="414" height="896"/>
    <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
    <color key="backgroundColor" systemColor="systemBackgroundColor"/>
</view>
```

- Delete the whole `<connections>` block that follows it (every `<outlet .../>` from `audioOnPCSelector` through `touchModeSelector`). **An outlet connected to a deleted view is a crash at scene load, so this deletion is mandatory, not cosmetic.**

- [ ] **Step 4: Strip the iPhone navigation bar styling**

Replace the `<navigationBar key="navigationBar" ... id="0ZA-Ec-QgD">…</navigationBar>` element with:

```xml
<navigationBar key="navigationBar" contentMode="scaleToFill" id="0ZA-Ec-QgD">
    <rect key="frame" x="0.0" y="48" width="414" height="44"/>
    <autoresizingMask key="autoresizingMask"/>
</navigationBar>
```

Dropping `barStyle="black"`, `translucent="NO"`, the grey `backgroundColor` / `barTintColor`, and `titleTextAttributes` is what lets iOS 26 supply glass.

- [ ] **Step 5: Strip the iPhone main scene**

In `<collectionView ... id="Rtu-AT-Alw" customClass="AppCollectionView">`:

- Delete the grey `<color key="backgroundColor" red="0.333…" .../>` line. The collection view background is set in code from Task 4 onward.
- Delete the whole `<cells>…</cells>` block containing the `AppCell` prototype. Task 4 registers cell classes in code.
- Leave `<collectionViewFlowLayout .../>` in place — a storyboard collection view requires a layout element, and Task 4 replaces it at runtime with `setCollectionViewLayout:`.
- Leave the `dataSource` / `delegate` outlets alone.

In `<navigationItem key="navigationItem" id="pSu-bl-gL9">`, delete both `<barButtonItem>` children so it reads `<navigationItem key="navigationItem" id="pSu-bl-gL9"/>`.

In the view controller's `<connections>`, delete the `settingsButton` and `upButton` outlets. **Keep** `<segue destination="mI3-9F-XwU" kind="push" identifier="createStreamFrame" id="NuQ-Ez-IEX"/>` — it is performed by name from code.

- [ ] **Step 6: Apply Steps 1–5 to `iPad.storyboard` with its own IDs**

| iPhone | iPad |
|---|---|
| initial VC `DL0-L5-LOv` → `ftZ-kC-fxI` | initial VC `EVd-wq-ego` → `baW-rW-rBd` |
| reveal scene `QYt-XN-Ojr` | reveal scene `rR7-ZT-bc7` |
| settings VC `rYd-e6-cQU`, view `iNk-qF-gIr` | settings VC `BsV-3c-455`, view `WRy-3f-gEP` |
| nav bar `0ZA-Ec-QgD` | nav bar `RUe-14-4Ya` |
| collection view `Rtu-AT-Alw`, cell `Uqv-Di-fzX` | collection view `TZj-Lc-M9d`, cell `fv6-NS-qsK` |
| main VC `dgh-JZ-Q7z` | main VC `wb7-af-jn8` |
| stream segue `NuQ-Ez-IEX` (keep) | stream segue `7gN-E7-Ips` (keep) |

The iPad replacement view keeps its own frame: `width="834" height="1194"`. The iPad file also contains an orphan `<!--Settings View Controller-->` scene (`sceneID="tWo-uo-hHg"`) holding only a first-responder placeholder — leave it, it references nothing.

- [ ] **Step 7: Verify both storyboards are still well-formed XML**

```bash
python3 -c "import xml.dom.minidom,sys; [xml.dom.minidom.parse(f) for f in ['iPhone.storyboard','iPad.storyboard']]; print('OK')"
grep -c "SWRevealViewController\|sw_rear\|sw_front" iPhone.storyboard iPad.storyboard
```

Expected: `OK`, then `0` for both files.

- [ ] **Step 8: Force dark appearance app-wide**

In `Limelight/Limelight-Info.plist`, add inside the top-level `<dict>`:

```xml
<key>UIUserInterfaceStyle</key>
<string>Dark</string>
```

This replaces the per-view-controller `overrideUserInterfaceStyle` hack and lets every new view use semantic colours (`labelColor`, `secondaryLabelColor`, `systemBackgroundColor`) while staying dark-first.

- [ ] **Step 9: Remove the reveal plumbing from `MainFrameViewController.h`**

Delete the `#import "SWRevealViewController.h"` line, drop `SWRevealViewControllerDelegate` from the protocol list, and move `settingsButton` behind the tvOS guard. The whole interface becomes:

```objc
#import <UIKit/UIKit.h>
#import "DiscoveryManager.h"
#import "PairManager.h"
#import "StreamConfiguration.h"
#import "UIComputerView.h"
#import "UIAppView.h"
#import "AppAssetManager.h"

@interface MainFrameViewController : UICollectionViewController <DiscoveryCallback, PairCallback, HostCallback, AppCallback, AppAssetCallback, NSURLConnectionDelegate>

#if TARGET_OS_TV
@property (weak, nonatomic) IBOutlet UIBarButtonItem *settingsButton;
#endif

@end
```

`upButton` is deleted outright: it was already inside `#if !TARGET_OS_TV` and has no remaining users. `settingsButton` survives for tvOS, whose separate `Moonlight TV/Base.lproj/Main.storyboard` still connects it.

- [ ] **Step 10: Remove the reveal plumbing from `MainFrameViewController.m`**

Make these edits:

1. Delete `disableUpButton` and `enableUpButton` entirely, and their three call sites: `[self disableUpButton]` in `viewDidLoad` and in `showHostSelectionView`, and `[self enableUpButton]` in `hostClicked:view:`.

2. Delete the `revealController:didMoveToPosition:` method and the `FrontViewPosition currentPosition;` instance variable.

3. Delete all three `#if !TARGET_OS_TV` reveal blocks of this shape — in `appClicked:view:`, `appLongClicked:view:`, and `launchPendingDeepLinkApp:`:

```objc
#if !TARGET_OS_TV
    if (currentPosition != FrontViewPositionLeft) {
        [[self revealViewController] revealToggleAnimated:NO];
    }
#endif
```

   They existed only to force `saveSettings` before `prepareToStreamApp:` read Core Data. Task 9 makes Settings save on every change, so the dependency disappears. Until Task 9 lands, settings changes are saved by the Done button added in Step 12 below.

4. In `viewDidLoad`, replace the `#if !TARGET_OS_TV` block that wires the reveal controller with the gear button:

```objc
#if !TARGET_OS_TV
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showSettings)];
#else
```

   keeping the existing tvOS `else` branch untouched.

5. Delete `currentPosition = FrontViewPositionLeft;` from `viewDidLoad`.

6. In `viewDidAppear:`, delete the `setPrimaryViewController:` call and the three lines that flatten the navigation bar:

```objc
    UIImage* fakeImage = [[UIImage alloc] init];
    [self.navigationController.navigationBar setShadowImage:fakeImage];
    [self.navigationController.navigationBar setBackgroundImage:fakeImage forBarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
```

   They are what currently prevents the bar from rendering as glass.

7. Rewrite `disableNavigation` / `enableNavigation`, which referenced the deleted bar button items:

```objc
- (void) disableNavigation {
    self.navigationItem.rightBarButtonItem.enabled = NO;
}

- (void) enableNavigation {
    self.navigationItem.rightBarButtonItem.enabled = YES;
}
```

8. Add the settings presenter:

```objc
#if !TARGET_OS_TV
- (void) showSettings {
    SettingsViewController* settings = [self.storyboard instantiateViewControllerWithIdentifier:@"settings"];
    UINavigationController* nav = [[UINavigationController alloc] initWithRootViewController:settings];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;

    UISheetPresentationController* sheet = nav.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    sheet.prefersGrabberVisible = YES;

    [self presentViewController:nav animated:YES completion:nil];
}
#endif
```

- [ ] **Step 11: Remove the reveal call from `StreamFrameViewController.m`**

Delete the whole `viewDidAppear:` override at the top of the file — its only non-`super` statement is the reveal call:

```objc
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];
#endif
}
```

- [ ] **Step 12: Give Settings a Done button and drop the dark-mode hack**

In `SettingsViewController.h`, delete the `@property(nonatomic) UIUserInterfaceStyle overrideUserInterfaceStyle;` declaration together with the two `#pragma clang diagnostic` lines wrapping it — the plist key from Step 8 makes it redundant.

In `SettingsViewController.m`, delete `@dynamic overrideUserInterfaceStyle;` and the `if (@available(iOS 13.0, tvOS 13.0, *)) { self.overrideUserInterfaceStyle = … }` block in `viewDidLoad`, then append to `viewDidLoad`. This file is in the iOS target only, so it needs no `#if` guards:

```objc
    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
```

and add:

```objc
- (void) doneTapped {
    [self saveSettings];
    [self dismissViewControllerAnimated:YES completion:nil];
}
```

- [ ] **Step 13: Neutralise the now-view-less Settings screen**

Every outlet in `SettingsViewController` is nil after Step 3, so `viewDidLoad` would crash-free but do nothing useful, and `viewDidLayoutSubviews` would dereference a nil `scrollView`. Task 9 rebuilds this screen properly; until then it must not crash. Delete these three methods from `SettingsViewController.m`:

- `viewDidLayoutSubviews`
- `viewSafeAreaInsetsDidChange`
- `updateResolutionDisplayViewText` — and its two call sites in `viewDidLoad` and `newResolutionChosen`

and delete from `viewDidLoad` the three lines that configure `self.resolutionDisplayView`:

```objc
    self.resolutionDisplayView.layer.cornerRadius = 10;
    self.resolutionDisplayView.clipsToBounds = YES;
    UITapGestureRecognizer *resolutionDisplayViewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resolutionDisplayViewTapped:)];
    [self.resolutionDisplayView addGestureRecognizer:resolutionDisplayViewTap];
```

Messages to nil receivers are safe in Objective-C, so the remaining outlet calls in `viewDidLoad` and `saveSettings` are no-ops rather than crashes. `saveSettings` will write defaults from nil selectors during this one task; Task 9 fixes that. Note this explicitly in the commit message.

- [ ] **Step 14: Confirm no reveal references remain in iOS code paths**

```bash
grep -rn "revealViewController\|SWReveal\|FrontViewPosition\|upButton" Limelight/ --include=*.m --include=*.h | grep -v "^Limelight/ViewControllers/SWRevealViewController"
```

Expected: no output.

- [ ] **Step 15: Commit**

```bash
git add iPhone.storyboard iPad.storyboard Limelight/Limelight-Info.plist \
        Limelight/ViewControllers/MainFrameViewController.h \
        Limelight/ViewControllers/MainFrameViewController.m \
        Limelight/ViewControllers/StreamFrameViewController.m \
        Limelight/ViewControllers/SettingsViewController.h \
        Limelight/ViewControllers/SettingsViewController.m
git commit -m "$(cat <<'EOF'
Replace the reveal drawer with a native navigation shell

The navigation controller is now the initial view controller on both
idioms, the SWRevealViewController scenes and their segues are gone, and
Settings is presented as a sheet from a gear button instead of sliding in
from the left. Navigation bar styling attributes are dropped so iOS 26
renders the bar as glass, and UIUserInterfaceStyle=Dark in Info.plist
replaces the per-controller dark mode override.

Settings is temporarily inert: its storyboard subviews and outlets are
removed here and the screen is rebuilt in code in a later commit. Its
outlet-reading methods are no-ops against nil until then.

SWRevealViewController.m and ComputerScrollView.m stay in the target,
unreferenced. Removing them means pbxproj surgery for no runtime benefit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 16: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(showSettings|doneTapped)$"
```

**On-device check after sideload:** app launches to the host picker with a dark, translucent navigation bar and a gear button top-right. Tapping the gear opens an empty sheet with a Done button that dismisses. No drawer, no left-edge pan. Selecting a host and launching a game still works.

---

### Task 4: Compositional layout, cell classes, and the PCs section

**Files:**
- Modify: `Limelight/UIComputerView.h`
- Modify: `Limelight/UIComputerView.m` (full rewrite of the iOS layout path)
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2), `showSettings` (Task 3)
- Produces:
  - `-[UIComputerView setHostSelected:(BOOL)selected]`
  - `MoonlightTileCell` (in `MainFrameViewController.m`): `-setTileView:(UIView*)tile`, reuse id `@"tile"`
  - `MoonlightHeaderView` (in `MainFrameViewController.m`): `titleLabel`, `accessoryButton`, reuse id `@"header"`, kind `UICollectionElementKindSectionHeader`
  - `MoonlightSection` enum with `MoonlightSectionHosts`, `MoonlightSectionContinue`, `MoonlightSectionGames`
  - `-[MainFrameViewController sectionAtIndex:] -> MoonlightSection`
  - `-[MainFrameViewController rebuildSections]`
  - `_sortedHostList` — hosts sorted by name, rebuilt in `updateHosts`

- [ ] **Step 1: Add the selection setter to `UIComputerView.h`**

Inside the existing `@interface UIComputerView`, after `initForAddWithCallback:`:

```objc
#if !TARGET_OS_TV
- (void) setHostSelected:(BOOL)selected;
#endif
```

- [ ] **Step 2: Rewrite the iOS layout in `UIComputerView.m`**

Replace the instance variable block, `init`, `updateBounds`, `updateContentsForHost:`, and the two highlight methods. The tvOS branches keep their existing fixed-frame behaviour, so the file keeps its `#if TARGET_OS_TV` structure — only the `#else` sides change.

New instance variables and imports (add `#import "TemporaryApp.h"` and `#import "Utils.h"` at the top):

```objc
@implementation UIComputerView {
    TemporaryHost* _host;
    id<HostCallback> _callback;
#if !TARGET_OS_TV
    UIVisualEffectView* _glass;
    UIImageView* _symbolView;
    UILabel* _nameLabel;
    UILabel* _statusLabel;
    UIActivityIndicatorView* _spinner;
    BOOL _isAddButton;
#else
    UIImageView* _hostIcon;
    UILabel* _hostLabel;
    UIImageView* _hostOverlay;
    UIActivityIndicatorView* _hostSpinner;
    CGSize _labelSize;
#endif
}
```

The iOS `init`:

```objc
#if !TARGET_OS_TV
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
```

State-to-copy helpers and the new `updateContentsForHost:` for iOS:

```objc
#if !TARGET_OS_TV
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
```

Delete `updateBounds` and every call to it on the iOS path. `initForAddWithCallback:` for iOS becomes:

```objc
#if !TARGET_OS_TV
- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;
    _isAddButton = YES;

    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    _nameLabel.text = @"Add PC";
    _statusLabel.text = @"Enter an IP address";
    _symbolView.image = [UIImage systemImageNamed:@"plus"];

    return self;
}
#endif
```

`initWithComputer:andCallback:`, `didMoveToSuperview`, `updateLoop`, `hostLongClicked:`, `contextMenuInteraction:configurationForMenuAtLocation:`, `hostClicked`, and `addClicked` keep their current bodies. `updateLoop`'s `performSelector:withObject:afterDelay:` refresh cycle is preserved unchanged — the status line depends on it.

- [ ] **Step 3: Add the cell and header classes to `MainFrameViewController.m`**

Insert immediately after the `#import` block and before `@implementation MainFrameViewController`:

```objc
#if !TARGET_OS_TV

typedef NS_ENUM(NSInteger, MoonlightSection) {
    MoonlightSectionHosts,
    MoonlightSectionContinue,
    MoonlightSectionGames,
};

// Hosts a single UIComputerView/UIAppView pinned to the cell's bounds. Those
// classes own their own drawing and callbacks; the cell only supplies a frame.
@interface MoonlightTileCell : UICollectionViewCell
- (void) setTileView:(UIView*)tile;
@end

@implementation MoonlightTileCell

- (void) setTileView:(UIView*)tile {
    [self clearTile];
    tile.frame = self.contentView.bounds;
    tile.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:tile];
}

- (void) clearTile {
    for (UIView* subview in [self.contentView.subviews copy]) {
        [subview removeFromSuperview];
    }
}

- (void) prepareForReuse {
    [super prepareForReuse];
    [self clearTile];
}

@end

// Section header: a title plus an optional trailing button that shows a menu.
@interface MoonlightHeaderView : UICollectionReusableView
@property (nonatomic, readonly) UILabel* titleLabel;
@property (nonatomic, readonly) UIButton* accessoryButton;
@end

@implementation MoonlightHeaderView

- (instancetype) initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.textColor = [UIColor labelColor];

    _accessoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _accessoryButton.tintColor = [MoonlightTheme accentColor];
    [_accessoryButton setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView* row = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _accessoryButton]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
    ]];

    return self;
}

@end

#endif
```

Add `#import "Utils.h"` to the import block if it is not already there.

- [ ] **Step 4: Add section bookkeeping to `MainFrameViewController.m`**

Add to the instance variable block:

```objc
    NSArray<NSNumber*>* _sections;
    NSArray<TemporaryHost*>* _sortedHostList;
```

and delete `UIScrollView* hostScrollView;`.

Add these methods:

```objc
#if !TARGET_OS_TV
- (void) rebuildSections {
    NSMutableArray<NSNumber*>* sections = [NSMutableArray arrayWithObject:@(MoonlightSectionHosts)];

    if (_selectedHost != nil) {
        if ([self findRunningApp:_selectedHost] != nil) {
            [sections addObject:@(MoonlightSectionContinue)];
        }
        [sections addObject:@(MoonlightSectionGames)];
    }

    _sections = sections;
}

- (MoonlightSection) sectionAtIndex:(NSInteger)index {
    return (MoonlightSection)[_sections[index] integerValue];
}

- (void) reloadEverything {
    [self rebuildSections];
    [self.collectionView reloadData];
}
#endif
```

- [ ] **Step 5: Build the compositional layout**

Add to `MainFrameViewController.m`:

```objc
#if !TARGET_OS_TV
- (NSCollectionLayoutBoundarySupplementaryItem*) makeSectionHeader {
    NSCollectionLayoutSize* size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension estimatedDimension:44]];
    return [NSCollectionLayoutBoundarySupplementaryItem boundarySupplementaryItemWithLayoutSize:size
                                                                                   elementKind:UICollectionElementKindSectionHeader
                                                                                     alignment:NSRectAlignmentTop];
}

- (NSCollectionLayoutSection*) makeHostsSection {
    NSCollectionLayoutSize* itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension absoluteDimension:240]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:88]];

    NSCollectionLayoutItem* item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
    NSCollectionLayoutGroup* group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:itemSize
                                                                                  subitems:@[item]];

    NSCollectionLayoutSection* section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.orthogonalScrollingBehavior = UICollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary;
    section.interGroupSpacing = 12;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0, 20, 0, 20);
    section.boundarySupplementaryItems = @[[self makeSectionHeader]];
    return section;
}

- (UICollectionViewLayout*) makeLayout {
    __weak MainFrameViewController* weakSelf = self;

    UICollectionViewCompositionalLayoutConfiguration* config =
        [[UICollectionViewCompositionalLayoutConfiguration alloc] init];
    config.interSectionSpacing = 28;

    return [[UICollectionViewCompositionalLayout alloc]
            initWithSectionProvider:^NSCollectionLayoutSection*(NSInteger index, id<NSCollectionLayoutEnvironment> env) {
        MainFrameViewController* self = weakSelf;
        if (self == nil || index >= self->_sections.count) {
            return nil;
        }

        switch ([self sectionAtIndex:index]) {
            case MoonlightSectionHosts:
                return [self makeHostsSection];
            case MoonlightSectionContinue:
            case MoonlightSectionGames:
                // Added in later commits; until then these sections are empty.
                return [self makeHostsSection];
        }
    } configuration:config];
}
#endif
```

- [ ] **Step 6: Rewrite the data source for sections**

Replace `numberOfSectionsInCollectionView:`, `collectionView:numberOfItemsInSection:`, and `collectionView:cellForItemAtIndexPath:` on the iOS path:

```objc
#if !TARGET_OS_TV
- (NSInteger) numberOfSectionsInCollectionView:(UICollectionView*)collectionView {
    return _sections.count;
}

- (NSInteger) collectionView:(UICollectionView*)collectionView numberOfItemsInSection:(NSInteger)section {
    switch ([self sectionAtIndex:section]) {
        case MoonlightSectionHosts:
            // Every host, plus the trailing "Add PC" tile.
            return _sortedHostList.count + 1;
        case MoonlightSectionContinue:
            return 0;   // populated in a later commit
        case MoonlightSectionGames:
            return 0;   // populated in a later commit
    }
    return 0;
}

- (UICollectionViewCell*) collectionView:(UICollectionView*)collectionView cellForItemAtIndexPath:(NSIndexPath*)indexPath {
    MoonlightTileCell* cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"tile" forIndexPath:indexPath];

    if ([self sectionAtIndex:indexPath.section] == MoonlightSectionHosts) {
        if (indexPath.item < _sortedHostList.count) {
            TemporaryHost* host = _sortedHostList[indexPath.item];
            UIComputerView* hostView = [[UIComputerView alloc] initWithComputer:host andCallback:self];
            [hostView setHostSelected:(host == _selectedHost)];
            [cell setTileView:hostView];
        }
        else {
            [cell setTileView:[[UIComputerView alloc] initForAddWithCallback:self]];
        }
    }

    return cell;
}

- (UICollectionReusableView*) collectionView:(UICollectionView*)collectionView
           viewForSupplementaryElementOfKind:(NSString*)kind
                                 atIndexPath:(NSIndexPath*)indexPath {
    MoonlightHeaderView* header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                     withReuseIdentifier:@"header"
                                                                            forIndexPath:indexPath];
    header.accessoryButton.hidden = YES;
    header.accessoryButton.menu = nil;

    switch ([self sectionAtIndex:indexPath.section]) {
        case MoonlightSectionHosts:
            header.titleLabel.text = @"PCs";
            break;
        case MoonlightSectionContinue:
            header.titleLabel.text = @"Continue";
            break;
        case MoonlightSectionGames:
            header.titleLabel.text = @"Games";
            break;
    }

    return header;
}
#endif
```

A fresh `UIComputerView` per cell mirrors what the old code did per app tile, and host counts are in single digits.
`// ponytail: rebuilds the tile view on every dequeue instead of reconfiguring; add a -configureForHost: reuse path if a large host list ever scrolls badly.`

- [ ] **Step 7: Rewire `viewDidLoad`, `updateHosts`, and the state transitions**

In `viewDidLoad`, delete the `hostScrollView` creation block:

```objc
    hostScrollView = [[ComputerScrollView alloc] init];
    hostScrollView.frame = CGRectMake(...);
    [hostScrollView setShowsHorizontalScrollIndicator:NO];
    hostScrollView.delaysContentTouches = NO;
```

and add, inside the existing `#if !TARGET_OS_TV` region:

```objc
    // Must run before the layout is installed: setCollectionViewLayout: can
    // query the data source, which indexes into _sections.
    [self rebuildSections];

    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[MoonlightTileCell class]
            forCellWithReuseIdentifier:@"tile"];
    [self.collectionView registerClass:[MoonlightHeaderView class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:@"header"];
    [self.collectionView setCollectionViewLayout:[self makeLayout] animated:NO];
```

Replace the tail of `viewDidLoad`:

```objc
    if ([hostList count] == 1) {
        [self hostClicked:[hostList anyObject] view:nil];
    }
    else {
        [self updateTitle];
        [self.view addSubview:hostScrollView];
    }
```

with:

```objc
    if ([hostList count] == 1) {
        [self hostClicked:[hostList anyObject] view:nil];
    }
    else {
        [self updateTitle];
        [self reloadEverything];
    }
```

Rewrite `updateHosts` for iOS — it no longer positions views by hand:

```objc
- (void)updateHosts {
    Log(LOG_I, @"Updating hosts...");

    @synchronized (hostList) {
        _sortedHostList = [[hostList allObjects] sortedArrayUsingSelector:@selector(compareName:)];

        for (TemporaryHost* comp in _sortedHostList) {
            // Start jobs to decode the box art in advance
            for (TemporaryApp* app in comp.appList) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                    [self updateBoxArtCacheForApp:app];
                });
            }
        }
    }

    [self updateHostShortcuts];
    [self updateTitle];
    [self reloadEverything];
}
```

Delete `getCompViewX:addComp:prevEdge:` entirely.

In `showHostSelectionView`, replace `[self.collectionView reloadData]; [self.view addSubview:hostScrollView];` with `[self reloadEverything];`. Everything above it — the `_appManager stopRetrieving`, `_showHiddenApps`, `_selectedHost`, `_sortedAppList`, and `_deepLinkAppQuery` resets — stays exactly as it is; that method is the choke point that abandons a pending deep link.

In `updateAppsForHost:`, replace `[hostScrollView removeFromSuperview]; [self.collectionView reloadData];` with `[self reloadEverything];`.

Delete `adjustScrollViewForSafeArea:` and `viewSafeAreaInsetsDidChange` — compositional layout section insets handle this, and the old method's `hostScrollView` reference no longer compiles.

Delete `#import "ComputerScrollView.h"` from the import block.

- [ ] **Step 8: Confirm nothing references the removed scroll view**

```bash
grep -n "hostScrollView\|ComputerScrollView\|getCompViewX\|adjustScrollViewForSafeArea" Limelight/ViewControllers/MainFrameViewController.m
```

Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add Limelight/UIComputerView.h Limelight/UIComputerView.m \
        Limelight/ViewControllers/MainFrameViewController.m
git commit -m "$(cat <<'EOF'
Rebuild the main screen on a compositional layout with a PCs section

Hosts move from a hand-positioned horizontal UIScrollView into an
orthogonally-scrolling section of the main collection view, so they stay
on screen while a host is selected. UIComputerView becomes an Auto Layout
glass card showing an SF Symbol, the host name, and a real status line
("Paired", "Offline", "Playing <game>") instead of an unlabeled icon.

The Continue and Games sections exist in the enum but are empty until the
following commits.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 10: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(makeHostsSection|rebuildSections|setHostSelected:|statusTextForHost:|MoonlightTileCell)$"
```

**On-device check after sideload:** a "PCs" header with horizontally scrolling glass host cards, each showing its name and status, and a trailing "Add PC" card. Tapping a host still enters its (currently empty) app view; the host row stays visible. Tapping "Add PC" still opens the IP prompt. Long-pressing a host still shows the action sheet.

---

### Task 5: The Games section and the redesigned game tile

**Files:**
- Modify: `Limelight/UIAppView.h`
- Modify: `Limelight/UIAppView.m` (full rewrite of the iOS layout path)
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2), `MoonlightTileCell` / `MoonlightSection` / `sectionAtIndex:` (Task 4)
- Produces: `-[MainFrameViewController makeGamesSectionForEnvironment:] -> NSCollectionLayoutSection*`

- [ ] **Step 1: Rewrite the iOS layout in `UIAppView.m`**

Keep `initWithApp:cache:andCallback:`'s callback wiring, the context menu interaction, `didMoveToSuperview`, `updateLoop`, `appClicked:`, `appLongClicked:`, and `contextMenuInteraction:configurationForMenuAtLocation:` exactly as they are. Replace the fixed-frame subview construction and `positionSubviews`.

New instance variables:

```objc
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
```

In `initWithApp:cache:andCallback:`, replace the iOS `self.frame` / `_appImage` setup with an Auto Layout tree. Add `#import "Utils.h"` at the top of the file.

```objc
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
```

Call `[self buildLayout];` from `initWithApp:cache:andCallback:` on the iOS path, in place of the removed `self.frame` assignment and `_appImage` creation. Delete `self.layer.shouldRasterize = YES;` and `self.layer.rasterizationScale = …` — rasterizing a layer that contains a live glass effect defeats the effect.

Rewrite `updateAppImage` for iOS. It no longer creates and destroys subviews; it only changes their content:

```objc
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
#endif
```

Delete `positionSubviews` on the iOS path. **Keep** the `static UIImage* noImage` variable and its lazy `NoAppImage` load: the tvOS branch of `initWithApp:cache:andCallback:` still assigns it, and this file compiles for both targets. The iOS path simply stops using it — its placeholder is now the tile's own background colour plus the name label.

Replace the iOS `buttonSelected:` / `buttonDeselected:` with the same scale animation used by `UIComputerView`:

```objc
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
#endif
```

`updateLoop` currently diffs `_appOverlay` against `host.currentGame`, pokes `self.superview.layer.shadowOpacity`, and re-sets `alpha`. On iOS all three are obsolete: the cell draws no shadow, and `updateAppImage` is now cheap because it mutates existing views instead of rebuilding them. The method body is not inside an `#if` today, so guard the split:

```objc
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
```

- [ ] **Step 2: Add the Games layout section to `MainFrameViewController.m`**

```objc
#if !TARGET_OS_TV
- (NSCollectionLayoutSection*) makeGamesSectionForEnvironment:(id<NSCollectionLayoutEnvironment>)env {
    CGFloat available = env.container.effectiveContentSize.width - 40;

    // Aim for ~170pt-wide posters, minimum two columns on the narrowest phone.
    NSInteger columns = MAX(2, (NSInteger)floor(available / 170.0));
    CGFloat columnWidth = available / columns - 12;

    NSCollectionLayoutSize* itemSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0 / columns]
                                       heightDimension:[NSCollectionLayoutDimension fractionalHeightDimension:1.0]];
    NSCollectionLayoutItem* item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
    item.contentInsets = NSDirectionalEdgeInsetsMake(0, 6, 0, 6);

    // Box art is 3:4, plus room for two lines of name beneath it.
    NSCollectionLayoutSize* groupSize =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:columnWidth * 4.0 / 3.0 + 44]];
    NSCollectionLayoutGroup* group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize
                                                                                    subitem:item
                                                                                      count:columns];

    NSCollectionLayoutSection* section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.interGroupSpacing = 16;
    section.contentInsets = NSDirectionalEdgeInsetsMake(0, 14, 20, 14);
    section.boundarySupplementaryItems = @[[self makeSectionHeader]];
    return section;
}
#endif
```

In `makeLayout`'s switch, replace the `MoonlightSectionGames` fall-through with `return [self makeGamesSectionForEnvironment:env];`.

- [ ] **Step 3: Populate the Games section**

In `collectionView:numberOfItemsInSection:`, change the `MoonlightSectionGames` case to `return _sortedAppList.count;`.

In `collectionView:cellForItemAtIndexPath:`, add the games branch:

```objc
    else if ([self sectionAtIndex:indexPath.section] == MoonlightSectionGames) {
        TemporaryApp* app = _sortedAppList[indexPath.item];
        [cell setTileView:[[UIAppView alloc] initWithApp:app cache:_boxArtCache andCallback:self]];
    }
```

Delete the old shadow, border, and manual scale-transform code that used to live in `cellForItemAtIndexPath:`:

```objc
    UIBezierPath *shadowPath = [UIBezierPath bezierPathWithRect:cell.bounds];
    cell.layer.masksToBounds = NO;
    cell.layer.shadowColor = [UIColor blackColor].CGColor;
    cell.layer.shadowOffset = CGSizeMake(1.0f, 5.0f);
    cell.layer.shadowPath = shadowPath.CGPath;
    cell.layer.borderWidth = 1;
    cell.layer.borderColor = [[UIColor colorWithRed:0 green:0 blue:0 alpha:0.3f] CGColor];
```

- [ ] **Step 4: Confirm the old tile geometry is gone**

```bash
grep -n "positionSubviews\|shouldRasterize\|NoAppImage\|shadowPath" Limelight/UIAppView.m Limelight/ViewControllers/MainFrameViewController.m
```

Expected: no output for the iOS path. Matches inside `#if TARGET_OS_TV` blocks are fine and must be left alone.

- [ ] **Step 5: Commit**

```bash
git add Limelight/UIAppView.h Limelight/UIAppView.m \
        Limelight/ViewControllers/MainFrameViewController.m
git commit -m "$(cat <<'EOF'
Redesign the game grid

Adaptive poster grid driven by the layout environment's width instead of
a fixed item size scaled by an affine transform, and every tile now shows
its name — the old view rendered the name only when box art was missing,
so a grid of arted games was a grid of unlabeled pictures.

Running games get a play glyph, HDR and hidden apps get glass badges, and
the per-cell drop shadow and border are gone. UIAppView mutates its
subviews on refresh instead of tearing them down and rebuilding them.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 6: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(makeGamesSectionForEnvironment:|buildLayout)$"
```

**On-device check after sideload:** selecting a host shows a "Games" header and a poster grid that reflows between portrait, landscape, and iPad split view. Every tile has a readable name. A running game shows a play glyph. Tapping launches; long-pressing shows the action sheet. Hidden apps (via "View All Apps") are dimmed with a badge.

---

### Task 6: The Continue hero and section header menus

**Files:**
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2), `MoonlightHeaderView` / `MoonlightSection` (Task 4)
- Produces:
  - `MoonlightHeroCell` (in `MainFrameViewController.m`): `-configureWithApp:hostName:`, `onResume` / `onQuit` block properties, reuse id `@"hero"`
  - `-[MainFrameViewController quitRunningApp:(TemporaryApp*)app then:(void (^)(void))completion]` — the quit path extracted from `appLongClicked:view:` so both entry points share it
  - `-[MainFrameViewController gamesMenu] -> UIMenu*`

- [ ] **Step 1: Add `MoonlightHeroCell` to `MainFrameViewController.m`**

Insert after `MoonlightHeaderView`'s `@implementation`, inside the same `#if !TARGET_OS_TV` region:

```objc
// The "Continue" cell: the game currently running on the selected host, with
// its two actions surfaced instead of buried in a long-press action sheet.
@interface MoonlightHeroCell : UICollectionViewCell
@property (nonatomic, copy) void (^onResume)(void);
@property (nonatomic, copy) void (^onQuit)(void);
- (void) configureWithApp:(TemporaryApp*)app hostName:(NSString*)hostName artwork:(UIImage*)artwork;
@end

@implementation MoonlightHeroCell {
    UIVisualEffectView* _glass;
    UIImageView* _artView;
    UILabel* _titleLabel;
    UILabel* _subtitleLabel;
    UIButton* _resumeButton;
    UIButton* _quitButton;
}

- (instancetype) initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    _glass = [MoonlightTheme glassViewWithTint:nil];
    _glass.layer.cornerRadius = [MoonlightTheme cardCornerRadius];
    _glass.layer.cornerCurve = kCACornerCurveContinuous;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_glass];

    _artView = [[UIImageView alloc] init];
    _artView.contentMode = UIViewContentModeScaleAspectFill;
    _artView.clipsToBounds = YES;
    _artView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    _artView.layer.cornerRadius = [MoonlightTheme tileCornerRadius];
    _artView.layer.cornerCurve = kCACornerCurveContinuous;
    _artView.translatesAutoresizingMaskIntoConstraints = NO;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle3];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.numberOfLines = 2;

    _subtitleLabel = [[UILabel alloc] init];
    _subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _subtitleLabel.textColor = [UIColor secondaryLabelColor];

    _resumeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _resumeButton.configuration = [MoonlightTheme glassButtonWithTitle:@"Resume"
                                                                 image:[UIImage systemImageNamed:@"play.fill"]
                                                             prominent:YES];
    [_resumeButton addTarget:self action:@selector(resumeTapped) forControlEvents:UIControlEventPrimaryActionTriggered];

    _quitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _quitButton.configuration = [MoonlightTheme glassButtonWithTitle:@"Quit"
                                                               image:[UIImage systemImageNamed:@"stop.fill"]
                                                           prominent:NO];
    [_quitButton addTarget:self action:@selector(quitTapped) forControlEvents:UIControlEventPrimaryActionTriggered];

    UIStackView* buttons = [[UIStackView alloc] initWithArrangedSubviews:@[_resumeButton, _quitButton]];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 10;

    UIView* spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];

    UIStackView* textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel, spacer, buttons]];
    textStack.axis = UILayoutConstraintAxisVertical;
    textStack.alignment = UIStackViewAlignmentLeading;
    textStack.spacing = 4;
    textStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.contentView addSubview:_artView];
    [self.contentView addSubview:textStack];

    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],

        [_artView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [_artView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],
        [_artView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_artView.widthAnchor constraintEqualToAnchor:_artView.heightAnchor multiplier:3.0f / 4.0f],

        [textStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [textStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16],
        [textStack.leadingAnchor constraintEqualToAnchor:_artView.trailingAnchor constant:16],
        [textStack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
    ]];

    return self;
}

- (void) configureWithApp:(TemporaryApp*)app hostName:(NSString*)hostName artwork:(UIImage*)artwork {
    _titleLabel.text = app.name;
    _subtitleLabel.text = [NSString stringWithFormat:@"Running on %@", hostName];
    _artView.image = artwork;
}

- (void) resumeTapped {
    if (self.onResume) {
        self.onResume();
    }
}

- (void) quitTapped {
    if (self.onQuit) {
        self.onQuit();
    }
}

@end
```

- [ ] **Step 2: Extract the quit logic so the hero and the action sheet share it**

`appLongClicked:view:` contains a ~60-line quit implementation inside its action handler. Move that body verbatim into a new method and call it from both places — patching only the hero would leave the action sheet with a divergent copy.

Add to `MainFrameViewController.m`:

```objc
#if !TARGET_OS_TV
// Quits the app currently running on its host, then runs completion on the
// main thread if the quit succeeded. Displays its own failure alert.
- (void) quitRunningApp:(TemporaryApp*)currentApp then:(void (^)(void))completion {
    [self showLoadingFrame: ^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            HttpManager* hMan = [[HttpManager alloc] initWithHost:currentApp.host];
            HttpResponse* quitResponse = [[HttpResponse alloc] init];
            HttpRequest* quitRequest = [HttpRequest requestForResponse:quitResponse withUrlRequest:[hMan newQuitAppRequest]];

            [self->_discMan pauseDiscoveryForHost:currentApp.host];
            [hMan executeRequestSynchronously:quitRequest];
            if (quitResponse.statusCode == 200) {
                ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
                [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                                                    fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
                if (![serverInfoResp isStatusOk] || [[serverInfoResp getStringTag:@"state"] hasSuffix:@"_SERVER_BUSY"]) {
                    // Newer GFE reports success even when another client's app
                    // survives the quit. Patch the response so the UI behaves.
                    quitResponse.statusCode = 599;
                }
                else if ([serverInfoResp isStatusOk]) {
                    [serverInfoResp populateHost:currentApp.host];
                }
            }
            [self->_discMan resumeDiscoveryForHost:currentApp.host];

            if (quitResponse.statusCode != 200) {
                UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Quitting App Failed"
                                                                               message:@"Failed to quit app. If this app was started by "
                                            "another device, you'll need to quit from that device."
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateAppsForHost:currentApp.host];
                    [self hideLoadingFrame: ^{
                        [[self activeViewController] presentViewController:alert animated:YES completion:nil];
                    }];
                });
                return;
            }

            currentApp.host.currentGame = @"0";
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion != nil) {
                    [self hideLoadingFrame:completion];
                }
                else {
                    [self hideLoadingFrame:^{
                        [self updateAppsForHost:currentApp.host];
                    }];
                }
            });
        });
    }];
}
#endif
```

Then replace the body of the "Quit App" / "Quit Running App and Start" handler in `appLongClicked:view:` with a call to it:

```objc
        [alertController addAction:[UIAlertAction actionWithTitle:
                                    [app.id isEqualToString:currentApp.id] ? @"Quit App" : @"Quit Running App and Start"
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction* action){
            Log(LOG_I, @"Quitting application: %@", currentApp.name);
            BOOL startAfterQuit = ![app.id isEqualToString:currentApp.id];
            [self quitRunningApp:currentApp then:^{
                if (startAfterQuit) {
                    [self prepareToStreamApp:app];
                    [self performSegueWithIdentifier:@"createStreamFrame" sender:nil];
                }
                else {
                    [self updateAppsForHost:app.host];
                }
            }];
        }]];
```

- [ ] **Step 3: Add the Continue layout section and register the cell**

Add to `MainFrameViewController.m`:

```objc
#if !TARGET_OS_TV
- (NSCollectionLayoutSection*) makeContinueSection {
    NSCollectionLayoutSize* size =
        [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0]
                                       heightDimension:[NSCollectionLayoutDimension absoluteDimension:172]];

    NSCollectionLayoutItem* item = [NSCollectionLayoutItem itemWithLayoutSize:size];
    NSCollectionLayoutGroup* group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:size subitems:@[item]];

    NSCollectionLayoutSection* section = [NSCollectionLayoutSection sectionWithGroup:group];
    section.contentInsets = NSDirectionalEdgeInsetsMake(0, 20, 0, 20);
    section.boundarySupplementaryItems = @[[self makeSectionHeader]];
    return section;
}
#endif
```

In `makeLayout`'s switch, change the `MoonlightSectionContinue` case to `return [self makeContinueSection];`.

In `viewDidLoad`, next to the other registrations:

```objc
    [self.collectionView registerClass:[MoonlightHeroCell class]
            forCellWithReuseIdentifier:@"hero"];
```

- [ ] **Step 4: Populate the Continue section**

In `collectionView:numberOfItemsInSection:`, change the `MoonlightSectionContinue` case to `return 1;`. (`rebuildSections` already omits the section entirely when nothing is running.)

In `collectionView:cellForItemAtIndexPath:`, handle it before the tile dequeue, since it uses a different reuse identifier:

```objc
    if ([self sectionAtIndex:indexPath.section] == MoonlightSectionContinue) {
        TemporaryApp* running = [self findRunningApp:_selectedHost];
        MoonlightHeroCell* hero = [collectionView dequeueReusableCellWithReuseIdentifier:@"hero" forIndexPath:indexPath];
        [hero configureWithApp:running
                      hostName:_selectedHost.name
                       artwork:[_boxArtCache objectForKey:running]];

        __weak MainFrameViewController* weakSelf = self;
        hero.onResume = ^{
            MainFrameViewController* strongSelf = weakSelf;
            [strongSelf->_appManager stopRetrieving];
            [strongSelf prepareToStreamApp:running];
            [strongSelf performSegueWithIdentifier:@"createStreamFrame" sender:nil];
        };
        hero.onQuit = ^{
            MainFrameViewController* strongSelf = weakSelf;
            [strongSelf quitRunningApp:running then:^{
                [strongSelf updateAppsForHost:strongSelf->_selectedHost];
            }];
        };

        return hero;
    }
```

Place this at the top of the method, before `MoonlightTileCell* cell = …`.

- [ ] **Step 5: Add the Games header menu**

Add to `MainFrameViewController.m`:

```objc
#if !TARGET_OS_TV
- (UIMenu*) gamesMenu {
    TemporaryHost* host = _selectedHost;
    if (host == nil) {
        return nil;
    }

    NSMutableArray<UIAction*>* actions = [NSMutableArray array];

    [actions addObject:[UIAction actionWithTitle:(_showHiddenApps ? @"Hide Hidden Apps" : @"Show Hidden Apps")
                                           image:[UIImage systemImageNamed:@"eye"]
                                      identifier:nil
                                         handler:^(UIAction* action) {
        self->_showHiddenApps = !self->_showHiddenApps;
        [self updateAppsForHost:host];
    }]];

    [actions addObject:[UIAction actionWithTitle:@"Test Network"
                                           image:[UIImage systemImageNamed:@"network"]
                                      identifier:nil
                                         handler:^(UIAction* action) {
        [self testNetwork];
    }]];

    [actions addObject:[UIAction actionWithTitle:@"Connection Help"
                                           image:[UIImage systemImageNamed:@"questionmark.circle"]
                                      identifier:nil
                                         handler:^(UIAction* action) {
        [Utils launchUrl:@"https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"];
    }]];

    UIAction* remove = [UIAction actionWithTitle:@"Remove PC"
                                           image:[UIImage systemImageNamed:@"trash"]
                                      identifier:nil
                                         handler:^(UIAction* action) {
        [self removeHost:host];
    }];
    remove.attributes = UIMenuElementAttributesDestructive;
    [actions addObject:remove];

    return [UIMenu menuWithTitle:host.name children:actions];
}
#endif
```

This calls two helpers that must be extracted from `hostLongClicked:view:`, again so the two entry points cannot diverge. Move the `Test Network` action's body and the `Remove Host` action's body into:

```objc
#if !TARGET_OS_TV
- (void) testNetwork {
    [self showLoadingFrame:^{
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // May take a while, so keep it off the main thread.
            unsigned int portTestResult = LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL);
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self hideLoadingFrame:^{
                    NSString* message;

                    if (portTestResult == 0) {
                        message = @"This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.\n\nVisit the Moonlight Setup Guide on GitHub for additional setup help and troubleshooting steps.";
                    }
                    else if (portTestResult == ML_TEST_RESULT_INCONCLUSIVE) {
                        message = @"The network test could not be performed because none of Moonlight's connection testing servers were reachable. Check your Internet connection or try again later.";
                    }
                    else {
                        char blockedPorts[512];
                        LiStringifyPortFlags(portTestResult, "\n", blockedPorts, sizeof(blockedPorts));
                        message = [NSString stringWithFormat:@"Your current network connection seems to be blocking Moonlight. Streaming may not work while connected to this network.\n\nThe following network ports were blocked:\n%s", blockedPorts];
                    }

                    UIAlertController* netTestAlert = [UIAlertController alertControllerWithTitle:@"Network Test Complete" message:message preferredStyle:UIAlertControllerStyleAlert];
                    [netTestAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [[self activeViewController] presentViewController:netTestAlert animated:YES completion:nil];
                }];
            });
        });
    }];
}

- (void) removeHost:(TemporaryHost*)host {
    [self->_discMan removeHostFromDiscovery:host];
    DataManager* dataMan = [[DataManager alloc] init];
    [dataMan removeHost:host];
    @synchronized(hostList) {
        [hostList removeObject:host];
        [self updateAllHosts:[hostList allObjects]];
    }
    if (host == _selectedHost) {
        [self showHostSelectionView];
    }
}
#endif
```

and replace both action handler bodies in `hostLongClicked:view:` with `[self testNetwork];` and `[self removeHost:host];`. The `removeHost:` version adds a reset when the removed host was the selected one — previously the app kept showing a deleted host's games.

- [ ] **Step 6: Wire the menu into the header**

In `collectionView:viewForSupplementaryElementOfKind:atIndexPath:`, replace the `MoonlightSectionGames` case:

```objc
        case MoonlightSectionGames: {
            header.titleLabel.text = @"Games";
            header.accessoryButton.hidden = NO;
            [header.accessoryButton setImage:[UIImage systemImageNamed:@"ellipsis.circle"] forState:UIControlStateNormal];
            [header.accessoryButton setTitle:nil forState:UIControlStateNormal];
            header.accessoryButton.menu = [self gamesMenu];
            header.accessoryButton.showsMenuAsPrimaryAction = YES;
            break;
        }
```

- [ ] **Step 7: Confirm the quit logic exists in exactly one place**

```bash
grep -c "newQuitAppRequest" Limelight/ViewControllers/MainFrameViewController.m
grep -c "LiTestClientConnectivity(CONN_TEST_SERVER, 443, ML_PORT_FLAG_ALL)" Limelight/ViewControllers/MainFrameViewController.m
```

Expected: `1` and `1`. A `2` means an old copy survived the extraction.

- [ ] **Step 8: Commit**

```bash
git add Limelight/ViewControllers/MainFrameViewController.m
git commit -m "$(cat <<'EOF'
Surface the running game and the per-host actions

A Continue section shows whatever is running on the selected host with
Resume and Quit as real buttons, and the Games header gets a menu holding
Show Hidden Apps, Test Network, Connection Help, and Remove PC. All of
these were previously reachable only by long-pressing a tile, which no
first-time user finds.

The quit sequence, the network test, and host removal are extracted into
single methods shared by the new buttons and the existing action sheets,
so the two entry points cannot drift apart. Removing the selected host now
also resets the app grid instead of leaving a deleted PC's games on screen.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 9: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(quitRunningApp:then:|gamesMenu|testNetwork|removeHost:|configureWithApp:hostName:artwork:)$"
```

**On-device check after sideload:** with a game running on the host, a "Continue" card appears above the grid with working Resume and Quit buttons. The Games header shows a `•••` button whose menu toggles hidden apps, runs the network test, and removes the PC. The long-press action sheet still works identically.

---

### Task 7: Search, pull-to-refresh, and empty states

**Files:**
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`

**Interfaces:**
- Consumes: everything from Tasks 4–6
- Produces:
  - `_searchText` — current filter string, applied inside `updateAppsForHost:`
  - `-[MainFrameViewController updateEmptyState]`
  - `MainFrameViewController` conforms to `UISearchResultsUpdating`

- [ ] **Step 1: Declare the conformance and state**

In `MainFrameViewController.m`, add a class extension above `@implementation MainFrameViewController` (the header must not gain iOS-only protocol conformances that tvOS would also see):

```objc
#if !TARGET_OS_TV
@interface MainFrameViewController () <UISearchResultsUpdating>
@end
#endif
```

Add to the instance variable block:

```objc
    NSString* _searchText;
```

- [ ] **Step 2: Apply the filter inside `updateAppsForHost:`**

`updateAppsForHost:` is the single place `_sortedAppList` is built, so filtering there means search, hidden-app toggling, and app-list refreshes cannot disagree. Replace its filtering block:

```objc
    _sortedAppList = [host.appList allObjects];
    _sortedAppList = [_sortedAppList sortedArrayUsingSelector:@selector(compareName:)];

    NSMutableArray* visibleAppList = [NSMutableArray array];
    for (TemporaryApp* app in _sortedAppList) {
        if (app.hidden && !_showHiddenApps) {
            continue;
        }
        if (_searchText.length > 0 &&
            [app.name rangeOfString:_searchText options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        [visibleAppList addObject:app];
    }
    _sortedAppList = visibleAppList;

    [self reloadEverything];
```

`reloadEverything` calls `updateEmptyState` (Step 4), so do not call it here as well. `_searchText` is declared unguarded in the ivar block, so this compiles for both targets.

- [ ] **Step 3: Add the search controller and refresh control**

In `viewDidLoad`, inside the `#if !TARGET_OS_TV` region:

```objc
    UISearchController* search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search games";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;

    UIRefreshControl* refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(pullToRefresh:) forControlEvents:UIControlEventValueChanged];
    self.collectionView.refreshControl = refresh;
```

and the two handlers:

```objc
#if !TARGET_OS_TV
- (void) updateSearchResultsForSearchController:(UISearchController*)searchController {
    _searchText = searchController.searchBar.text;

    if (_selectedHost != nil) {
        [self updateAppsForHost:_selectedHost];
    }
}

- (void) pullToRefresh:(UIRefreshControl*)sender {
    [_discMan resetDiscoveryState];
    [_discMan startDiscovery];

    if (_selectedHost != nil && _selectedHost.pairState == PairStatePaired) {
        // nil view: not a user tap on a host, so skip the cached-app-list fast
        // path and refetch serverinfo. See hostClicked:view:.
        [self hostClicked:_selectedHost view:nil];
    }

    [sender endRefreshing];
}
#endif
```

- [ ] **Step 4: Add empty states**

```objc
#if !TARGET_OS_TV
- (void) updateEmptyState {
    if (_selectedHost == nil && _sortedHostList.count == 0) {
        UIContentUnavailableConfiguration* config = [UIContentUnavailableConfiguration loadingConfiguration];
        config.text = @"Looking for PCs";
        config.secondaryText = @"Moonlight is searching your network. Make sure your PC is awake and running Sunshine or GeForce Experience.";
        self.contentUnavailableConfiguration = config;
        return;
    }

    if (_selectedHost == nil) {
        UIContentUnavailableConfiguration* config = [UIContentUnavailableConfiguration emptyConfiguration];
        config.image = [UIImage systemImageNamed:@"desktopcomputer"];
        config.text = @"Choose a PC";
        config.secondaryText = @"Pick one of the PCs above to see its games.";
        self.contentUnavailableConfiguration = config;
        return;
    }

    if (_sortedAppList.count == 0 && _searchText.length > 0) {
        self.contentUnavailableConfiguration = [UIContentUnavailableConfiguration searchConfiguration];
        return;
    }

    self.contentUnavailableConfiguration = nil;
}
#endif
```

`UIContentUnavailableConfiguration` is iOS 17+, comfortably inside the 26.0 floor, and it renders above the collection view without disturbing the layout. Call `[self updateEmptyState];` at the end of `reloadEverything` as well, so host-list and host-selection changes refresh it, not just app-list changes.

- [ ] **Step 5: Drop the placeholder titles**

`updateTitle` currently puts status text in the navigation bar. With real empty states, shorten it:

```objc
- (void)updateTitle {
    if (_selectedHost != nil) {
        self.title = _selectedHost.name;
    }
    else {
        self.title = @"Moonlight";
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add Limelight/ViewControllers/MainFrameViewController.m
git commit -m "$(cat <<'EOF'
Add search, pull-to-refresh, and real empty states

Filtering happens inside updateAppsForHost:, the one place _sortedAppList
is built, so search and the hidden-apps toggle cannot disagree.

"Searching for PCs on your network..." moves out of the navigation title
and into a UIContentUnavailableConfiguration that can actually explain
itself; the title is now just the host name, or "Moonlight".

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 7: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(updateEmptyState|pullToRefresh:|updateSearchResultsForSearchController:)$"
```

**On-device check after sideload:** with no PCs paired, a spinner and "Looking for PCs" fill the screen. With a PC selected, pulling down re-runs discovery. Typing in the search field filters the grid live and shows the standard no-results view when nothing matches.

---

### Task 8: Box-art ambient background

**Files:**
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`

**Interfaces:**
- Consumes: `+[MoonlightTheme ambientColorForImage:]` (Task 2)
- Produces:
  - `_ambientCache` — `NSCache` of `TemporaryApp` → `UIColor`
  - `-[MainFrameViewController ambientColorForApp:] -> UIColor*`
  - `-[MainFrameViewController updateAmbientBackground]`

- [ ] **Step 1: Add the gradient layer and cache**

Add to the instance variable block:

```objc
    NSCache* _ambientCache;
    CAGradientLayer* _ambientLayer;
```

In `viewDidLoad`, inside the `#if !TARGET_OS_TV` region and before the layout is installed:

```objc
    _ambientCache = [[NSCache alloc] init];

    _ambientLayer = [CAGradientLayer layer];
    _ambientLayer.type = kCAGradientLayerRadial;
    _ambientLayer.startPoint = CGPointMake(0.5, 0.0);
    _ambientLayer.endPoint = CGPointMake(1.4, 1.4);
    _ambientLayer.colors = @[(id)[UIColor clearColor].CGColor, (id)[UIColor clearColor].CGColor];

    UIView* backdrop = [[UIView alloc] initWithFrame:self.collectionView.bounds];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.userInteractionEnabled = NO;
    [backdrop.layer addSublayer:_ambientLayer];
    self.collectionView.backgroundView = backdrop;
```

The gradient layer needs to track the backdrop's size:

```objc
- (void) viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

#if !TARGET_OS_TV
    // CALayer has no autoresizing, and the implicit animation on a bounds
    // change would make the tint lag behind rotation.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ambientLayer.frame = self.collectionView.backgroundView.bounds;
    [CATransaction commit];
#endif
}
```

- [ ] **Step 2: Compute and cache the colour on the existing box-art pass**

Extend `updateBoxArtCacheForApp:` — it already runs on a background queue for every app of every host:

```objc
- (void) updateBoxArtCacheForApp:(TemporaryApp*)app {
    if ([_boxArtCache objectForKey:app] == nil) {
        UIImage* image = [MainFrameViewController loadBoxArtForCaching:app];
        if (image != nil) {
            [_boxArtCache setObject:image forKey:app];
        }
    }

#if !TARGET_OS_TV
    if ([_ambientCache objectForKey:app] == nil) {
        UIColor* ambient = [MoonlightTheme ambientColorForImage:[_boxArtCache objectForKey:app]];
        if (ambient != nil) {
            [_ambientCache setObject:ambient forKey:app];
        }
    }
#endif
}
```

- [ ] **Step 3: Pick and apply the tint**

```objc
#if !TARGET_OS_TV
- (UIColor*) ambientColorForApp:(TemporaryApp*)app {
    if (app == nil) {
        return nil;
    }

    UIColor* cached = [_ambientCache objectForKey:app];
    if (cached != nil) {
        return cached;
    }

    // Not sampled yet — compute it now from whatever art we already decoded.
    UIColor* ambient = [MoonlightTheme ambientColorForImage:[_boxArtCache objectForKey:app]];
    if (ambient != nil) {
        [_ambientCache setObject:ambient forKey:app];
    }
    return ambient;
}

- (void) updateAmbientBackground {
    // The running game owns the tint; otherwise the first game in the grid does.
    TemporaryApp* source = [self findRunningApp:_selectedHost];
    if (source == nil) {
        source = _sortedAppList.firstObject;
    }

    UIColor* ambient = [self ambientColorForApp:source] ?: [MoonlightTheme accentColor];

    NSArray* colors = @[(id)[ambient colorWithAlphaComponent:0.38f].CGColor,
                        (id)[ambient colorWithAlphaComponent:0.0f].CGColor];

    CABasicAnimation* fade = [CABasicAnimation animationWithKeyPath:@"colors"];
    fade.fromValue = _ambientLayer.colors;
    fade.toValue = colors;
    fade.duration = 0.45;

    _ambientLayer.colors = colors;
    [_ambientLayer addAnimation:fade forKey:@"ambient"];
}
#endif
```

`findRunningApp:` returns nil for a nil host, so no extra guard is needed when nothing is selected.

- [ ] **Step 4: Call it whenever content changes**

Add `[self updateAmbientBackground];` to `reloadEverything`, after `[self.collectionView reloadData];`. That covers host selection, app-list refresh, search, and the return from streaming, because every one of those paths already funnels through it.

Also add `[self->_ambientCache removeAllObjects];` next to the two existing `[_boxArtCache removeAllObjects]` calls in `didReceiveMemoryWarning` and `viewDidDisappear:` — the two caches must be purged together or the ambient cache will outlive the art it was derived from.

- [ ] **Step 5: Commit**

```bash
git add Limelight/ViewControllers/MainFrameViewController.m
git commit -m "$(cat <<'EOF'
Tint the main screen from the running game's box art

Average colour of the running game's cover (or the first game's, when
nothing is running) drives a soft radial gradient behind the grid.
Sampling piggybacks on the existing background box-art decode pass and
lands in a cache purged alongside it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 6: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(updateAmbientBackground|ambientColorForApp:)$"
```

**On-device check after sideload:** the background carries a soft colour wash drawn from the box art, changing when you switch hosts or start a game. This is the one piece with real arithmetic and no way to unit-test it, so look specifically for: a tint that is neither washed-out grey nor a garish full-saturation block, and no visible flash on rotation.

---

### Task 9: Rebuild Settings as a native list

**Files:**
- Modify: `Limelight/ViewControllers/SettingsViewController.h`
- Modify: `Limelight/ViewControllers/SettingsViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2), the sheet presenter from Task 3
- Produces: `-[SettingsViewController saveSettings]` reads instance variables instead of outlets; every other public behaviour is unchanged

This deviates from the spec on one point: an inset-grouped `UITableView` rather than a compositional list layout. It reaches the same iOS 26 appearance with materially less code and no diffable data source, which matters when there is no local compiler.

`SettingsViewController.m` is in the **iOS target only** — it is absent from the tvOS `Sources` build phase. Every `#if !TARGET_OS_TV` shown below could be dropped; they are written out anyway to match the surrounding file's existing style, and the `#if TARGET_OS_TV` blocks already in the file are dead code that may be left alone or deleted.

**All arithmetic is preserved verbatim.** Do not rewrite `bitrateTable`, `resolutionTable`, `isCustomResolution`, `getSliderValueForBitrate:`, `updateBitrate`, or `promptCustomResolutionDialog`. Only their inputs change from outlets to ivars.

- [ ] **Step 1: Replace the outlets in `SettingsViewController.h`**

```objc
#import <UIKit/UIKit.h>
#import "AppDelegate.h"

@interface SettingsViewController : UIViewController

- (void) saveSettings;

@end
```

- [ ] **Step 2: Declare the row model and state in `SettingsViewController.m`**

Insert above `@implementation SettingsViewController`:

```objc
#if !TARGET_OS_TV

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

#endif
```

Extend the implementation's ivar block:

```objc
@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;
#if !TARGET_OS_TV
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
#endif
}
```

- [ ] **Step 3: Load current settings into the ivars**

Replace the body of `viewDidLoad` (keeping the `resolutionTable` population, which must run before any row is built):

```objc
- (void)viewDidLoad {
    [super viewDidLoad];

    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* currentSettings = [dataMan getSettings];

    // Ensure we pick a bitrate that falls exactly onto a slider notch
    _bitrate = bitrateTable[[self getSliderValueForBitrate:[currentSettings.bitrate intValue]]];

    UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
    CGFloat screenScale = window.screen.scale;
    CGFloat safeAreaWidth = (window.frame.size.width - window.safeAreaInsets.left - window.safeAreaInsets.right) * screenScale;
    CGFloat fullScreenWidth = window.frame.size.width * screenScale;
    CGFloat fullScreenHeight = window.frame.size.height * screenScale;

    resolutionTable[0] = CGSizeMake(640, 360);
    resolutionTable[1] = CGSizeMake(1280, 720);
    resolutionTable[2] = CGSizeMake(1920, 1080);
    resolutionTable[3] = CGSizeMake(3840, 2160);
    resolutionTable[4] = CGSizeMake(safeAreaWidth, fullScreenHeight);
    resolutionTable[5] = CGSizeMake(fullScreenWidth, fullScreenHeight);
    resolutionTable[6] = CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]);

    // Don't populate the custom entry unless we have a custom resolution
    if (!isCustomResolution(resolutionTable[6])) {
        resolutionTable[6] = CGSizeMake(0, 0);
    }

#if !TARGET_OS_TV
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
    _optimizeGames = currentSettings.optimizeGames;
    _multiController = currentSettings.multiController;
    _swapABXYButtons = currentSettings.swapABXYButtons;
    _audioOnPC = currentSettings.playAudioOnPC;
    _btMouseSupport = currentSettings.btMouseSupport;
    _useFramePacing = currentSettings.useFramePacing;
    _absoluteTouchMode = currentSettings.absoluteTouchMode;
    _statsOverlay = currentSettings.statsOverlay;
    _enableHdr = currentSettings.enableHdr && _hdrSupported;

    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];

    [self buildTableView];
    [self rebuildRows];
#endif
}
```

- [ ] **Step 4: Build the table view and the row-construction helpers**

```objc
#if !TARGET_OS_TV
- (void) buildTableView {
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"row"];
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
    button.configuration = config;
    button.menu = menu;
    button.showsMenuAsPrimaryAction = YES;
    return button;
}

- (MoonlightSettingsRow*) rowWithTitle:(NSString*)title accessory:(UIView*)accessory {
    MoonlightSettingsRow* row = [[MoonlightSettingsRow alloc] init];
    row.title = title;
    row.accessory = accessory;
    return row;
}
#endif
```

- [ ] **Step 5: Build the rows**

```objc
#if !TARGET_OS_TV
- (NSString*) resolutionTitleForIndex:(NSInteger)index {
    NSArray<NSString*>* names = @[@"360p", @"720p", @"1080p", @"4K", @"Safe Area", @"Full Screen"];
    if (index < names.count) {
        return names[index];
    }
    return [NSString stringWithFormat:@"%d × %d",
            (int)resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width,
            (int)resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height];
}

- (UIMenu*) resolutionMenu {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];

    for (NSInteger i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
        // 4K needs an A9 or later, which we judge by HEVC decode support.
        if (i == 3 && !_hevcSupported) {
            continue;
        }

        NSString* title = (i == RESOLUTION_TABLE_CUSTOM_INDEX) ? @"Custom…" : [self resolutionTitleForIndex:i];
        UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction* a) {
            if (i == RESOLUTION_TABLE_CUSTOM_INDEX) {
                [self promptCustomResolutionDialog];
                return;
            }
            self->_resolutionIndex = i;
            self->_lastSelectedResolutionIndex = i;
            [self updateBitrate];
            [self settingsChanged];
        }];
        action.state = (_resolutionIndex == i) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    return [UIMenu menuWithTitle:@"" children:actions];
}

- (UIMenu*) framerateMenu {
    NSMutableArray<UIAction*>* actions = [NSMutableArray array];

    for (NSNumber* fps in (_support120Fps ? @[@30, @60, @120] : @[@30, @60])) {
        UIAction* action = [UIAction actionWithTitle:[NSString stringWithFormat:@"%@ FPS", fps]
                                               image:nil identifier:nil handler:^(UIAction* a) {
            self->_framerate = fps.integerValue;
            [self updateBitrate];
            [self settingsChanged];
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
    for (NSNumber* pref in prefs) {
        uint32_t value = (uint32_t)pref.unsignedIntValue;
        UIAction* action = [UIAction actionWithTitle:[self codecTitleForPref:value]
                                               image:nil identifier:nil handler:^(UIAction* a) {
            self->_codecPref = value;
            [self settingsChanged];
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

    [titles enumerateObjectsUsingBlock:^(NSString* title, NSUInteger index, BOOL* stop) {
        UIAction* action = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction* a) {
            setter(index);
            [self settingsChanged];
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
    [_bitrateSlider addTarget:self action:@selector(settingsChanged) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];

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
        [stack.leadingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:container.layoutMarginsGuide.trailingAnchor],
    ]];

    [self updateBitrateText];
    return container;
}

- (void) rebuildRows {
    _resolutionButton = [self menuButtonWithTitle:[self resolutionTitleForIndex:_resolutionIndex] menu:[self resolutionMenu]];
    _framerateButton = [self menuButtonWithTitle:[NSString stringWithFormat:@"%ld FPS", (long)_framerate] menu:[self framerateMenu]];
    _codecButton = [self menuButtonWithTitle:[self codecTitleForPref:_codecPref] menu:[self codecMenu]];

    NSArray<NSString*>* controlTitles = @[@"Off", @"Auto", @"Simple", @"Full"];
    _onscreenControlsButton = [self menuButtonWithTitle:controlTitles[_onscreenControls]
                                                   menu:[self indexMenuWithTitles:controlTitles
                                                                          current:_onscreenControls
                                                                           setter:^(NSInteger index) {
        self->_onscreenControls = index;
    }]];
    // On-screen controls are meaningless when touch acts as a touchscreen.
    _onscreenControlsButton.enabled = !_absoluteTouchMode;

    NSArray<NSString*>* pacingTitles = @[@"Lowest Latency", @"Smoothest Video"];
    _framePacingButton = [self menuButtonWithTitle:pacingTitles[_useFramePacing ? 1 : 0]
                                              menu:[self indexMenuWithTitles:pacingTitles
                                                                     current:(_useFramePacing ? 1 : 0)
                                                                      setter:^(NSInteger index) {
        self->_useFramePacing = (index == 1);
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
#endif
```

- [ ] **Step 6: Add the change handlers**

```objc
#if !TARGET_OS_TV
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

- (void) doneTapped {
    [self saveSettings];
    [self dismissViewControllerAnimated:YES completion:nil];
}
#endif
```

Replace the existing `touchModeChanged` (which read an outlet) with:

```objc
- (void) touchModeChanged {
#if !TARGET_OS_TV
    _absoluteTouchMode = (_touchModeControl.selectedSegmentIndex == 1);
    [self settingsChanged];
#endif
}
```

Replace `bitrateSliderMoved` and `updateBitrateText`:

```objc
- (void) bitrateSliderMoved {
    assert(_bitrateSlider.value < (sizeof(bitrateTable) / sizeof(*bitrateTable)));
    _bitrate = bitrateTable[(int)_bitrateSlider.value];
    [self updateBitrateText];
}

- (void) updateBitrateText {
    _bitrateValueLabel.text = [NSString stringWithFormat:@"%.1f Mbps", _bitrate / 1000.];
}
```

`bitrateSliderMoved` deliberately does not call `settingsChanged` — a save per slider tick would thrash Core Data and `rebuildRows` mid-drag would destroy the slider under the user's finger. The `TouchUpInside`/`TouchUpOutside` targets added in `bitrateRowView` do the save.

At the end of `updateBitrate`, replace `[self.bitrateSlider setValue:… animated:YES];` with:

```objc
    _bitrateSlider.value = [self getSliderValueForBitrate:_bitrate];
```

The rest of `updateBitrate`'s interpolation maths is untouched.

- [ ] **Step 7: Rewrite the getters and `saveSettings`**

```objc
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
```

The old width/height getters special-cased "last segment selected" because the 4K segment could be removed at runtime, shifting indices. `_resolutionIndex` is a real index into `resolutionTable`, so that correction is no longer needed — the 4K entry is filtered out of the *menu* in `resolutionMenu` without renumbering the table.

In `promptCustomResolutionDialog`, replace the three `self.resolutionSelector` references:

- both `[self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];` restore calls become `self->_resolutionIndex = self->_lastSelectedResolutionIndex; [self rebuildRows];`
- `self->_lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];` on success becomes `self->_resolutionIndex = RESOLUTION_TABLE_CUSTOM_INDEX; self->_lastSelectedResolutionIndex = RESOLUTION_TABLE_CUSTOM_INDEX;`
- follow the success path's `[self updateBitrate];` with `[self settingsChanged];`

Delete `newResolutionChosen` and `resolutionDisplayViewTapped:` — the menu replaces both.

- [ ] **Step 8: Add the table view data source and delegate**

Declare conformance with a class extension above `@implementation`:

```objc
#if !TARGET_OS_TV
@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@end
#endif
```

```objc
#if !TARGET_OS_TV
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
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];

    for (UIView* subview in [cell.contentView.subviews copy]) {
        [subview removeFromSuperview];
    }
    cell.accessoryView = nil;
    cell.selectionStyle = row.action ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;

    if (row.custom != nil) {
        cell.contentConfiguration = nil;
        row.custom.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:row.custom];
        [NSLayoutConstraint activateConstraints:@[
            [row.custom.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [row.custom.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
            [row.custom.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [row.custom.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
        ]];
        return cell;
    }

    UIListContentConfiguration* content = [UIListContentConfiguration valueCellConfiguration];
    content.text = row.title;
    content.secondaryText = row.subtitle;
    cell.contentConfiguration = content;
    cell.accessoryView = row.accessory;

    return cell;
}

- (void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MoonlightSettingsRow* row = _rows[indexPath.section][indexPath.row];
    if (row.action) {
        row.action();
    }
}
#endif
```

- [ ] **Step 9: Confirm no outlet references survive**

```bash
grep -n "self\.\(bitrateSlider\|bitrateLabel\|framerateSelector\|resolutionSelector\|resolutionDisplayView\|touchModeSelector\|onscreenControlSelector\|optimizeSettingsSelector\|multiControllerSelector\|swapABXYButtonsSelector\|audioOnPCSelector\|codecSelector\|hdrSelector\|framePacingSelector\|btMouseSelector\|statsOverlaySelector\|scrollView\)" Limelight/ViewControllers/SettingsViewController.m
```

Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add Limelight/ViewControllers/SettingsViewController.h \
        Limelight/ViewControllers/SettingsViewController.m
git commit -m "$(cat <<'EOF'
Rebuild Settings as an inset-grouped list

The old screen was a hand-positioned scroll view of fixed-frame segmented
controls laid out at 450pt, which overflowed every iPhone — the 7-way
resolution picker was partly off-screen. Rows are now built in code as an
inset-grouped table with switches, pop-up buttons, and one slider row.

Settings persist on every change instead of when a drawer finished
closing, so prepareToStreamApp: can no longer read a stale value. Every
piece of arithmetic — the bitrate table, the resolution table, the
bitrate interpolation, custom resolution validation — is unchanged; only
the widgets feeding it moved from outlets to instance variables.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 11: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(rebuildRows|settingsChanged|resolutionMenu|codecMenu|bitrateRowView)$"
```

**On-device check after sideload, exercising the arithmetic that has no other test:**
1. Every row is on screen and reachable; nothing is clipped in portrait.
2. Changing resolution or frame rate moves the bitrate slider to a new default (the interpolation table).
3. Resolution → Custom…, enter `2560 × 1080`, accept the warning; the row shows `2560 × 1080` and it survives closing and reopening the sheet.
4. Custom resolution with a width of `0` or `99999` clamps to the 256…4096/8192 range rather than being accepted.
5. Switching Touch Mode to Touchscreen greys out On-Screen Controls.
6. On a non-HDR device, the HDR row reads "Unsupported on this device" and has no switch.
7. Change a setting, close the sheet, start a stream, and confirm the new value took effect.

---

### Task 10: Glass loading frame and stream overlays

**Files:**
- Modify: `Limelight/ViewControllers/LoadingFrameViewController.m`
- Modify: `Limelight/ViewControllers/StreamFrameViewController.m`

**Interfaces:**
- Consumes: `MoonlightTheme` (Task 2)
- Produces: no new public API. `showLoadingFrame:` / `dismissLoadingFrame:` / `isShown` keep their signatures and semantics, so all existing callers are unaffected.

- [ ] **Step 1: Wrap the loading spinner in a glass card**

Replace `viewDidLoad` in `LoadingFrameViewController.m`:

```objc
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
```

Add `#import "Utils.h"` to the file.

- [ ] **Step 2: Group the stream startup labels into one glass card**

In `StreamFrameViewController.m`, add `#import "Utils.h"`, add an ivar `UIVisualEffectView* _startupCard;` to the implementation's variable block, and replace the three separate `[self.view addSubview:…]` calls at lines ~209–211 with a card. The label and spinner creation earlier in `viewDidLoad` stays, minus its manual centring:

Delete these three lines from the `_stageLabel` / `_spinner` setup:

```objc
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
```

and, from the `_tipLabel` setup:

```objc
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
```

Replace:

```objc
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
```

with:

```objc
#if !TARGET_OS_TV
    _startupCard = [MoonlightTheme glassViewWithTint:nil];
    _startupCard.layer.cornerRadius = [MoonlightTheme cardCornerRadius];
    _startupCard.layer.cornerCurve = kCACornerCurveContinuous;
    _startupCard.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_startupCard];

    _stageLabel.numberOfLines = 0;
    _tipLabel.numberOfLines = 0;

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[_spinner, _stageLabel, _tipLabel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_startupCard.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [_startupCard.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_startupCard.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_startupCard.widthAnchor constraintLessThanOrEqualToAnchor:self.view.widthAnchor multiplier:0.8],
        [stack.topAnchor constraintEqualToAnchor:_startupCard.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:_startupCard.contentView.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:_startupCard.contentView.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:_startupCard.contentView.trailingAnchor constant:-24],
    ]];
#else
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
#endif
```

The two places that hide the startup UI must hide the card, not just the labels. At line ~375:

```objc
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
```

becomes:

```objc
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
#if !TARGET_OS_TV
        self->_startupCard.hidden = YES;
#endif
```

And at line ~478, the stage-change handler re-centres a label that is now stack-managed:

```objc
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
```

becomes:

```objc
        [self->_stageLabel setText:titleCase];
#if TARGET_OS_TV
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
#endif
```

- [ ] **Step 3: Turn the stats overlay into a glass pill**

Replace the `_overlayView == nil` construction block (lines ~265–287) on the iOS path. The overlay is a `UITextView` today purely so it can size itself to multi-line text; a `UILabel` in a glass container does the same with less machinery. Change the ivar declaration to `UILabel* _overlayLabel;` plus `UIVisualEffectView* _overlayView;`, and:

```objc
#if !TARGET_OS_TV
    if (_overlayView == nil) {
        _overlayView = [MoonlightTheme glassViewWithTint:nil];
        _overlayView.layer.cornerRadius = 14;
        _overlayView.layer.cornerCurve = kCACornerCurveContinuous;
        _overlayView.userInteractionEnabled = NO;
        _overlayView.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_overlayView];

        _overlayLabel = [[UILabel alloc] init];
        _overlayLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
        _overlayLabel.textColor = [UIColor labelColor];
        _overlayLabel.numberOfLines = 0;
        _overlayLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [_overlayView.contentView addSubview:_overlayLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_overlayView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
            [_overlayView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:12],
            [_overlayLabel.topAnchor constraintEqualToAnchor:_overlayView.contentView.topAnchor constant:8],
            [_overlayLabel.bottomAnchor constraintEqualToAnchor:_overlayView.contentView.bottomAnchor constant:-8],
            [_overlayLabel.leadingAnchor constraintEqualToAnchor:_overlayView.contentView.leadingAnchor constant:12],
            [_overlayLabel.trailingAnchor constraintEqualToAnchor:_overlayView.contentView.trailingAnchor constant:-12],
        ]];
    }
#endif
```

and replace the text-update block (lines ~294–304) on the iOS path with:

```objc
#if !TARGET_OS_TV
    if (text != nil) {
        _overlayLabel.text = text;
        _overlayView.hidden = NO;
    }
    else {
        _overlayView.hidden = YES;
    }
#endif
```

Keep the tvOS branches of both blocks exactly as they are.

- [ ] **Step 4: Commit**

```bash
git add Limelight/ViewControllers/LoadingFrameViewController.m \
        Limelight/ViewControllers/StreamFrameViewController.m
git commit -m "$(cat <<'EOF'
Give the loading frame and stream overlays a glass treatment

The loading spinner moves into a glass card over a light scrim instead of
sitting bare on a 50% black wash. The three separately-centred startup
views become one Auto Layout card, so a long app name no longer overlaps
the spinner. The stats overlay becomes a glass pill with monospaced
digits pinned to the safe area, replacing a manually-sized UITextView.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Nru3Ki3f9zUFkaE5f2G1Dh
EOF
)"
```

- [ ] **Step 5: Run the Verification Protocol**

Task-specific check:

```bash
strings Payload/Moonlight.app/Moonlight | grep -E "^(glassViewWithTint:|cardCornerRadius)$"
```

**On-device check after sideload:** tapping a host shows a small glass card with a spinner, not a black wash. Starting a stream shows one card containing spinner, stage text, and the swipe tip, which disappears cleanly when video starts. With Statistics Overlay on, a glass pill sits under the notch showing stats in monospaced digits.

---

## Post-implementation

- [ ] **Merge:** use `superpowers:finishing-a-development-branch` once all ten tasks are green and Kamil has confirmed the on-device checks.
- [ ] **Memory:** the `ci-unsigned-ipa-build` memory records the deployment target as 12.0 building fine under Xcode 26. After Task 1 that is stale — update it to note the 26.0 floor and anything legacy that broke under it.

## Deviations from the spec

Recorded so review does not treat them as mistakes:

1. **`layer.cornerRadius` + `cornerCurve` instead of `UICornerConfiguration`.** Shrinks the set of unverifiable iOS 26 API names from six to three. Visually near-identical; the loss is concentric corner nesting.
2. **Inset-grouped `UITableView` instead of a compositional list layout for Settings.** Same appearance on iOS 26, materially less code, no diffable data source to get wrong blind.
3. **Section headers are plain views, not `UIListContentConfiguration` headers.** The Games header needs a trailing menu button, which a plain header supplies more directly.
