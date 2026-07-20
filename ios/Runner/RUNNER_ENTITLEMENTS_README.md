# Runner.entitlements

This file declares iOS Universal Links + iCloud Keychain webcredentials
support for the FieldFleet app. Creating the file alone isn't enough —
Xcode needs to wire it into the build.

## One-time Xcode setup

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Select the `Runner` target → `Signing & Capabilities` tab.
3. Click `+ Capability` and add **Associated Domains**.
4. Xcode will create / link `Runner.entitlements` and append the
   capability to the project settings.
5. Verify the `Associated Domains` rows match what's in this file:
   ```
   applinks:example.com
   applinks:app.example.com
   webcredentials:example.com
   webcredentials:app.example.com
   ```

Once added, every release build embeds the entitlements. On install,
iOS fetches `https://example.com/.well-known/apple-app-site-association`
and `https://app.example.com/.well-known/apple-app-site-association`
and verifies the `appID` matches `<TeamID>.com.taskfleet.taskfleet`.

## What the user sees

- Tapping a FieldFleet URL in Mail / Messages / Safari opens the app
  directly if installed; if not installed, it opens in Safari (and
  Smart App Banner appears at the top — see the landing site's
  `<head>` meta tag).
- iCloud Keychain auto-fills FieldFleet passwords across the web
  portal and the native app.

## If verification fails

iOS logs the AASA fetch + verification failure in the device console
(`Console.app`, filter for `swcd` — "shared web credentials daemon").
Common causes:

- AASA served as `text/html` instead of `application/json`.
- AASA file has `.json` extension — must be served with NO extension.
- `TeamID` placeholder still in the AASA file.
- `Runner.entitlements` not actually wired up in Build Settings
  → "Code Signing Entitlements".
