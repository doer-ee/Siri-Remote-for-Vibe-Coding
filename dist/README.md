# Release packaging

The release builder creates three Apple-silicon macOS downloads from a clean checkout:

- **`SiriRemoteVibe-Full-Setup-VERSION-arm64.pkg`** — the primary native macOS Installer. It installs
  the app, virtual microphone, router, on-demand capture service, and uninstaller with one
  administrator approval. Siri Remote Vibe then opens its live System Check for the privacy permissions
  macOS deliberately keeps under the user's control.

- **`SiriRemoteVibe-VERSION-macOS-arm64.zip`** — the menu-bar app only. Unzip, move
  `Siri Remote for Vibe Coding.app` to Applications, then right-click it and choose **Open** the first time.
- **`SiriRemoteVibe-Full-Setup-VERSION-arm64.zip`** — the app plus the Siri Remote Mic HAL plug-in,
  router, capture daemon, and an uninstaller. This is the advanced option because it installs
  system audio and Bluetooth-capture components with an administrator password.

`SHA256SUMS.txt` covers the native Installer and both archives. GitHub supplies source archives
separately.

## Build public Release assets

The only local prerequisite is Xcode command-line tools. The builder downloads the official,
checksum-pinned libopus 1.6.1 source, compiles it for macOS 13, and links it statically into the
shipping router. Neither the build Mac nor the destination Mac needs Homebrew.

```sh
dist/build-release.sh 1.0.1
```

The command requires a clean worktree, rebuilds every shipping binary, injects the numeric app
version and a monotonic internal build number, uses reproducible ad-hoc signing in an isolated
staging bundle, runs the router and HAL
offline tests, and writes:

```text
dist/build/1.0.1/
├── SiriRemoteVibe-1.0.1-macOS-arm64.zip
├── SiriRemoteVibe-Full-Setup-1.0.1-arm64.zip
├── SiriRemoteVibe-Full-Setup-1.0.1-arm64.pkg
└── SHA256SUMS.txt
```

Generated output remains ignored by Git because personal packages may contain private material.
Upload only the four audited files above, never the whole `dist/build/` directory.
`build-release.sh` finishes by running `audit-release.sh`, which independently extracts both
archives and fails on invalid signatures/checksums, wrong versions or architectures, Homebrew
runtime links, missing license notices, private paths, author config, PacketLogger, or video files.
The libopus source archive and build output are cached under ignored `dist/build/` paths.
The builder never rewrites `app/Siri Remote for Vibe Coding.app`, so the installed local development App
and its macOS privacy grants are left untouched.

The final step also updates and signs the repository-root `appcast.xml`. Siri Remote Vibe checks that feed
daily and can download the app-only ZIP in the background. Every archive is authenticated with
Sparkle Ed25519 before extraction; published feeds receive an additional whole-feed signature.
The public key is committed as `app/sparkle-public-key.txt`. The private key remains in the
maintainer's login Keychain under account `doer-ee.SiriRemoteVibe` and must never be committed. Back it up
to encrypted offline storage with Sparkle's
`generate_keys --account doer-ee.SiriRemoteVibe -x /encrypted/backup/key.txt`, and import it on a replacement release machine with `generate_keys --account doer-ee.SiriRemoteVibe -f /encrypted/backup/key.txt`.
Automatic updates replace only `Siri Remote for Vibe Coding.app`, so they do not restart system audio or request an
administrator password. Full Setup remains a separate, explicitly selected download when users want
to install or refresh the virtual microphone and its privileged services.

## Public-package safety boundary

Public mode is the default. It always uses `examples/config.jsonc` and refuses both a custom config
and PacketLogger. The payload has its own SHA-256 manifest, which the privileged installer verifies
before changing the system.

The Full Setup installer:

1. installs the app and `Siri Remote Vibe Uninstall.app`;
2. preserves the pre-existing Bluetooth `HCITraces` preference;
3. installs the HAL plug-in and restarts `coreaudiod`;
4. monitors `coreaudiod` for 25 seconds and restores the previous plug-in if CPU remains at or above
   85% for three consecutive seconds;
5. installs the on-demand capture daemon only after that check passes.

The uninstaller removes the app, HAL plug-in, daemon, and support binaries, then restores the prior
`HCITraces` value. It intentionally keeps the user's `~/.config/siriremote` directory and Apple's
separately installed PacketLogger.

If PacketLogger is absent, the installed daemon leaves Bluetooth HCI debug traces unchanged and
remote voice stays disabled. Installing PacketLogger later activates trace capture lazily on the
next microphone demand; no reboot is required.

## PacketLogger and remote voice

Remote voice capture needs Apple's PacketLogger from
[*Additional Tools for Xcode*](https://developer.apple.com/download/all/?q=Additional+Tools+for+Xcode)
at `/Applications/PacketLogger.app`. It is not redistributable as part of this public project and is
never included in public Release assets. Full Setup offers Apple's download page if it is missing;
the app and built-in-microphone fallback still work without it.

For a private transfer between machines you control, packaging a local config and, subject to
Apple's license, an existing PacketLogger copy is an explicit separate mode:

```sh
dist/package.sh --personal --version local --config /path/to/config.jsonc
dist/package.sh --personal --version local --config /path/to/config.jsonc --with-packetlogger
```

Personal output prints a warning and must never be uploaded to GitHub.

## Signing and Gatekeeper

These release app bundles are ad-hoc signed, not Apple-notarized. The hardened runtime is intentionally
disabled because it terminates the private MultitouchSupport callback used by the remote trackpad.
An ad-hoc identifier is not a trustworthy Keychain peer identity, so ad-hoc releases do not invoke the
certificate-bound credential helper. Native cloud dictation remains available by storing keys in a
separate current-user-only plaintext JSON file under Application Support; the shareable config and
release artifacts never contain it. Certificate-bound builds continue to prefer the login Keychain.
The native package is unsigned unless `HYPERVIBE_INSTALLER_SIGN_IDENTITY` names a real Developer ID
Installer identity; App signing and Installer signing are separate Apple certificate types. Until
both Developer ID signing and notarization are configured, use **right-click → Open** for the first
launch. Do not tell users to globally disable Gatekeeper.

## Fork update signing

Release preparation fails early if the Keychain public key does not match the committed public key.
`HYPERVIBE_SPARKLE_ACCOUNT` can select a different account with the same key, and the existing
`HYPERVIBE_SPARKLE_PRIVATE_KEY_FILE` override remains available for controlled release environments.
Archive signatures are independently verified with CryptoKit against the committed public key before
publishing a feed item. An override cannot silently sign a release with another key.

Older builds embed the upstream public key and require a one-time manual install of 1.0.1. Keep the
fork's signing key for subsequent releases; changing it breaks the established update trust chain.
