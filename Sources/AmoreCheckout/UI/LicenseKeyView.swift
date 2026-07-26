import AppKit
import SwiftUI

struct LicenseKeyView: View {
    let licenseKey: String
    
    @State private var isCopied = false
    
    var body: some View {
        HStack {
            Text(licenseKey)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Spacer()
            copyControl
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .frame(width: 16, height: 16)
        }
        .task(id: isCopied) {
            guard isCopied else { return }
            try? await Task.sleep(for: .seconds(2))
            isCopied = false
        }
    }
    
    @ViewBuilder
    private var copyControl: some View {
        if isCopied {
            Label("Copied", systemImage: "checkmark.circle.fill")
        } else {
            Button("Copy", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(licenseKey, forType: .string)
                isCopied = true
            }
        }
    }
}

#if DEBUG
#Preview {
    LicenseKeyView(licenseKey: "AMORE-4F2A-91C7-BD03")
        .padding()
}
#endif
