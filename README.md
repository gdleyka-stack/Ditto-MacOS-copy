<p align="center">
  <img src="icon_ditto.png" width="128" height="128" alt="Ditto Logo">
</p>

# Ditto

Ditto is a lightweight, minimalist clipboard manager for macOS built using Swift and SwiftUI. It runs as a status bar application and keeps track of your copied text and images.

## Features

- **Clipboard History**: Stores up to 50 copied text and image items.
- **Translucent UI**: Premium glassmorphic panel with native rounded corners.
- **Search**: Instant case-insensitive filtering for text history.
- **Favorites**: Star items to prevent them from being cleared or pruned.
- **Keyboard Navigation**: Use Up/Down arrows to navigate, Return to copy, and Escape to dismiss.
- **Interactive Cells**: Double-click any cell to copy it back to your clipboard.
- **Space & Fullscreen Support**: Accessible on top of fullscreen apps and multiple virtual desktops.
- **Persistence**: Automatically preserves your history across restarts.

## Requirements

- macOS 13.0 or later

## Building from Source

Build the release binary using Swift Package Manager:

```bash
swift build -c release
```

To create the application bundle:

1. Create the bundle directory structure:
```bash
mkdir -p Ditto.app/Contents/MacOS
mkdir -p Ditto.app/Contents/Resources
```

2. Copy the binary and assets:
```bash
cp .build/release/Ditto Ditto.app/Contents/MacOS/Ditto
cp icon_ditto.png Ditto.app/Contents/Resources/icon_ditto.png
```

3. Configure Info.plist under `Ditto.app/Contents/Info.plist`.
