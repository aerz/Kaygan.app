# Kaygan

Kaygan is a macOS app that scrolls when you hold a mouse button and move the mouse. In toggle mode, click once to start scrolling and click again to stop.

## Requirements

Kaygan runs on macOS 15 or later. To build it, you need Xcode 16 or later and XcodeGen. XcodeGen creates the `Kaygan.xcodeproj` project from `project.yml`.

## Build

Install XcodeGen with Homebrew:

```sh
brew install xcodegen
```

Generate the project and build the app:

```sh
xcodegen generate
xcodebuild -project Kaygan.xcodeproj -scheme Kaygan build
```

To open the project in Xcode, run `open Kaygan.xcodeproj` after you generate it.

`project.yml` sets the signing team in `DEVELOPMENT_TEAM`. If your team is different, change that value and run `xcodegen generate` again.

## Run

1. In Xcode, select the `Kaygan` scheme and `My Mac`. Run the app.
2. Grant Accessibility permission to Kaygan in `System Settings > Privacy & Security > Accessibility`. Kaygan needs this permission to read the mouse and send scroll events. macOS keeps this permission for each app.
3. After Kaygan starts scrolling, look in the Xcode debug console for `Kaygan: scrolling enabled`.

If Kaygan cannot start or restore mouse input, it shows an alert to retry or quit.

Kaygan runs from the menu bar and opens no window at launch. Click the Kaygan menu bar icon to open Settings or quit. Kaygan has no Dock icon, including while Settings is open. Kaygan does not register itself to launch at login.

## Settings

Kaygan keeps its settings in `com.aerz.Kaygan`. You can also set them with the macOS `defaults` command. This example sets mouse button 3:

```sh
defaults write com.aerz.Kaygan button -int 3
defaults write com.aerz.Kaygan speed -int 3
defaults write com.aerz.Kaygan reverse -int 0
defaults write com.aerz.Kaygan toggle -int 0
```

Changes in the Settings window apply immediately. Changes with `defaults write` apply at the next launch.

Button numbers start at 1. Values 3 to 32 select extra buttons. The value 0 disables the app. If the default button does not work, use `Detect` in Settings. The next extra mouse button that you press becomes the new button.

Speed has five steps. `1` is the slowest, `5` is the fastest, and `3` is the default. Set `reverse` to `1` to scroll in the opposite direction. Set `toggle` to `1` to turn on toggle mode.

## License

Kaygan is licensed under the GNU General Public License, version 3 or later. The full license text is in [LICENSE](LICENSE). You can use, study, change, and share the code under the terms of that license.
