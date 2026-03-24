import SwiftUI

struct DMsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Messages coming soon")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("This tab is a placeholder while messaging is being built.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
            .navigationTitle("Messages")
        }
    }
}
