# ``AmoreLicensing``

A macOS licensing SDK for license activation, validation, and deactivation.

## Overview

AmoreLicensing is the licensing SDK for [Amore](https://amore.computer).

AmoreLicensing provides an `@Observable` class that manages the full license lifecycle, including activation, validation, and deactivation, with offline-first design and hardware ID binding. Integrate it with SwiftUI to reactively update your UI based on the current license status.

> Work In Progress: AmoreLicensing is still under active development. If you have any suggestions or questions reach out to [amore@lucas.love](mailto:amore@lucas.love).

## Topics

### Articles

- <doc:Getting-Started>
- <doc:Architecture-&-Security>

### Essentials

- ``AmoreLicensing``
- ``License``
- ``License/Entitlement``
- ``EntitlementProtocol``
- ``ValidationStatus``

### Configuration

- ``LicensingConfiguration``
- ``LicenseServer``
- ``ValidationFrequency``
- ``GracePeriod``

### Token Storage

- ``TokenStore``
- ``FileTokenStore``

### Errors

- ``AmoreError``
- ``ClientError``
- ``TokenStoreError``
- ``NetworkError``
