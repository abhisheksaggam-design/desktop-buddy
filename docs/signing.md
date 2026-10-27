# Signing Desktop Buddy

Every release must be signed with the **Desktop Buddy Signing** certificate.

## Why it matters

- **No more Keychain prompts after updates.** macOS remembers which app may read your saved sign-ins by its signature. With the same certificate on every version, an update is "the same app" and macOS doesn't ask again.
- **Safe in-app updates.** "Update and Restart" only installs a download signed with this same certificate, and only if it matches the release's `Desktop-Buddy.dmg.sha256` checksum.

It's a free, self-made certificate, not an Apple Developer ID, so first-time installs still show "Apple could not verify…" (see the README). A paid Apple Developer ID ($99/year) plus notarisation would remove that too.

## Where it is

- Installed in the login keychain of the Mac that builds releases. `./build-app.sh` finds it automatically and prints "Signed with Desktop Buddy Signing".
- Backup: `~/Documents/Desktop Buddy Signing/signing.p12`, with its password in `p12-password.txt` next to it. **Keep a copy in your password manager.** If the certificate is lost, a new one breaks in-app updates: everyone has to download the next version by hand once, and sees one more Keychain prompt.

## Building on another Mac

```bash
security import signing.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
```

Enter the password from `p12-password.txt` when asked. Never commit `signing.p12` or its password.
