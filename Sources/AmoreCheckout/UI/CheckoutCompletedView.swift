import AmoreLicensing
import struct AmoreStore.Product
import SwiftUI

struct CheckoutCompletedView: View {
    private let completion: CheckoutCompletion
    
    // Triggers the checkmark's single entrance bounce.
    @State private var hasAppeared = false
    
    init(completion: CheckoutCompletion) {
        self.completion = completion
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: hasAppeared)
            VStack(spacing: 6) {
                Text("Purchase complete")
                    .font(.title2.bold())
                Text("Thank you for your purchase. Your license is now activated.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            summary
            Spacer()
            if let onDone = completion.onDone {
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
    }
    
    // MARK: - Private
    
    private var summary: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                HStack {
                    Text(completion.product.name)
                        .font(.headline)
                    if let price = completion.product.displayPrice {
                        Spacer()
                        Text(price)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let email = completion.license.customer?.email {
                    detailRow("Licensed to", email)
                }
                if let validity {
                    detailRow(validity.label, validity.value)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("License key")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LicenseKeyView(licenseKey: completion.licenseKey)
                Text("Keep it safe to activate other devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // The single line that best describes how long the purchase lasts:
    // the renewal date for a live subscription, otherwise the expiry.
    private var validity: (label: String, value: String)? {
        if case .renewing(let renewsAt) = completion.license.subscriptionState {
            return ("Renews", renewsAt.formatted(date: .abbreviated, time: .omitted))
        }
        if let expiresAt = completion.license.expiresAt {
            return ("Valid until", expiresAt.formatted(date: .abbreviated, time: .omitted))
        }
        return nil
    }
    
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}

#if DEBUG
#Preview("With Done") {
    CheckoutCompletedView(
        completion: CheckoutCompletion(
            license: .preview,
            licenseKey: "AMORE-4F2A-91C7-BD03",
            onDone: {},
            product: .preview
        )
    )
    .frame(width: 480, height: 640)
}

#Preview("Self-closing Container") {
    CheckoutCompletedView(
        completion: CheckoutCompletion(
            license: .preview,
            licenseKey: "AMORE-4F2A-91C7-BD03",
            product: .preview
        )
    )
    .frame(width: 480, height: 640)
}
#endif
