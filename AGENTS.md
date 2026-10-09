# Project operating rules

These rules are non-negotiable for every local macOS App build and test deployment.

1. The only App used for live testing is `/Applications/Siri Remote for Vibe Coding.app`.
2. After compiling and packaging a user-test build, install that verified bundle at
   `/Applications/Siri Remote for Vibe Coding.app`. Never launch `app/Siri Remote for Vibe Coding.app` as the live App.
3. Ad-hoc signing is authorized for local development builds on this Mac. The installed App and
   the October 8 builds use ad-hoc signing. Package with `HYPERVIBE_SIGN_MODE=adhoc` (the default);
   do not ask again for permission to use this signing mode. macOS permissions may need to be
   granted again after a rebuild.
4. Verify the packaged bundle's signature before replacing the installed App, and verify the
   installed copy before restarting. Stop on any signature verification failure. Stable signing
   with `siriRemote Local Signing` is optional when explicitly requested and its keychain is
   available; preserve that identity if present. An explicitly requested stable build must fail
   when its identity is unavailable rather than silently changing signing modes.
5. Restart only after installation and signature verification, then confirm the single running UI
   process executes `/Applications/Siri Remote for Vibe Coding.app/Contents/MacOS/SiriRemoteVibe`.
6. Treat Siri Remote for Vibe Coding as an always-on App. Unless the user explicitly asks to stop it, finish every
   local App build, installation, configuration change that needs a reload, or user-test handoff by
   ensuring `/Applications/Siri Remote for Vibe Coding.app` is running as exactly one UI process. Do this
   automatically; never wait for the user to ask for the App to be started.

Public release artifacts may use their explicitly requested release signing workflow. Keep local
test builds packaged as an App; never substitute the bare executable for the installed App.

Branding: full name “Siri Remote for Vibe Coding”; compact name “Siri Remote Vibe”; executable
`SiriRemoteVibe`; repository `doer-ee/Siri-Remote-for-Vibe-Coding`. Preserve `com.hypervibe.app`,
credential broker identity, Keychain services, legacy data directories, and config paths for migration.
