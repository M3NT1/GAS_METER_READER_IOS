#!/usr/bin/env bash
set -euo pipefail

# Vigavi / GasPhotoIOS IPA csomagoló script
# Használat: ./Scripts/package_ipa.sh

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA_DIR="$HOME/Library/Developer/Xcode/DerivedData"

echo "🔨 GasPhotoIOS Release build fordítása..."
cd "$PROJECT_ROOT"
xcodebuild -workspace GasPhotoIOS.xcworkspace \
    -scheme GasPhotoIOS \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -allowProvisioningUpdates \
    build > /dev/null

APP_PATH=$(find "$DERIVED_DATA_DIR" -name "GasPhotoIOS.app" -path "*/Release-iphoneos/*" | head -n1)

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "❌ Nem található a lefordított GasPhotoIOS.app a Release-iphoneos mappában!"
    exit 1
fi

echo "📦 IPA csomag készítése ($APP_PATH)..."
rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP_PATH" "$BUILD_DIR/Payload/"

cd "$BUILD_DIR"
zip -qr "Vigavi.ipa" Payload
cp "Vigavi.ipa" "GasPhotoIOS.ipa"
echo "✅ Elkészült: $BUILD_DIR/Vigavi.ipa ($(du -h Vigavi.ipa | cut -f1))"
