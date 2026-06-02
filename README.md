# RunOrRaise

RunOrRaise is a local-only native macOS menu bar launcher written in Swift. It indexes installed applications, running applications, and visible windows so you can quickly open an app, raise an app that is already running, or focus a specific window.

This project is inspired by [CZ-NIC/run-or-raise](https://github.com/CZ-NIC/run-or-raise), adapted for macOS as a native Swift app.

## Features

- Native macOS menu bar app and floating command palette.
- Global hotkey: `Command-Shift-Space`.
- Fuzzy search over installed apps, running apps, window titles, bundle identifiers, executable names, and app paths.
- Combined-field search, so queries like `Code Jiday` can match a `Code` window whose title contains `Jiday`.
- Usage-weighted ranking, so frequently selected results move higher when text relevance is similar.
- Exact window focusing through macOS Accessibility APIs.
- Local-only persistence through `UserDefaults` for usage history and installed-app cache.

## Requirements

- macOS 14 or newer
- Xcode command line tools with Swift 6

## Build, Test, and Run

```bash
swift test
scripts/build-app.sh
open .build/RunOrRaise.app
```

`scripts/build-app.sh` builds `.build/RunOrRaise.app` and signs it. By default it uses the first available `Apple Development` code-signing identity, falling back to ad-hoc signing if no identity is available. You can override this with:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/build-app.sh
```

Stable signing matters for Accessibility permission. If macOS still reports RunOrRaise as untrusted after a rebuild, remove the old entry from Accessibility settings and add the current `.build/RunOrRaise.app` again.

## Permissions

RunOrRaise can launch installed apps and activate running apps without special permission. Focusing a specific window requires Accessibility permission.

Grant it at:

```text
System Settings > Privacy & Security > Accessibility
```

The status menu shows whether Accessibility is granted and includes an action to open the relevant settings pane.

## Usage

Open the palette with `Command-Shift-Space`, then type to filter.

- `Code` can find the running Code app and Code windows.
- `Jiday` can find a window whose title contains `Jiday`.
- `Code Jiday` can narrow to a `Code` window whose title contains `Jiday`.

Keyboard controls:

- `Up` / `Down`: move the selected result.
- `Return`: run the selected result.
- `Escape`: close the palette.

Selection behavior:

- Installed app: opens the app, or activates it if already running.
- Running app: activates that app.
- Running window: focuses the selected window when Accessibility permission is granted.

## Architecture

- `AppCoordinator` wires services and controllers.
- `CarbonGlobalHotKeyService` owns global hotkey registration.
- `StatusItemController` owns the menu bar item and menu.
- `CommandPaletteWindowController` owns the floating AppKit panel and keyboard handling.
- `CommandPaletteView` and `CommandPaletteViewModel` keep SwiftUI rendering separate from launcher behavior.
- `FuzzyCommandMatcher` ranks and highlights command results.
- `NSWorkspaceLauncher` executes app launch, app activation, and window focus behavior.

## Development

Run the full test suite before rebuilding the app:

```bash
swift test
scripts/build-app.sh
```

Tests cover command providers, fuzzy search, usage ranking, palette view-model behavior, keyboard handling, activation decisions, installed-app caching, and usage persistence.

## Current Limitations

- Window focusing depends on macOS Accessibility data and can fail if a target window closes or the app stops exposing the window through Accessibility.
- The installed-app cache is a fallback, not a background indexer.
- There is no preferences UI beyond the status menu.
- The global hotkey is currently fixed at `Command-Shift-Space`.
