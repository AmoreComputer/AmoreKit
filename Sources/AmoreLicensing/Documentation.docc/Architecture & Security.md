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
   - System clock not set back (see Clock Rollback)
4. If valid: app runs normally
5. If expired or the system clock is set back: attempt refresh from server
6. If refresh fails: enter grace period (7 days default), unless the system clock is set back. ``LicensingConfiguration/gracePeriod``
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
- Works without network until JWT expires, unless the system clock is set back (see Clock Rollback)

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

### Clock Rollback
- The SDK keeps the latest time it has seen: the signed issue time of the newest token, moved forward by each later validation
- A system clock more than an hour behind that time makes the stored token untrusted, so it is refreshed from the server. Setting the clock more than an hour behind that time does not extend an expired or revoked license. A device clock more than an hour behind the server's clock can also count as set back
- While the clock is more than an hour behind that time and the server cannot be reached, the license is invalid, even if its token has not expired, and the grace period does not apply. A server answer sets the latest time to the new token's issue time, so a corrected clock is trusted again, and a clock that is still set back needs the server at each validation
- A clock no more than an hour behind the latest time, or ahead of it, is not detected, so setting it to such a time before each launch keeps a token unexpired. The check stops casual tampering, not a determined user
- The record is kept in `UserDefaults.standard` of the app that runs the SDK, not in the ``TokenStore``, so processes that share a token through a custom ``TokenStore`` each keep their own record. Deleting it leaves only the token's issue time as the limit

### Grace Period
- App continues working N days after its token expires
- Handles temporary network outages or server downtime
- Does not apply to a license past its own end date, unless it is a subscription that renews, or while the system clock is set back (see Clock Rollback)
- Configurable per-app (default: 7 days). ``LicensingConfiguration/gracePeriod``
- Needs no extra state: the SDK computes it from the stored token's expiry
