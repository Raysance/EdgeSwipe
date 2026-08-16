# EdgeSwipe

EdgeSwipe is a small macOS menu-bar prototype for recognizing trackpad edge and corner swipes.

It uses the closest publicly available model to Apple's Notification Center gesture:

- Track exactly two active `NSTouch` identities for edge swipes.
- Track exactly one active `NSTouch` identity for corner swipes.
- Require edge swipes to begin inside a normalized edge band.
- Require corner swipes to begin inside one of the four normalized corner squares.
- Require enough inward movement from the start edge or corner.
- Reject gestures with too much cross-axis drift.
- Apply a per-trigger cooldown to avoid repeated triggers.
- Keep separate recognition parameters for two-finger edge swipes and one-finger corner swipes.

Apple does not publish an API for registering system-level trackpad edge gestures, so this app implements its own recognizer with AppKit touch data and event monitors.

For background recognition, the app first tries the private `MultitouchSupport` framework and falls back to AppKit gesture monitoring if that is unavailable. The private path is not App Store safe and may need adjustment on future macOS releases.

## Run

```sh
swift run EdgeSwipe
```

The settings window includes a Launch at Login checkbox. It uses `SMAppService.mainApp`, so it is intended for the packaged `.app` bundle rather than a `swift run` process.

## Built-in Actions

Each edge or corner trigger can run one of these built-in actions:

- Show HUD
- Control Center
- Lock Screen
- Screenshot
- Switch App, with a submenu of currently windowed apps
- Run Shell
- Open URL/File

Control Center and restoring minimized Switch App windows may require granting Accessibility permission to EdgeSwipe. Switch App can be chosen from the action menu's app submenu; it stores the selected app bundle identifier in the payload field.

The configurable trigger list includes four two-finger edge swipes and four one-finger corner swipes:

- Left Edge
- Top Edge
- Bottom Edge
- Right Edge
- Top-Left Corner
- Top-Right Corner
- Bottom-Left Corner
- Bottom-Right Corner

## Recognition Sliders

The recognizer uses normalized trackpad coordinates, so these values are proportions of the trackpad rather than pixels.

Two-finger edge swipes and one-finger corner swipes have separate slider groups. Changing one group does not alter the other group.

- Edge band: for edge swipes, how close both fingers must start to an edge. Lower values require a tighter edge start; higher values accept a wider edge zone.
- Inward travel: for edge swipes, how far the two-finger average must move toward the center before triggering. Lower values trigger on shorter swipes; higher values require longer swipes.
- Drift limit: for edge swipes, how much movement is allowed across the wrong axis. Lower values require a straighter swipe; higher values tolerate looser drift.
- Edge cooldown: how soon the same edge trigger can fire again. Lower values allow more repeated triggers; higher values reduce accidental repeats.
- Corner band: for corner swipes, the width and height of the start square in each corner. Lower values require a tiny corner start; higher values accept a wider corner zone.
- Diagonal travel: for corner swipes, how far the finger must move inward on both axes before triggering. Lower values trigger on shorter diagonal swipes; higher values require longer diagonal swipes.
- Diagonal drift: for corner swipes, the allowed imbalance between horizontal and vertical inward movement. Lower values require a cleaner diagonal toward the center; higher values tolerate looser movement.
- Corner cooldown: how soon the same corner trigger can fire again. Lower values allow more repeated triggers; higher values reduce accidental repeats.

## Build App Bundle

```sh
./scripts/build-app.sh
```

The app bundle is written to `outputs/EdgeSwipe.app`.

## Check Core Recognizer

```sh
swift run EdgeSwipeCheck
```
