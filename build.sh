#!/bin/zsh
set -euo pipefail
PET_PROJECT="${0:A:h}"
PET_APP="${PET_OUTPUT:-$PET_PROJECT/.build/蓝色大肥鱼.app}"
PET_ARCH="${PET_ARCH:-$(uname -m)}"
[[ "$PET_ARCH" == arm64 || "$PET_ARCH" == x86_64 ]] || { print -u2 'Unsupported architecture'; exit 1; }
[[ "$PET_APP" == /* && "$PET_APP" == *.app ]] || { print -u2 'PET_OUTPUT must be an absolute .app path'; exit 1; }
if [[ -e "$PET_APP" ]]; then
  PET_EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PET_APP/Contents/Info.plist" 2>/dev/null || true)
  [[ "$PET_EXISTING_ID" == local.bluewhale.desktop.pet ]] || { print -u2 'Refusing to replace a different application'; exit 1; }
fi
mkdir -p "$PET_PROJECT/.build" "${PET_APP:h}"
PET_STAGE=$(mktemp -d "$PET_PROJECT/.build/staging.XXXXXX")
trap 'rm -rf -- "$PET_STAGE"' EXIT
PET_BUNDLE="$PET_STAGE/蓝色大肥鱼.app"
mkdir -p "$PET_BUNDLE/Contents/MacOS" "$PET_BUNDLE/Contents/Resources"
cp "$PET_PROJECT/Info.plist" "$PET_BUNDLE/Contents/Info.plist"
ditto "$PET_PROJECT/HighResolution" "$PET_BUNDLE/Contents/Resources/HighResolution"
cp "$PET_PROJECT/Assets/DeepSeekStatus.pdf" "$PET_BUNDLE/Contents/Resources/DeepSeekStatus.pdf"
cp "$PET_PROJECT/PetIcon.icns" "$PET_BUNDLE/Contents/Resources/PetIcon.icns"
xcrun swiftc -O -swift-version 5 -target "$PET_ARCH-apple-macos13.0" \
  -module-cache-path "$PET_PROJECT/.build/module-cache" \
  -framework AppKit -framework ImageIO \
  "$PET_PROJECT/Sources/PetModel.swift" "$PET_PROJECT/Sources/PetApp.swift" \
  "$PET_PROJECT/Tests/ModelTests.swift" "$PET_PROJECT/Sources/main.swift" \
  -o "$PET_BUNDLE/Contents/MacOS/BlueWhalePet"
codesign --force --sign - "$PET_BUNDLE"
codesign --verify --deep --strict "$PET_BUNDLE"
if [[ -e "$PET_APP" ]]; then rm -rf -- "$PET_APP"; fi
mv "$PET_BUNDLE" "$PET_APP"
print -r -- "$PET_APP"
