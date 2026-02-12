import Foundation

@MainActor
internal protocol Licensing: Sendable {
    func activate(licenseKey: String) async throws(AmoreError)
    func deactivate() async throws(AmoreError)
    func validate() async throws(AmoreError) -> ValidationStatus
    var status: ValidationStatus { get }
}
