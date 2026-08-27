# Architecture & Security

Learn more about AmoreLicensing's architecture and security.

## Architecture

Client-server licensing system using JWT-based validation with client-generated nonces for MITM and replay attack protection.

Server stores per-app private keys for signing JWTs. Clients verify signatures and validate nonces to ensure responses haven't been tampered with. Hardware ID binding prevents license sharing across devices.

## Authentication Flow

### Initial Activation (one-time per device)

1. User enters license key in app
2. Client generates:
   - Hardware ID: a salted hash of this device's identifier (see Device Identifier Privacy)
   - Random nonce (UUID)
3. Client sends HTTPS POST to server:
   { license_key, hardware_id, nonce }
4. Server validates:
   - License key exists and isn't revoked
   - Device limit not exceeded for this license
   - Records hardware_id binding
5. Server creates JWT containing:
   { hardware_id, nonce, iat, exp (30 days), license_id }
6. Server signs JWT with app's private key
7. Server returns: { token }
8. Client verifies:
   - JWT signature valid (using server's public key)
   - Nonce matches what client sent
   - JWT not expired
9. Client stores JWT in the file system

### Ongoing Validation (offline-first)

1. App launches
2. Client loads JWT from file system
3. Client verifies locally:
   - Signature valid
   - Not expired
   - Hardware ID matches current device
4. If valid: app runs normally
5. If expired: attempt refresh from server
6. If refresh fails: enter grace period (7 days default). ``LicensingConfiguration/gracePeriod``
7. After grace period: block or degrade features

### Refresh Flow (when JWT expires)

1. Client generates new nonce
2. Client sends: { hardware_id, old_jwt, nonce }
3. Server validates:
   - Old JWT signature valid
   - License not revoked
   - Hardware ID still authorized
4. Server issues new JWT with new nonce + expiration
5. Client verifies nonce and updates stored JWT

## Security Mechanisms

### MITM & Replay Attack Protection
- HTTPS encrypts license key transmission
- Client-generated nonce prevents request tampering
- Server includes nonce in signed JWT
- Client rejects responses with mismatched nonce

### Offline Validation
- JWT signature verified locally (no server round-trip)
- Cryptographically proves JWT came from licensing server
- Works without network until JWT expires

### Hardware Binding
- License tied to a specific device via its hardware ID
- JWT contains the hardware ID (signed by server)
- Client verifies the JWT's hardware ID against this device on each validation
- Prevents JWT theft/sharing between devices

### Device Identifier Privacy
- The hardware ID is not the raw device identifier: it is an HMAC-SHA256 of it, keyed with the app's bundle identifier and prefixed `h1:`
- The raw device identifier (the built-in macOS ``DeviceIdentity`` reads IOPlatformSerialNumber) never leaves the device
- The bundle identifier salt makes the same device pseudonymous per app, so the server cannot correlate a device across apps
- Hashing defeats enumeration and leakage of device identifiers, not targeted confirmation: the salt is public, so a candidate identifier can be checked for a match

> Note: For a plain-language list of every field AmoreLicensing sends, written
> for the people who use your app, see
> [What your app sends to Amore](https://amore.computer/privacy/app-data/).
> It carries a paragraph you can paste into your own privacy policy.

### Grace Period
- App continues working N days after last successful validation
- Handles temporary network outages or server downtime
- Configurable per-app (default: 7 days). ``LicensingConfiguration/gracePeriod``
- Stored: last validation timestamp from JWT
