# Persistent local signing

This Mac uses the self-signed **siriRemote Local Signing** certificate in its login Keychain.
It is trusted for code signing only. No Apple Developer subscription is required, and the private
key stays in Keychain. The temporary private-key export used during setup was removed immediately
after import. This certificate does not provide Apple notarization or Apple trust on other Macs.

The local, non-secret file `~/.config/siriremote/build-signing-mode` contains `stable`. Both
`app/create_app_bundle.sh` and `dist/build-release.sh` honor it through `app/sign_app_bundle.sh`.
Machines without this file continue to use ad-hoc signing. Explicit environment settings take
precedence:

```sh
HYPERVIBE_SIGN_MODE=stable ./create_app_bundle.sh
HYPERVIBE_SIGN_MODE=stable dist/build-release.sh VERSION
```

`HYPERVIBE_SIGN_KEYCHAIN` can select a Keychain explicitly. Otherwise an existing
`~/Library/Keychains/siriremote-signing.keychain-db` is preferred, followed by the login Keychain.
A requested stable build fails if the identity cannot be used; it never silently switches to
ad-hoc signing. The shared signer signs nested code before signing and verifying the outer App.
The outer App retains its existing entitlements and stays without hardened runtime.

Switching from the old ad-hoc App to this certificate may require one permission approval.
Subsequent builds must keep the same certificate, bundle identifier and designated requirement.
This also applies to release archives downloaded by Sparkle: an ad-hoc archive would undo the
continuity. The existing published 1.0.1 archive remains ad-hoc signed; it was not replaced.
Sparkle's separate Ed25519 key still authenticates downloads and is unchanged by local signing.

Do not delete or regenerate this certificate between releases. Keep a protected backup of the
certificate and private key through Keychain Access if needed; never commit a private key,
Keychain password or certificate export containing a private key to Git.

## Verified on this Mac

The installed 1.0.1 App was signed and approved once with the new certificate. A second signed
revision removed a temporary resource, producing a different CDHash but exactly the same
certificate-bound designated requirement. After replacing the installed App and restarting it,
System Check still showed **Accessibility Granted** and **Input Monitoring Granted** without
resetting TCC or granting permissions again. Both bundles passed deep, strict signature verification,
and the credential broker matched the App's certificate-bound peer requirement. This tests local
App replacement; a future Sparkle release must still pass the normal release/update verification.
