#!/bin/bash
# Cleanly rebuild every shipping component, then create public-safe Release assets.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

ROOT="$PWD"
RELEASE_VERSION="${1:-}"

if [ -z "$RELEASE_VERSION" ]; then
    echo "usage: dist/build-release.sh VERSION  (example: 0.1.0-beta.1)" >&2
    exit 2
fi
if ! [[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "invalid release version: $RELEASE_VERSION" >&2
    exit 2
fi
[ -f "dist/release-notes-v$RELEASE_VERSION.md" ] || {
    echo "missing release notes: dist/release-notes-v$RELEASE_VERSION.md" >&2
    exit 2
}

if [ "${HYPERVIBE_ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain)" ]; then
    echo "REFUSED: release builds require a clean worktree" >&2
    echo "set HYPERVIBE_ALLOW_DIRTY=1 only for a local packaging test" >&2
    exit 2
fi

if [ "$(uname -m)" != "arm64" ]; then
    echo "REFUSED: the first public binary release is defined as Apple-silicon only" >&2
    exit 2
fi

APP_VERSION="${RELEASE_VERSION%%-*}"
. dist/version.sh
BUILD_NUMBER="$(hypervibe_build_number "$RELEASE_VERSION")"
export HYPERVIBE_BUILD_NUMBER="$BUILD_NUMBER"
export HYPERVIBE_RELEASE_VERSION="$RELEASE_VERSION"
COMMIT="$(git rev-parse HEAD)"
# Fail before the expensive build when the fork-specific signing key is absent or mismatched.
if [ -z "${HYPERVIBE_SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SPARKLE_ROOT="$(app/prepare_sparkle.sh)"
    KEYCHAIN_PUBLIC_KEY="$("$SPARKLE_ROOT/bin/generate_keys" \
        --account "${HYPERVIBE_SPARKLE_ACCOUNT:-doer-ee.SiriRemoteVibe}" -p)"
    [ "$KEYCHAIN_PUBLIC_KEY" = "$(tr -d '[:space:]' < app/sparkle-public-key.txt)" ] || {
        echo "Release signing key does not match app/sparkle-public-key.txt" >&2
        exit 1
    }
fi
OPUS_PREFIX="$(dist/build-opus.sh)"
APP_STAGE="$ROOT/dist/build/staging/$RELEASE_VERSION/Siri Remote for Vibe Coding.app"

case "$APP_STAGE" in
    "$ROOT/app/"*)
        echo "REFUSED: Release staging must never write inside app/" >&2
        exit 2
        ;;
esac

/bin/rm -rf "$ROOT/dist/build/staging/$RELEASE_VERSION"
/bin/mkdir -p "$(dirname "$APP_STAGE")"

echo "→ building SiriRemoteVibe $APP_VERSION ($COMMIT)"
(
    cd app
    ./build.sh
    HYPERVIBE_VERSION="$APP_VERSION" \
    HYPERVIBE_BUILD_NUMBER="$BUILD_NUMBER" \
    HYPERVIBE_RELEASE_VERSION="$RELEASE_VERSION" \
    HYPERVIBE_SIGN_MODE=adhoc \
    HYPERVIBE_APP_BUNDLE_PATH="$APP_STAGE" \
        ./create_app_bundle.sh
)

echo "→ building microphone router"
(cd mic/router && HYPERVIBE_OPUS_PREFIX="$OPUS_PREFIX" ./build.sh)

echo "→ building microphone HAL plug-in"
(
    cd mic/driver
    HYPERVIBE_VERSION="$APP_VERSION" \
    HYPERVIBE_BUILD_NUMBER="$BUILD_NUMBER" \
        ./build.sh
)

echo "→ building capture daemon"
(cd mic/captured && ./build.sh)

echo "→ packaging public Release assets"
HYPERVIBE_SOURCE_COMMIT="$COMMIT" \
HYPERVIBE_APP_PATH="$APP_STAGE" \
    dist/package.sh --version "$RELEASE_VERSION"

dist/audit-release.sh "$RELEASE_VERSION"
dist/update-appcast.sh "$RELEASE_VERSION"
