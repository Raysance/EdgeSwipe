# EdgeSwipe

EdgeSwipe is a small macOS menu-bar prototype for recognizing two-finger edge swipes on a trackpad.

It uses the closest publicly available model to Apple's Notification Center gesture:

- Track exactly two active `NSTouch` identities.
- Require both touches to begin inside a normalized edge band.
- Require enough inward movement from the start edge.
- Reject gestures with too much cross-axis drift.
- Apply a per-edge cooldown to avoid repeated triggers.

Apple does not publish an API for registering system-level trackpad edge gestures, so this app implements its own recognizer with AppKit touch data and event monitors.

For background recognition, the app first tries the private `MultitouchSupport` framework and falls back to AppKit gesture monitoring if that is unavailable. The private path is not App Store safe and may need adjustment on future macOS releases.

## Run

```sh
swift run EdgeSwipe
```

## Built-in Actions

Each edge can run one of these built-in actions:

- Show HUD
- Control Center
- Lock Screen
- Screenshot
- Switch App, with a submenu of currently windowed apps
- Run Shell
- Open URL/File

Control Center and restoring minimized Switch App windows may require granting Accessibility permission to EdgeSwipe. Switch App can be chosen from the action menu's app submenu; it stores the selected app bundle identifier in the payload field.

## Build App Bundle

```sh
./scripts/build-app.sh
```

The app bundle is written to `outputs/EdgeSwipe.app`.

## Check Core Recognizer

```sh
swift run EdgeSwipeCheck
```
