import SwiftUI

/// The reload prompt shown when the checkout page itself fails to load.
///
/// A page that never loaded is not a failed checkout: the session stays open
/// and payable, in the browser as much as here, so dismissing this returns to
/// a fresh load of the same page rather than starting a new attempt.
struct CheckoutPageFailureView: View {
    let error: any Error
    let reload: () -> Void

    // Triggers the symbol's single entrance bounce.
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .symbolEffect(.bounce, value: hasAppeared)
            VStack(spacing: 6) {
                Text("Couldn't load checkout")
                    .font(.title2.bold())
                Text(error.localizedDescription)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button("Try Again", action: reload)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
    }
}

#if DEBUG
#Preview {
    CheckoutPageFailureView(
        error: URLError(.notConnectedToInternet),
        reload: {}
    )
    .frame(width: 480, height: 640)
}
#endif
