import AmoreLicensing

// Init
let licensing = try AmoreLicensing(
    publicKey: "sa92JNtsaYefYp0MIWQbKu1hpS9bSN89ta7b8mlPbI8=",
    autoValidate: true,
    configuration: .init(gracePeriod: .days(7)) // optional
)

// Activating the license
try await licensing.activate(licenseKey: "amore-9378a1e0-25b1-446f-b831")

// Manual validation (optional)
try await licensing.validate()

// Observable Status
switch licensing.status {
case .valid: print("License is valid")
case .invalid: print("License is invalid")
case .gracePeriod(let endDate): print("Grace period until \(endDate)")
case .unknown: print("License status unknown")
}
