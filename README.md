# Barrly

A native macOS bar, inspired by SketchyBar and Übersicht, built on Liquid Glass.

Every widget is built in. There is no config file and no scripting: you choose widgets,
order them, group them into glass capsules and tune their data in **Barrly Settings**.
One process, native data sources, no shell forks on hover, workspace switch or app switch.

Requires macOS 26 or later (Liquid Glass). Developed on macOS 27 with Swift 6.4 and the
Command Line Tools only; no Xcode needed.

## Widgets

Apple menu · AeroSpace workspaces (real app icons) · Front app · Now playing · CPU · Memory ·
Wi‑Fi (IP) · VPN (auto-hides; SCNetworkConnection + tunnel interfaces) · Volume (CoreAudio; click mutes, scroll adjusts) · Battery · Jalali date · Clock · Input source · Meeting (EventKit) · Keep awake (an owl: click keeps the Mac and display awake, like caffeinate; the input lock switches it on while locked) · Input lock (global shortcut or click blocks all keyboards and mice until the unlock chord, default ⌃⌥⌘L for both; keeps the Mac awake while locked; the first use shows an explanation and asks for approval) · Spacer

## Install

```sh
brew install arastu/tap/barrly   # prebuilt bottle on Apple Silicon (source build elsewhere)
barrly                           # launch;  barrly zen | refresh | settings | lock | awake | sign | quit
```

The app lives at `/opt/homebrew/opt/barrly/Barrly.app`. Start it at login with
`brew services start barrly`, or from AeroSpace (see below).

macOS privacy grants (Accessibility for the input lock, Calendars) are tied to the app's code
identity, and a Homebrew build is only ad-hoc signed. So the first `barrly` run creates a local
"Barrly Code Signing" identity in its own keychain and signs the app with it; macOS may ask for
your password once. Every later launch (`barrly`, `brew services`) re-signs after an upgrade, so
the grants survive. `barrly sign` does the same by hand.

Without Homebrew: download `Barrly-<version>.zip` from the
[releases page](https://github.com/arastu/barrly/releases), unzip, and clear the quarantine flag
before the first launch, since the app is not notarized:

```sh
xattr -dr com.apple.quarantine ~/Downloads/Barrly.app && open ~/Downloads/Barrly.app
```

Requires macOS 26 (Liquid Glass) or newer.

From a checkout:

```sh
scripts/install.sh            # release build → ~/.local/share/barrly/Barrly.app, launches it
scripts/dev.sh                # debug build + relaunch while developing
swift test                    # unit tests
```

The menu bar should be set to auto-hide (System Settings › Desktop & Dock) and your window
manager should reserve the strip, e.g. AeroSpace `gaps.outer.top`.

## Control from anywhere

```
open barrly://mode/zen        # toggle zen (hide the noisy widgets)
open barrly://mode/zen/on     # or /off
open barrly://refresh         # refresh every widget
open barrly://settings        # open the Settings window (also: right‑click the Apple logo)
open barrly://lock            # block all keyboards and mice until the unlock chord (also: lock/on, lock/off)
open barrly://awake           # toggle keep-awake (also: awake/on, awake/off)
```

Launch at login: `brew services start barrly`, Settings › Advanced, or from AeroSpace:
`after-startup-command = ['exec-and-forget /opt/homebrew/bin/barrly']`.

## How it is built

- `Shell/` AppKit: one borderless, non-activating `NSPanel` per display, an `NSGlassEffectContainerView`
  holding one `NSGlassEffectView` capsule per surface. Clicks never steal focus from the front app.
- `UI/`, `Widgets/` SwiftUI content inside the capsules; hover lozenges are plain fills (never glass on glass).
  `@ViewState` stands in for `@State`, whose macro plugin ships only with Xcode.
- `Providers/` native data: IOKit power sources, Mach host statistics, SCDynamicStore, Text Input Sources,
  NSWorkspace, EventKit, the AeroSpace Unix socket (`subscribe` stream), and the bundled
  [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) for now‑playing.
- `Model/` settings (Codable, UserDefaults), modes, appearance. `SettingsUI/` the Settings window.
- `Providers/Scheduler.swift` one timer for every polling job, minute-aligned, paused during sleep.

Light/dark, Reduce Transparency, Increase Contrast and Reduce Motion are followed live.

## App icon

`Resources/Icon/source.png` is the artwork; `scripts/make-icon.swift` crops it to the macOS icon
grid and writes `Resources/AppIcon.icns`:

```sh
swiftc -O scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon Resources/Icon/source.png Resources/Icon \
  && iconutil -c icns Resources/Icon/AppIcon.iconset -o Resources/AppIcon.icns
```

## Releasing

```sh
scripts/release.sh 0.2.0   # tests, version bump, tag, push, GitHub release, tap formula, brew upgrade
```

## Phase 0 spikes

See `Spikes/RESULTS.md` for what was verified on macOS 27 before building.
