# RunOrRaise

RunOrRaise is a local-only native macOS menu bar launcher written in Swift. It indexes installed applications, running applications, and visible windows so you can quickly open an app, raise an app that is already running, or focus a specific window.

## Requirements

- macOS 14 or newer
- Xcode command line tools with Swift 6

## Permissions

RunOrRaise works without special permission for installed-app launch and running-app activation. Exact window focusing requires macOS Accessibility permission because focusing a specific window uses the Accessibility API.

The menu bar item shows the current Accessibility state:

- `Accessibility: Granted` means exact window focusing is enabled.
- `Accessibility: Missing - window focus disabled` means RunOrRaise can still open or activate apps, but selecting a window falls back gracefully and shows a permission message.

Choose `Open Accessibility Settings` from the menu bar item to request permission and open the relevant macOS System Settings pane. You can also open it manually at `System Settings > Privacy & Security > Accessibility`, then enable RunOrRaise.

## Build and test

```bash
swift test
swift build
```

## Run as an app

```bash
chmod +x scripts/build-app.sh
scripts/build-app.sh
open .build/RunOrRaise.app
```

The app appears as a menu bar utility named `Run`.

## Hotkey behavior

Use `Command-Shift-Space` to open or hide the floating command palette, or choose `Open Palette` from the status menu. Type to filter results, use the arrow keys to move selection, press `Return` to run the selected item, and press `Escape` to close the palette.

Selection behavior:

- Installed app: launches the app, or activates it if it is already running.
- Running app: activates that application.
- Running window: focuses that exact window when Accessibility permission is granted.

Successful selections are recorded in local usage history and influence future result ranking.

## Persistence

RunOrRaise stores usage history in `UserDefaults` so frequently selected apps and windows rank higher across launches. It also persists the installed-application index in `UserDefaults` and can use that cache if a later app scan returns no installed apps. Running apps and windows are refreshed at palette open and are not persisted because those targets are session-specific.

## Manual verification

Unit tests cover activation decision logic, command ranking, usage persistence, installed-app cache persistence, command refresh behavior, and view-model failure handling. OS-level window focusing must be verified manually because macOS Accessibility and live window state are not reliable unit-test targets:

1. Build and open `.build/RunOrRaise.app`.
2. Open at least two windows in the same app.
3. Grant Accessibility permission to RunOrRaise.
4. Open the palette with `Command-Shift-Space`.
5. Select each window result and confirm the exact selected window becomes focused.
6. Remove Accessibility permission and confirm selecting a window shows a permission message without crashing.

## Architecture

- `AppCoordinator` wires services and AppKit controllers.
- `CarbonGlobalHotKeyService` owns global hotkey registration.
- `StatusItemController` owns the menu bar status item and menu.
- `CommandPaletteWindowController` owns the floating AppKit panel.
- `CommandPaletteView` and `CommandPaletteViewModel` keep SwiftUI rendering separate from launcher behavior.
- `NSWorkspaceLauncher` executes launch, activation, and Accessibility window focus decisions.
- `FuzzyCommandMatcher`, `InMemoryCommandIndex`, and protocol-based services are covered by unit tests where behavior is pure and deterministic.

## Current v1 limitations

- Window focusing requires Accessibility permission and may fail if the target window closes, moves to another process, or macOS does not expose a matching Accessibility window number.
- Running windows without a stable window identifier fall back to app activation.
- The installed-app cache is a fallback, not a background indexer.
- There is no preferences UI beyond the status menu.
- The global hotkey is fixed at `Command-Shift-Space`.
