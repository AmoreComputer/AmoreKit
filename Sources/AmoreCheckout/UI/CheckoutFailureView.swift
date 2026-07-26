import AmoreLicensing
import SwiftUI

/// The terminal error screen for a failed checkout.
///
/// Activation failures surface the license key so the completed purchase is
/// never lost, and a license still on its way reads as a warning rather than
/// a failure. Every case offers a retry: resuming a paid pending session
/// re-attempts activation instead of charging again.
struct CheckoutFailureView: View {
    let error: CheckoutError
    let portalURL: URL
    let retry: () -> Void

    // Triggers the symbol's single entrance bounce.
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: presentation.symbol)
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(presentation.color)
                .symbolEffect(.bounce, value: hasAppeared)
            VStack(spacing: 6) {
                Text(presentation.title)
                    .font(.title2.bold())
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let licenseKey {
                keyCard(licenseKey)
            }
            Spacer()
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
    }

    // MARK: - Private

    // A purchase that succeeded but did not activate is a warning, not a
    // failure; only an actual loss gets the red cross.
    private var presentation: (symbol: String, color: Color, title: String) {
        switch error {
        case .activationFailed:
            ("exclamationmark.triangle.fill", .yellow, "Activation failed")
        case .licenseIssuanceTimedOut:
            ("clock.fill", .yellow, "License on its way")
        case .pollingFailed:
            ("exclamationmark.triangle.fill", .yellow, "Connection lost")
        default:
            ("xmark.circle.fill", .red, "Purchase failed")
        }
    }

    private var licenseKey: String? {
        guard case .activationFailed(let key, _) = error else { return nil }
        return key
    }

    private func keyCard(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activate manually with this license key:")
                .font(.callout)
                .foregroundStyle(.secondary)
            LicenseKeyView(licenseKey: key)
            Divider()
            HStack {
                Text("Manage your purchase")
                    .foregroundStyle(.secondary)
                Spacer()
                Link("Customer Portal", destination: portalURL)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

#if DEBUG
#Preview("Activation Failed") {
    CheckoutFailureView(
        error: .activationFailed(
            licenseKey: "AMORE-4F2A-91C7-BD03",
            underlying: .network(.requestFailed("The request timed out."))
        ),
        portalURL: URL(string: "https://api.amore.computer/portal")!,
        retry: {}
    )
    .frame(width: 480, height: 640)
}

#Preview("License Delayed") {
    CheckoutFailureView(
        error: .licenseIssuanceTimedOut,
        portalURL: URL(string: "https://api.amore.computer/portal")!,
        retry: {}
    )
    .frame(width: 480, height: 640)
}

#Preview("Session Expired") {
    CheckoutFailureView(
        error: .sessionExpired,
        portalURL: URL(string: "https://api.amore.computer/portal")!,
        retry: {}
    )
    .frame(width: 480, height: 640)
}
#endif
