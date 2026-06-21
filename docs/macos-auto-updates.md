# macOS Auto-Updates

Ledger uses Sparkle for direct-distribution macOS updates.

## First Install

Build and share the DMG when a user needs to install Ledger for the first time:

```bash
./scripts/build-macos-dmg.sh
```

## Subsequent Updates

Build and stage a Sparkle update archive plus appcast:

```bash
./scripts/build-macos-sparkle-update.sh
```

To deploy the staged files to Firebase Hosting:

```bash
DEPLOY=1 ./scripts/build-macos-sparkle-update.sh
```

The app checks:

```text
https://ledger-nine4.web.app/sparkle/appcast.xml
```

## Signing

Sparkle update archives are signed with the EdDSA key stored in this Mac's
Keychain. The public key embedded in `Info.plist` is:

```text
joXVPdo9X0gjd6sT2l6CeD747FzJog5ihda8cNVp8+E=
```

If you move release builds to another Mac, export/import the Sparkle private key
with Sparkle's `generate_keys` tool.

## Integration Notes

Sparkle is vendored at `LedgeriOS/Vendor/Sparkle/Sparkle.framework` and embedded
only for macOS builds. The app is sandboxed, so `SUEnableInstallerLauncherService`
is enabled and the `-spks` / `-spki` mach lookup exceptions are present in the
app entitlements. The Downloader XPC service is intentionally not enabled because
Ledger already has the outgoing network client entitlement.
