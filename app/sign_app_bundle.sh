#!/bin/bash
# Reuse one certificate across local builds and releases on opted-in Macs.
set -euo pipefail
APP_BUNDLE="${1:?usage: sign_app_bundle.sh APP_BUNDLE}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SIGN_MODE="${HYPERVIBE_SIGN_MODE:-adhoc}"
if [ -z "${HYPERVIBE_SIGN_MODE:-}" ] && [ -f "$HOME/.config/siriremote/build-signing-mode" ]; then
    SIGN_MODE="$(cat "$HOME/.config/siriremote/build-signing-mode")"
fi
SIGN_ID="siriRemote Local Signing"
SIGN_KC="${HYPERVIBE_SIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
if [ -z "${HYPERVIBE_SIGN_KEYCHAIN:-}" ] && [ -f "$HOME/Library/Keychains/siriremote-signing.keychain-db" ]; then
    SIGN_KC="$HOME/Library/Keychains/siriremote-signing.keychain-db"
fi
case "$SIGN_MODE" in
    stable)
        if ! security find-certificate -c "$SIGN_ID" "$SIGN_KC" >/dev/null 2>&1; then
            echo "Error: stable signing identity '$SIGN_ID' is unavailable in $SIGN_KC" >&2
            echo "Refusing to fall back to ad-hoc signing." >&2
            exit 1
        fi
        ;;
    adhoc) SIGN_ID="-" ;;
    *) echo "Error: unknown signing mode: $SIGN_MODE" >&2; exit 1 ;;
esac
# macOS ships Bash 3.2, whose nounset handling rejects expansion of empty arrays.
# Route the optional Keychain argument explicitly so ad-hoc mode works there too.
run_codesign() {
    if [ "$SIGN_MODE" = "stable" ]; then
        /usr/bin/codesign --keychain "$SIGN_KC" "$@"
    else
        /usr/bin/codesign "$@"
    fi
}
echo "Signing App ($SIGN_MODE): $APP_BUNDLE"
SPARKLE_B="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework/Versions/B"
run_codesign --force --sign "$SIGN_ID" \
    "$APP_BUNDLE/Contents/XPCServices/HyperVibeCredentialBroker.xpc"
run_codesign --force --options runtime --sign "$SIGN_ID" \
    "$SPARKLE_B/XPCServices/Installer.xpc"
run_codesign --force --options runtime --preserve-metadata=entitlements \
    --sign "$SIGN_ID" "$SPARKLE_B/XPCServices/Downloader.xpc"
run_codesign --force --options runtime --sign "$SIGN_ID" "$SPARKLE_B/Autoupdate"
run_codesign --force --options runtime --sign "$SIGN_ID" "$SPARKLE_B/Updater.app"
run_codesign --force --options runtime --sign "$SIGN_ID" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
# The outer App must remain without hardened runtime for MultitouchSupport.
run_codesign --force --entitlements "$SCRIPT_DIR/SiriRemoteVibe.entitlements" \
    --sign "$SIGN_ID" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
