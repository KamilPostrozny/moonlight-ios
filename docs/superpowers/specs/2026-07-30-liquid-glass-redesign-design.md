# Liquid Glass Redesign — Design

Date: 2026-07-30
Status: Approved, ready for planning

## Goal

Replace Moonlight iOS's 2014-era UI with a modern, consistent, Liquid Glass
design built against the iOS 26 SDK. Improve ease of use, not just looks: the
current app hides most of its functionality behind long presses and an
unlabeled grid.

## Scope

In scope:

- Host picker and app grid (`MainFrameViewController`, `UIComputerView`, `UIAppView`)
- Settings (`SettingsViewController`)
- Loading frame and in-stream overlays (`LoadingFrameViewController`,
  `StreamFrameViewController`)

Out of scope:

- On-screen touch controls (`OnScreenControls.m`) — large, self-contained,
  unrelated to Liquid Glass
- Gamepad-driven focus navigation — iOS does not drive the focus engine from a
  controller D-pad, so it would be a hand-written focus driver; deliberately
  deferred
- The tvOS target — see "tvOS" below
- Streaming, pairing, discovery, and networking behavior — unchanged

## Constraints

These shape every decision below and are not negotiable within this project.

1. **No local build.** Development happens on Linux with no Xcode. GitHub
   Actions (`.github/workflows/build-ipa.yml`, iOS `Moonlight` scheme only) is
   the only compile gate. Nothing is verified until CI is green and the
   artifact is inspected.
2. **Avoid `project.pbxproj` edits.** Adding source files requires pbxproj
   surgery, the most likely way to break an unverifiable build. The design
   therefore adds **no new source files**; all new code goes into files already
   in the target. The single exception is one build-setting value (deployment
   target), applied and CI-verified on its own.
3. **Objective-C only.** The project contains no Swift and no Swift build
   phase. Adding one would require pbxproj changes.
4. **Liquid Glass API names are recalled, not compiled.** Every
   `UIGlassEffect`, `UICornerConfiguration`, and glass `UIButtonConfiguration`
   name in this design is written from knowledge of the iOS 26 SDK without a
   compiler to confirm it. Mitigation is structural: they are funnelled through
   a handful of helpers so a wrong name is a single-site fix, and work ships in
   phases so each CI run bisects a small surface.

## Decisions

| Decision | Choice |
|---|---|
| Minimum iOS | **26.0** — no availability guards, full glass everywhere |
| Navigation shell | **Native** — `SWRevealViewController` drawer removed from the view hierarchy |
| Visual identity | **Dark-first, purple accent, box-art ambient tint** |
| Main screen | **Single screen** — PCs section always visible, games below |
| Gamepad navigation | **Skipped** |
| tvOS target | **Ignored** — `#if TARGET_OS_TV` branches left byte-for-byte intact |

## Architecture

### File map

No new source files. Every change lands in a file already in the iOS target.

| File | Role after the redesign |
|---|---|
| `Limelight/Utility/Utils.h/.m` | `MoonlightTheme` — design tokens, glass helpers, ambient color |
| `Limelight/ViewControllers/MainFrameViewController.h/.m` | Single main screen, compositional layout, 3 sections |
| `Limelight/UIComputerView.h/.m` | Host card content view |
| `Limelight/UIAppView.h/.m` | Game tile content view |
| `Limelight/ViewControllers/SettingsViewController.h/.m` | Code-built inset-grouped list, presented as a sheet |
| `Limelight/ViewControllers/LoadingFrameViewController.h/.m` | Glass loading card |
| `Limelight/ViewControllers/StreamFrameViewController.m` | Startup card and stats overlay |
| `iPhone.storyboard`, `iPad.storyboard` | Reveal scenes removed; nav controller is the initial VC |
| `Moonlight.xcodeproj/project.pbxproj` | `IPHONEOS_DEPLOYMENT_TARGET` only |

`SWRevealViewController.h/.m` and `ComputerScrollView.h/.m` remain on disk and
in the target, unreferenced — the reveal drawer and the hand-positioned host
scroll view both disappear, but removing their files from the build would
require pbxproj surgery for no runtime benefit.
`MainFrameViewController.h` drops its `#import` and its
`SWRevealViewControllerDelegate` conformance; `StreamFrameViewController.m`
drops its `revealViewController` call.

### Design tokens — `MoonlightTheme`

Declared in `Utils.h`, implemented in `Utils.m`. Deliberately small; it exists
because of constraint 4, not for reuse elegance. Approximately:

```objc
@interface MoonlightTheme : NSObject
+ (UIColor*) accentColor;                                   // refined #AB9DFF
+ (CGFloat)  cornerRadiusForTile;                           // one radius scale
+ (UIVisualEffectView*) glassViewWithTint:(UIColor*)tint;   // UIGlassEffect
+ (UIButtonConfiguration*) glassButtonWithTitle:(NSString*)title
                                          image:(UIImage*)image
                                      prominent:(BOOL)prominent;
+ (UIColor*) ambientColorForImage:(UIImage*)image;          // avg colour, saturated
@end
```

Every `UIGlassEffect` / glass `UIButtonConfiguration` / `UICornerConfiguration`
call in the app goes through these. If a name is wrong, CI fails once and the
fix is in one file.

### Main screen

`MainFrameViewController` stays a `UICollectionViewController` and keeps all of
its existing discovery, pairing, app-list, deep-link, and shortcut logic
unchanged. Only presentation is replaced: `UICollectionViewFlowLayout` and the
hand-positioned `hostScrollView` give way to a
`UICollectionViewCompositionalLayout` with a section enum.

**Section: PCs.** Always visible, including while a host is selected. A
horizontal orthogonally-scrolling group of host cards. Each card is a glass
rounded rect containing an SF Symbol keyed to state
(`desktopcomputer`, `lock.desktopcomputer`,
`desktopcomputer.trianglebadge.exclamationmark`), the host name, and a status
line: `Paired`, `Not paired`, `Offline`, `Connecting…`, or
`Playing <game name>`. The selected host is accent-tinted. The final card is
`Add PC` with a `plus` symbol, replacing today's
`initForAddWithCallback:` icon. The section header carries a refresh button.

This removes the `Select New Host` up-button and the whole
`showHostSelectionView` / `addSubview:hostScrollView` swap: hosts never leave
the screen, so there is nothing to navigate back to. `showHostSelectionView`
survives as a state reset (it is the choke point that clears
`_deepLinkAppQuery`) but no longer manipulates view hierarchy.

**Section: Continue.** Present only when `host.currentGame` is non-zero. A
single full-width hero cell: box art, ambient tint, game name, a prominent
glass `Resume` button and a glass `Quit` button. Today resuming or quitting a
running game is reachable only by long-pressing its tile and reading an action
sheet.

**Section: Games.** Poster grid with column count driven by fractional
`NSCollectionLayoutDimension` so it adapts across iPhone, iPad, and split view
without the current manual scale transform in
`collectionView:cellForItemAtIndexPath:`. Each tile: box art with a concentric
`cornerConfiguration`, **a name label beneath every tile**, an HDR badge where
`app.hdrSupported`, and reduced opacity plus a `Hidden` badge for hidden apps.

The name label is a UX fix, not decoration: today `UIAppView` renders the app
name *only when box art is missing*, so a grid of arted games is a grid of
unlabeled pictures.

The section header carries an `ellipsis` menu with **Show Hidden Apps**,
**Wake PC**, **Test Network**, and **Remove PC** — all of which are currently
reachable only by long-pressing a host or app, and are therefore
undiscoverable.

**Chrome.** Nav title is the selected host name, or `Moonlight` when none is
selected. Right bar button is a `gearshape` opening Settings. A
`UISearchController` in the navigation item filters the Games section. A
`UIRefreshControl` re-runs discovery and the app-list fetch.

**Empty states.** No PCs found: a centered glass card, spinner, "Looking for
PCs on your network…", and an `Add PC Manually` button. PCs found but none
selected: "Choose a PC above." Both replace today's approach of putting
`Searching for PCs on your network...` in the navigation bar title.

**Context menus.** The existing `UIContextMenuInteraction` in `UIAppView` and
`UIComputerView` is retained and its callbacks are unchanged; only the menus'
presentation benefits from the new tiles.

### Ambient colour

`MoonlightTheme.ambientColorForImage:` downsamples a box art image to 1×1 via
`CGBitmapContext` (the same CoreGraphics idiom already used by
`+loadBoxArtForCaching:`), then boosts saturation so washed-out art still
produces a usable tint.

The colour is computed on the existing background pass in
`updateBoxArtCacheForApp:` and stored in a second `NSCache` keyed by
`TemporaryApp`, alongside `_boxArtCache`. Both caches are already purged
together on memory warnings and in `viewDidDisappear:`.

A `CAGradientLayer` on a background view behind the collection view renders a
soft radial tint from the running game's colour, or the first game's colour
when nothing is running, cross-fading on change.

### Settings

Presented modally as a sheet from the gear button
(`UISheetPresentationController`, large detent, grabber visible) — not as a
drawer. `SettingsViewController` builds its own
`UICollectionViewCompositionalLayout` list with
`UICollectionLayoutListConfiguration` in the `.insetGrouped` appearance, which
is what earns the iOS 26 list styling.

Sections and rows:

- **Video** — Resolution (menu row: 360p / 720p / 1080p / 4K / Safe Area /
  Full / Custom…), Frame Rate (menu row), Bitrate (slider row with live
  value), HDR (switch), Codec (menu row)
- **Audio** — Play Audio on PC (switch)
- **Input** — Touch Mode (segmented row, only two options so it fits),
  On-Screen Controls (menu row, disabled in absolute touch mode),
  Multi-Controller (switch), Swap A/B and X/Y (switch), Citrix X1 Mouse
  (switch)
- **Advanced** — Frame Pacing (menu row), Statistics Overlay (switch)
- **About** — version string, Setup Guide link, Troubleshooting link

Seven- and four-option segmented controls become menu rows because the current
ones are laid out at a fixed 450pt width and overflow the screen on every
iPhone.

**All computation is preserved verbatim**: `bitrateTable`, `resolutionTable`,
`isCustomResolution`, `getSliderValueForBitrate:`, `updateBitrate`,
`promptCustomResolutionDialog`, `getChosenFrameRate`,
`getChosenCodecPreference`, `getChosenStreamWidth/Height`, and `saveSettings`.
Only the widgets those methods read from change: the `IBOutlet` properties are
deleted from `SettingsViewController.h` and replaced with plain instance
variables holding the selected values. `viewDidLayoutSubviews` and
`viewSafeAreaInsetsDidChange` — both of which exist purely to patch up the
fixed-frame layout — are deleted.

Every storyboard subview and outlet connection in both Settings scenes is
removed. Leaving an outlet connected to a deleted view is a load-time crash, so
the scenes are reduced to a bare view controller.

**Behavior change:** settings persist on every change (and on dismiss) instead
of only when the reveal drawer finishes closing. The old
`revealController:didMoveToPosition:` → `saveSettings` hook disappears with the
drawer, and callers such as `prepareToStreamApp:` read settings straight from
Core Data, so writing eagerly is strictly safer than the current timing
dependency. The `revealToggleAnimated:NO` calls in `appClicked:`,
`appLongClicked:`, and `launchPendingDeepLinkApp:` that existed to force that
save are removed.

### Loading frame and stream overlays

`LoadingFrameViewController`: the 50%-black backdrop and bare white spinner
become a centered glass card holding a spinner and an optional status line.
Presentation style and the `showLoadingFrame:` / `dismissLoadingFrame:`
interface are unchanged, so all existing callers keep working.

`StreamFrameViewController`: `_stageLabel`, `_tipLabel`, and `_spinner` are
grouped into one centered glass card over black instead of three
independently-centered subviews. The stats overlay `_overlayView` becomes a
glass pill pinned top-leading with monospaced-digit text rather than a raw
`UITextView`.

### Storyboards

Both `iPhone.storyboard` and `iPad.storyboard` change identically:

- Initial view controller becomes the existing `UINavigationController`
- The `SWRevealViewController` scene and its `sw_front` / `sw_rear` segues are
  deleted
- The Settings scene keeps its view controller and storyboard identity but
  loses every subview and outlet
- The `createStreamFrame` push segue and the `loadingFrame` storyboard
  identifier are preserved — both are referenced by name in code
- Navigation bar styling attributes are dropped so iOS 26 supplies glass; the
  `setBackgroundImage:` / `setShadowImage:` calls in
  `MainFrameViewController.viewDidAppear:` that flatten the bar are removed

### tvOS

Every `#if TARGET_OS_TV` branch is left exactly as it is, and new UI code goes
inside `#if !TARGET_OS_TV`. The tvOS deployment target stays at 12.0. Nothing
builds or runs that target today and this project does not change that.

## Phasing

Each phase is a commit, a CI run, and an artifact check before the next begins.

| Phase | Content | Why separate |
|---|---|---|
| 0 | `IPHONEOS_DEPLOYMENT_TARGET` 12.0 → 26.0, nothing else | A 26.0 floor can turn deprecated calls in `SWRevealViewController` and `OnScreenControls` into hard errors. Isolate that signal. |
| 1 | `MoonlightTheme` helpers, storyboard surgery, reveal removal, glass nav bar | Proves the glass API names compile and the app still launches before anything depends on it |
| 2 | Main screen: compositional layout, host cards, game tiles, hero, empty states, search, pull-to-refresh | The largest single change; nothing else should be in flight with it |
| 3 | Ambient colour background | Purely additive on top of phase 2 |
| 4 | Settings rewrite | Independent of phases 2–3; touches a disjoint file set |
| 5 | Loading frame and stream overlays | Smallest surface, last |

## Verification

There is no test target and no way to render a pixel locally, so "verified"
means:

1. CI green on the pushed branch. Feature branches do not build on push;
   dispatch with `gh workflow run build-ipa.yml --ref <branch>`, then
   `gh run list --branch <branch>` and `gh run watch <id> --exit-status`.
2. Artifact inspected, not assumed: download the `.ipa`, confirm
   `Payload/Moonlight.app/Moonlight` is `Mach-O arm64`, confirm
   `strings Payload/Moonlight.app/Info.plist | grep -oE "iphoneos[0-9.]+"`
   reports `iphoneos26.x`, and `strings` the binary for selectors added in that
   phase to confirm the new code actually linked.
3. Kamil sideloads and reports what looks or behaves wrong. Phases are sized so
   a visual regression is attributable to one of them.

## Risks

| Risk | Mitigation |
|---|---|
| A Liquid Glass API name is wrong | Funnelled through `MoonlightTheme`; one CI failure, one-site fix |
| The 26.0 floor breaks unrelated legacy code | Phase 0 ships the bump alone |
| Storyboard XML edited by hand without Interface Builder | Small, surgical deletions; the initial-VC change and outlet removal are the only structural edits, and a wrong one fails at launch, not silently |
| A visual result is only judgeable on-device | Small phases, one sideload per phase |
| The `#if TARGET_OS_TV` branches drift out of compilability | Accepted: nothing builds them today |
