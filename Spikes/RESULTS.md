# Phase 0 spike results (macOS 27.0.1, Swift 6.4, 2026-10-25)

| # | Spike | Result |
|---|---|---|
| 1 | Liquid Glass (`NSGlassEffectView` inside `NSGlassEffectContainerView`) in a borderless `.nonactivatingPanel` at backstop/status level | PASS — renders real glass over the wallpaper in the hidden-menu-bar strip. Long-run backdrop refresh behind moving windows not yet observed (AeroSpace tiled the test window away); keep the surface abstraction so `NSVisualEffectView` can replace it if staleness shows up. |
| 2 | SwiftUI `.onHover` / `.onTapGesture` inside `NSHostingView` in the panel | PASS — log shows hover + click events while Ghostty stayed frontmost, `NSApp.isActive == false`. No AppKit hit-testing fallback needed. |
| 3 | Sticky across Spaces / fullscreen (`.canJoinAllSpaces, .stationary, .fullScreenAuxiliary`) | Not exercised yet: the user runs AeroSpace workspaces (no macOS Spaces). Re-check when a native fullscreen app is used. |
| 4 | AeroSpace socket (`/tmp/bobko.aerospace-$USER.sock`, protocol v1) | PASS — `list-workspaces --json` in 4 ms; `subscribe focused-workspace-changed focus-changed window-detected` streams events immediately (note: `--all` conflicts with named events). |
| 5 | mediaremote-adapter built with plain clang (no cmake), self-test | PASS — `test` exits 0 on 27.0.1 from `/usr/bin/perl`; `get` prints `null` when idle. Test client needs `-framework MediaPlayer`. |

Menu bar: the user has `_HIHideMenuBar = 1` (auto-hide Always). When auto-hidden, `visibleFrame` still excludes the 37.5 pt notch strip, so the bar must be placed from `frame.maxY`, not `visibleFrame.maxY`.
