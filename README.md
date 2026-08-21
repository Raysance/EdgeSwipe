# EdgeSwipe

EdgeSwipe is a lightweight macOS menu-bar app that turns trackpad edge and corner swipes into shortcuts.

It is built for people who want Notification Center-style gestures, but with their own actions: open Control Center, lock the screen, launch a URL or file, run a shell command, switch to a specific app, or simply show a quick HUD confirmation.

## What You Can Do

EdgeSwipe recognizes eight configurable gestures:

- Two-finger swipes from the left, top, bottom, or right edge of the trackpad.
- One-finger diagonal swipes from the top-left, top-right, bottom-left, or bottom-right corner.

Each gesture can be assigned one action:

- Disabled
- Show HUD
- Control Center
- Lock Screen
- Screenshot
- Hide Front Window
- Restore Hidden Window
- Switch App
- Switch Window
- Run Shell
- Open URL/File

The app lives in the macOS menu bar. From the menu, you can open settings, pause or resume gesture monitoring, and quit the app.

## Typical Uses

- Swipe from the right edge to open Control Center.
- Swipe from the bottom edge to take a screenshot.
- Swipe from a corner to lock the screen.
- Swipe from the left edge to switch back to a frequently used app.
- Assign a corner gesture to a shell command, automation script, URL, or local file.

## Settings

Open **EdgeSwipe → Open Settings...** from the menu-bar icon.

The settings window lets you:

- Choose an action for every edge and corner gesture.
- Preview the selected gesture and assigned action.
- Test an action without performing the gesture.
- Pick a currently windowed app from the Switch App submenu.
- Pick a specific visible window from the Switch Window submenu.
- Enable **Launch at Login** for the packaged `.app` build.

Actions that need extra input use the text field beside the action picker:

- **Open URL/File** accepts a URL such as `https://apple.com` or a path such as `~/Documents`.
- **Run Shell** accepts a shell command executed through `/bin/zsh -lc`.
- **Switch App** stores an app bundle identifier, or can match a running app by name.
- **Switch Window** stores a selected visible window and tries to focus that exact window later.

## Recognition Tuning

Click the parameters button in the settings window to tune gesture recognition.

EdgeSwipe uses normalized trackpad coordinates, so the sliders are proportions of the trackpad rather than pixel distances.

Two-finger edge swipes and one-finger corner swipes are tuned separately:

- **Edge band**: how close both fingers must start to an edge.
- **Inward travel**: how far the two-finger average must move toward the center before triggering.
- **Drift limit**: how much sideways movement is allowed while swiping from an edge.
- **Edge cooldown**: minimum time before the same edge gesture can trigger again.
- **Corner band**: size of the corner square where a one-finger corner swipe must begin.
- **Diagonal travel**: how far the finger must move inward on both axes before triggering.
- **Diagonal drift**: how much imbalance is allowed between horizontal and vertical diagonal movement.
- **Corner cooldown**: minimum time before the same corner gesture can trigger again.

The recognition window also includes a **Live Probe** area. Use it to try gestures while the window is active and verify that your thresholds feel right.

## Permissions

Most actions work without extra setup, but some system-level actions depend on macOS Accessibility access:

- **Control Center** clicks the Control Center menu-bar item through AppleScript/System Events.
- **Hide Front Window** and **Restore Hidden Window** use Accessibility to hide and restore the frontmost app window on the active display.
- **Switch Window** uses Accessibility to focus the selected window.
- **Switch Window** thumbnails use Screen Recording permission.
- **Switch App** can activate apps without Accessibility, but restoring minimized windows needs Accessibility permission.

If a permission is missing, EdgeSwipe shows an `Accessibility Needed` HUD.

## Build and Run

EdgeSwipe requires macOS 13 or newer and Swift Package Manager.

Run directly from source:

```sh
swift run EdgeSwipe
```

Build a packaged menu-bar app:

```sh
./scripts/build-app.sh
```

The app bundle is written to:

```text
outputs/EdgeSwipe.app
```

`Launch at Login` uses `SMAppService.mainApp`, so it is intended for the packaged `.app` bundle instead of a `swift run` process.

## Check the Core Recognizer

The repository also includes a small command-line target for checking the recognizer logic:

```sh
swift run EdgeSwipeCheck
```

## How It Works

Apple does not provide a public API for registering global, system-level trackpad edge gestures, so EdgeSwipe implements its own recognizer from normalized trackpad touch samples.

The recognizer keeps the rules intentionally simple:

- Edge gestures require exactly two active touches.
- Corner gestures require exactly one active touch.
- Touches must start inside the configured edge band or corner square.
- Movement must travel far enough toward the trackpad center.
- Excess sideways or diagonal drift is rejected.
- Each trigger has a cooldown to avoid repeated firing.

`EdgeSwipeCore` contains the pure recognition logic. The menu-bar app feeds it touch samples, then runs the action assigned to the resulting gesture.

## Monitoring Strategy

For background recognition, EdgeSwipe first tries macOS's private `MultitouchSupport` framework and falls back to AppKit `NSEvent`/`NSTouch` gesture monitoring when unavailable.

Because the primary background path uses a private framework, EdgeSwipe is not App Store safe and may need adjustment on future macOS releases. It is best treated as a personal utility or prototype.

## Project Layout

- `Sources/EdgeSwipeCore/`: pure recognizer types and gesture classification logic.
- `Sources/EdgeSwipe/`: menu-bar app, settings UI, event monitors, launch-at-login support, and action execution.
- `Sources/EdgeSwipeCheck/`: command-line recognizer check target.
- `scripts/build-app.sh`: release build script that creates `outputs/EdgeSwipe.app`.
