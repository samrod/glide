# Glide for OS X 10.6+

Glide is a small background utility that adds a decaying scroll tail after a
two-finger scroll. It targets older trackpads that report scrolling but stop
when the fingers lift.

Glide has no menu-bar item. Its Dock icon is optional and can be toggled in
Preferences. Closing the Preferences window leaves Glide running; use **Quit
Glide** inside Preferences to stop it.

## Source layout

- `src/Glide.m` contains app startup, trackpad monitoring, scroll-event
  handling, and inertial coasting.
- `src/GlidePreferencesController.m` owns the Preferences window, controls,
  and slider interactions. It communicates with the app controller through a
  small delegate interface.
- `src/GlideSettings.m` holds slider names, ranges, defaults, and units shared
  by the scrolling and preferences code.
- `src/GlideLoginItems.m` adds/removes Glide from the user's visible macOS
  Login Items list and migrates the old LaunchAgent preference.
- `resources/glide-icon-source.tif` is the editable Photoshop master. Export
  the updated artwork to `resources/glide-icon.png`; `build.sh` converts that
  PNG into the app's `.icns` icon.
- `build.sh` compiles these source files and packages/deploys the app.

## Build

Run `./build.sh` on a Mac with the Xcode Command Line Tools and Python 3
installed. The script rebuilds the app icon from `resources/glide-icon.png`,
then builds an Intel `x86_64` app with a 10.6 deployment target. This supports
64-bit Intel Macs running Snow Leopard, Lion, or Mountain Lion; it does not
support 32-bit-only Intel Macs.

## Install

In Mac OS X 10.6 - 10.8, put `Glide.app` in `/Applications` or `/Applications/Utilities`.
On first launch, Control-click the app and choose Open if Gatekeeper blocks the unsigned 
build. In Preferences, enable **Launch Glide at login** to add Glide to the user's Login 
Items list. If you hide its Dock icon, Glide starts hidden at the next login.

If Glide reports that scroll access is unavailable, enable **access for
assistive devices** in System Preferences > Universal Access, then quit and
reopen Glide. The app only listens for scroll-wheel events and posts additional
pixel-based scroll events after a short pause. It leaves the original scroll
events untouched. Faster flicks receive a stronger launch speed. When Blanca's
built-in trackpad input monitor is available, touching the pad during a coast
stops the generated motion immediately; otherwise the next scroll movement
stops it.

## Limits

Glide is a normal user-space app, not a kernel driver or injected dynamic
library. Coasting uses gradual exponential deceleration: the launch speed
continues to reflect the flick, and faster flicks shed speed more strongly
over time. Glide ignores trackpad release reports briefly at coast start so
lifting the fingers does not cancel the coast. The Preferences
window is built into the app for this prototype; a System Preferences pane can
be added after the scrolling behavior is fully validated.
