#!/bin/bash
set -euo pipefail

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[[ "${SIGNING_IDENTITY:-}" =~ ^[[:xdigit:]]{40}$ ]] \
    || fail "Set SIGNING_IDENTITY to the certificate's 40-character SHA-1 fingerprint."

for tool in xcodegen xcodebuild codesign hdiutil osascript ditto lipo; do
    command -v "$tool" >/dev/null || fail "Install $tool before running this script."
done

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dist_dir="$root_dir/build/dist"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/kaygan-package.XXXXXX")"
mount_point="$work_dir/mount"
mounted=false

cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$mounted" == true ]]; then
        if ! hdiutil detach "$mount_point" -quiet; then
            if ! hdiutil detach "$mount_point" -force -quiet; then
                printf 'Error: Unmount %s before removing %s.\n' "$mount_point" "$work_dir" >&2
                exit 1
            fi
        fi
    fi
    rm -rf "$work_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$root_dir"
xcodegen generate
xcodebuild -quiet -project Kaygan.xcodeproj -scheme Kaygan \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work_dir/DerivedData" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=15.0 \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build

app="$work_dir/DerivedData/Build/Products/Release/Kaygan.app"
plist="$app/Contents/Info.plist"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")"

[[ "$bundle_id" == com.aerz.Kaygan ]] || fail "The app has an unexpected bundle identifier: $bundle_id."
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ && -n "$build_number" ]] || fail "The app has an invalid version."
[[ "$minimum_macos" == 15.0 ]] || fail "The app must target macOS 15.0."
[[ "$(lipo -archs "$app/Contents/MacOS/Kaygan")" == arm64 ]] || fail "The app must contain only arm64 code."

signing_args=(--force --sign "$SIGNING_IDENTITY" --timestamp=none)
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then
    signing_args+=(--keychain "$SIGNING_KEYCHAIN")
fi
codesign "${signing_args[@]}" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

mkdir -p "$work_dir/staging" "$mount_point"
ditto "$app" "$work_dir/staging/Kaygan.app"
ln -s /Applications "$work_dir/staging/Applications"
hdiutil create -volname Kaygan -srcfolder "$work_dir/staging" \
    -format UDRW -fs HFS+ "$work_dir/writable.dmg"
hdiutil attach -readwrite -nobrowse -noautoopen \
    -mountpoint "$mount_point" "$work_dir/writable.dmg"
mounted=true

osascript - "$mount_point" <<'APPLESCRIPT'
on run arguments
    set volumeFolder to POSIX file (item 1 of arguments) as alias
    tell application "Finder"
        open volumeFolder
        set imageWindow to container window of volumeFolder
        set current view of imageWindow to icon view
        set toolbar visible of imageWindow to false
        set statusbar visible of imageWindow to false
        set bounds of imageWindow to {400, 200, 1000, 560}
        set viewOptions to icon view options of imageWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "Kaygan.app" of volumeFolder to {150, 150}
        set position of item "Applications" of volumeFolder to {450, 150}
        close imageWindow
        open volumeFolder
        delay 2
        close container window of volumeFolder
    end tell
end run
APPLESCRIPT

[[ -f "$mount_point/.DS_Store" ]] || fail "Finder did not save the disk image layout."
sync
hdiutil detach "$mount_point" -quiet
mounted=false

dmg_name="Kaygan-$version-arm64.dmg"
hdiutil convert "$work_dir/writable.dmg" -format UDZO \
    -imagekey zlib-level=9 -o "$work_dir/$dmg_name"
hdiutil verify "$work_dir/$dmg_name"
(
    cd "$work_dir"
    shasum -a 256 "$dmg_name" > SHA256SUMS
)

mkdir -p "$dist_dir"
mv "$work_dir/$dmg_name" "$dist_dir/$dmg_name"
mv "$work_dir/SHA256SUMS" "$dist_dir/SHA256SUMS"
printf 'Created %s\n' "$dist_dir/$dmg_name"
printf 'Created %s\n' "$dist_dir/SHA256SUMS"
