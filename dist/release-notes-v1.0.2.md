# Siri Remote for Vibe Coding 1.0.2

This maintenance release adds persistent certificate signing so macOS can recognize subsequent
updates as the same app.

## Changes

- **Persistent signing:** this release reuses the `siriRemote Local Signing` certificate used by
  the maintainer's installed 1.0.1. A local replacement test retained Accessibility and Input
  Monitoring permissions across two changed App revisions signed with that certificate.
- **Consistent build and release signing:** a shared signer handles the App, Sparkle components
  and credential broker. Local signing preferences apply to release builds as well as local builds.
- **Fail safely:** when stable signing is selected, an unavailable certificate fails the build
  instead of silently switching to ad-hoc signing.
- **Documentation:** updated build instructions and local signing guidance. Existing layouts,
  macros, push-to-talk settings, Voice data and bundle identifiers are preserved.

## Upgrade

In the App, choose **Tuning → Software Updates → Check for Updates…**, then install 1.0.2.
Updates still use this fork's existing Sparkle Ed25519 key to authenticate the archive.

The public 1.0.1 archive was ad-hoc signed. Moving from that archive to this certificate may require
permission approval once. A 1.0.1 already signed with this same local certificate is expected to
retain its permissions; this release is intended to test that path through Sparkle.

The App is self-signed, **not Apple-notarized**. This does not provide Apple Developer ID trust on
other Macs. Initial installation may require **right-click → Open / Open Anyway**. Keep Gatekeeper
enabled. macOS 13 or later on Apple silicon is required.

## Downloads

- **App only:** `SiriRemoteVibe-1.0.2-macOS-arm64.zip`; also used by the in-app updater.
- **Native Full Setup:** `SiriRemoteVibe-Full-Setup-1.0.2-arm64.pkg`; installs the App and optional
  Siri Remote Mic components. The installer package is unsigned.
- **Alternative Full Setup:** `SiriRemoteVibe-Full-Setup-1.0.2-arm64.zip`.
- **Checksums:** `SHA256SUMS.txt`.

Sparkle updates the App only. Use Full Setup for microphone system-component changes. Apple's
PacketLogger is still a separate prerequisite for remote microphone capture and is not bundled.
