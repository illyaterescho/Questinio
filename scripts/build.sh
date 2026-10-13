#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h:h}"
SIGNING_DIR="$HOME/Library/Application Support/Questionio/Signing"
KEYCHAIN="$SIGNING_DIR/Questionio.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
if [[ ! -f "$KEYCHAIN" || ! -f "$PASSWORD_FILE" ]]; then
    echo "Set up stable local signing once: $PROJECT_ROOT/scripts/setup-local-signing.sh" >&2
    exit 1
fi
security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
SIGNING_IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | sed -n 's/^[[:space:]]*[0-9]*)[[:space:]]*\([0-9A-Fa-f]*\).*/\1/p' | head -1)"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Questionio signing keychain has no code-signing identity." >&2
    exit 1
fi
xcodebuild -project "$PROJECT_ROOT/LocalCopilot.xcodeproj" -scheme LocalCopilot -configuration Release -derivedDataPath "$PROJECT_ROOT/build" -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CONFIGURATION_BUILD_DIR="$PROJECT_ROOT/dist" build
codesign --force --sign "$SIGNING_IDENTITY" --keychain "$KEYCHAIN" --timestamp=none "$PROJECT_ROOT/dist/Questionio.app"
codesign --verify --deep --strict "$PROJECT_ROOT/dist/Questionio.app"
