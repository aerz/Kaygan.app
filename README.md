<div align="center">
  <img src="docs/images/kaygan-icon.png" alt="Kaygan app icon" width="128" height="128">
  <h1>Kaygan</h1>
  <p><strong>A smoother, more natural mouse experience.</strong></p>
  <p>macOS 15+ &nbsp;·&nbsp; <a href="LICENSE">Free and open source</a></p>
  <p><a href="#getting-started">Getting started</a> &nbsp;·&nbsp; <a href="#build-from-source">Build from source</a></p>
</div>

Hold a mouse button and move to scroll. Use the side buttons to go back and forward.

<p align="center">
  <img src="docs/images/02-scrolling.jpeg" alt="Kaygan Scrolling settings with mouse button detection, speed, reverse direction and click-to-toggle controls" width="800">
</p>

## What you can do

- **Scroll in any direction.** Hold your chosen button or click to toggle, then move your mouse.
- **Go back and forward.** Use your side buttons in apps that support navigation gestures.
- **Set your pace.** Adjust scrolling speed and direction.
- **Choose your apps.** Disable scrolling, navigation or both per app.

Changes in Settings apply immediately.

<p align="center">
  <a href="docs/images/03-navigation.jpeg"><img src="docs/images/03-navigation.jpeg" alt="Navigation settings with side-button navigation, reverse directions and a button test" width="390"></a>
  <a href="docs/images/01-general.jpeg"><img src="docs/images/01-general.jpeg" alt="General settings with Accessibility access, Launch at Login and disabled apps" width="390"></a>
</p>

## Getting started

Requires **macOS 15+** and a mouse with a middle or side button. [Build and run Kaygan](#build-from-source), then:

1. **Open Settings** from the menu bar icon.
2. **Grant Accessibility access:** click **General → Request Access**, then enable Kaygan in **System Settings → Privacy & Security → Accessibility**. **Enabled** confirms access to handle mouse gestures and send scroll and navigation events.
3. **Choose your button:** in **Scrolling**, click **Mouse button** and press your preferred middle or side button. The default is **Button 3** (usually the middle button). Hold it and move to scroll.

Check side buttons in **Navigation → Test buttons**. **Buttons 4 and 5** go back and forward; a button assigned to scrolling takes priority.

## Build from source

Use **Xcode 27** and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The app targets macOS 15 and later; the Xcode project is generated from [`project.yml`](project.yml).

```sh
brew install xcodegen
xcodegen generate
open Kaygan.xcodeproj
```

In Xcode, select the **Kaygan** scheme and **My Mac**, then run the app. Kaygan starts in the menu bar without opening a window.

For a signed build, use your existing signing identity. If your development team differs from the one in `project.yml`, update `DEVELOPMENT_TEAM` there and regenerate the project.

<details>
<summary>Command-line builds and tests</summary>

```sh
xcodebuild -project Kaygan.xcodeproj -scheme Kaygan build
xcodebuild -project Kaygan.xcodeproj -scheme Kaygan test
```

</details>

## License

Kaygan is free and open source under the [GNU General Public License, version 3 or later](LICENSE). You can use, study, change and share it under the terms of that license.
