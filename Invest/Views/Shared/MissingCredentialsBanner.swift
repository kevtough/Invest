import SwiftUI

/// Shown at the top of a screen when required API credentials haven't been
/// entered yet.
struct MissingCredentialsBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.subheadline.weight(.medium))
                Text("Open the Settings tab to add it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
