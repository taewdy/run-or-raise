# RunOrRaise

RunOrRaise is a local-only native macOS menu bar launcher foundation written in Swift.

## Requirements

- macOS 14 or newer
- Xcode command line tools with Swift 6

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

The app appears as a menu bar utility named `Run`. Use `Command-Shift-Space` to open the floating command palette, or choose `Open Palette` from the status menu.

## Architecture

- `AppCoordinator` wires services and AppKit controllers.
- `CarbonGlobalHotKeyService` owns global hotkey registration.
- `StatusItemController` owns the menu bar status item and menu.
- `CommandPaletteWindowController` owns the floating AppKit panel.
- `CommandPaletteView` and `CommandPaletteViewModel` keep SwiftUI rendering separate from launcher behavior.
- `FuzzyCommandMatcher`, `InMemoryCommandIndex`, and protocol-based services are covered by unit tests where behavior is pure and deterministic.
