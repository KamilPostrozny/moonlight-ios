# Moonlight iOS/tvOS

[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/kwv8vpwr457lqn25/branch/master?svg=true)](https://ci.appveyor.com/project/cgutman/moonlight-ios/branch/master)

[Moonlight for iOS/tvOS](https://moonlight-stream.org) is an open source client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream. Moonlight for iOS/tvOS allows you to stream your full collection of games and apps from your powerful desktop computer to your iOS device or Apple TV.

Moonlight also has a [PC client](https://github.com/moonlight-stream/moonlight-qt) and [Android client](https://github.com/moonlight-stream/moonlight-android).

Check out [the Moonlight wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for more detailed project information, setup guide, or troubleshooting steps.

[![Moonlight for iOS and tvOS](https://moonlight-stream.org/images/App_Store_Badge_135x40.svg)](https://apps.apple.com/us/app/moonlight-game-streaming/id1000551566)

## Deep links

This fork registers the `moonlight://` URL scheme on iOS/iPadOS, so a Shortcut,
an automation, or a Home Screen bookmark can launch straight into a stream:

```
moonlight://launch?host=Gaming-PC&app=Steam
```

* `host` — the PC, identified by its name, its UUID, or any of its addresses.
  Aliases: `ip`, `uuid`, `name`.
* `app` — the game or app, identified by its name or its numeric ID.
  Aliases: `appid`, `appname`. Optional: leave it out to just open the PC's app
  list.

Matching is case-insensitive, and values must be URL-encoded (a space becomes
`%20`). The PC has to have been paired in the app at least once, since the deep
link resolves against saved hosts.

To use it from the Shortcuts app, add an **Open URLs** action and paste the URL.
If a different game is already running on the host, the deep link stops at the
app list and tells you rather than quitting it.

## Building
* Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835)
* Run `git clone --recursive https://github.com/moonlight-stream/moonlight-ios.git`
  *  If you've already clone the repo without `--recursive`, run `git submodule update --init --recursive`
* Open Moonlight.xcodeproj in Xcode
* To run on a real device, you will need to locally modify the signing options:
    * Click on "Moonlight" at the top of the left sidebar
    * Click on the "Signing & Capabilities" tab
    * Under "Targets", select "Moonlight" (for iOS/iPadOS) or "Moonlight TV" (for tvOS)
    * In the "Team" dropdown, select your name. If your name doesn't appear, you may need to sign into Xcode with your Apple account.
    * Change the "Bundle Identifier" to something different. You can add your name or some random letters to make it unique.
    * Now you can select your Apple device in the top bar as a target and click the Play button to run.
