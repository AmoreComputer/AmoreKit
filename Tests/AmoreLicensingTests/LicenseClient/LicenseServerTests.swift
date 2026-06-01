import Foundation
import Testing

@testable import AmoreLicensing

@Suite struct LicenseServerTests {
    private let baseURL = URL(string: "https://api.amore.computer")!

    @Test func initWithBaseURLComposesEndpointURLs() {
        let server = LicenseServer(
            baseURL: baseURL,
            activatePath: "v1/activate",
            deactivatePath: "v1/deactivate",
            validatePath: "v1/validate"
        )

        #expect(server.activateURL.absoluteString == "https://api.amore.computer/v1/activate")
        #expect(server.deactivateURL.absoluteString == "https://api.amore.computer/v1/deactivate")
        #expect(server.validateURL.absoluteString == "https://api.amore.computer/v1/validate")
    }

    @Test func initWithExplicitURLsPreservesThemExactly() {
        let activate = URL(string: "https://a.example.com/activate")!
        let deactivate = URL(string: "https://b.example.com/deactivate")!
        let validate = URL(string: "https://c.example.com/validate")!

        let server = LicenseServer(activateURL: activate, deactivateURL: deactivate, validateURL: validate)

        #expect(server.activateURL == activate)
        #expect(server.deactivateURL == deactivate)
        #expect(server.validateURL == validate)
    }

    @Test func amoreFactoryProducesExpectedPaths() {
        let server = LicenseServer.amore(for: "com.test.app", baseURL: baseURL)

        #expect(server.activateURL.absoluteString == "https://api.amore.computer/v2/apps/com.test.app/licenses/activate")
        #expect(server.deactivateURL.absoluteString == "https://api.amore.computer/v2/apps/com.test.app/licenses/deactivate")
        #expect(server.validateURL.absoluteString == "https://api.amore.computer/v2/apps/com.test.app/licenses/validate")
    }

    @Test func baseURLWithTrailingSlashDoesNotDoubleSlash() {
        let trailingSlashURL = URL(string: "https://api.amore.computer/")!
        let server = LicenseServer(baseURL: trailingSlashURL, activatePath: "v1/activate", deactivatePath: "v1/deactivate", validatePath: "v1/validate")

        #expect(!server.activateURL.absoluteString.contains("//v1"))
    }
}
