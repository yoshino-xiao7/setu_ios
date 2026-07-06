# Passkey Associated Domains

This project includes `SetuIOSApp.entitlements` as the Xcode target entitlement template for native Passkey registration and login.

## Xcode Target

1. Open the iOS app target in Xcode.
2. Enable **Signing & Capabilities > Associated Domains**.
3. Set the target's entitlements file to `SetuIOSApp.entitlements`.
4. Keep these associated domains in sync with the WebAuthn relying party:

```text
applinks:cloud.yukiryou.icu
webcredentials:cloud.yukiryou.icu
```

## Backend

The backend WebAuthn RP ID must match the credential domain:

```text
WEBAUTHN_RP_ID=cloud.yukiryou.icu
WEBAUTHN_ALLOWED_ORIGINS=https://cloud.yukiryou.icu
```

Development may still use localhost for web testing, but native device Passkeys require a real associated domain over HTTPS.

## Website

Host an Apple App Site Association file at:

```text
https://cloud.yukiryou.icu/.well-known/apple-app-site-association
```

It must include the app identifier for the signed iOS bundle under `webcredentials.apps` and, if universal links are used, `applinks.details`.
