import AppKit
import struct AmoreStore.Product
import SwiftUI

/// Close and open-in-browser chrome around ``AmoreCheckoutView``.
struct CheckoutSheet<Completed: View>: View {
    let checkout: AmoreCheckout
    let completedView: ((CheckoutCompletion) -> Completed)?
    let customerEmail: String?
    let onResult: (CheckoutResult) -> Void
    let product: Product
    
    @Environment(\.dismiss) private var dismiss
    
    // Set on handoff to the external browser
    // A new checkout URL supersedes the handoff.
    @State private var isWaitingForBrowser = false
    
    // Closing during activation needs a second step: the user has paid, and
    // an interrupted activation only finishes at the next launch.
    @State private var isCloseConfirmationPresented = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            AmoreCheckoutView(
                checkout: checkout,
                product: product,
                customerEmail: customerEmail,
                completedView: completedView,
                waitingForBrowser: isWaitingForBrowser,
                onDone: { dismiss() },
                onResult: onResult
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 640)
        .onChange(of: checkout.checkoutURL) {
            isWaitingForBrowser = false
        }
    }
    
    private var header: some View {
        HStack {
            Button("Close") {
                if checkout.state.isCancellable || !checkout.isInProgress {
                    dismiss()
                } else {
                    isCloseConfirmationPresented = true
                }
            }
            .keyboardShortcut(.cancelAction)
            Spacer()
            if let url = checkout.checkoutURL, !isWaitingForBrowser {
                Button("Open in Browser") {
                    NSWorkspace.shared.open(url)
                    isWaitingForBrowser = true
                }
            }
        }
        .padding(12)
        .confirmationDialog(
            "Finish activating later?",
            isPresented: $isCloseConfirmationPresented
        ) {
            Button("Close") { dismiss() }
        } message: {
            Text("Your payment went through. If you close now, your license will finish activating the next time you open the app.")
        }
    }
}
