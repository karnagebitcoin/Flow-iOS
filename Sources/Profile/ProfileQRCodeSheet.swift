import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct ProfileQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: AppToastCenter

    let npub: String
    let displayName: String
    let handle: String?
    let avatarURL: URL?
    var onOpenProfile: ((String) -> Void)? = nil

    @State private var isShowingScanner = false
    @State private var pendingScannedProfilePubkey: String?

    private var qrPayload: String {
        "nostr:\(npub)"
    }

    private var qrCodeImage: UIImage? {
        QRCodeRenderer.render(payload: qrPayload)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        profileHeader
                        qrCard
                        actionRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 56)
                }
                .safeAreaInset(edge: .bottom) {
                    Color.clear
                        .frame(height: 24)
                }
            }
            .navigationTitle("Profile QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $isShowingScanner) {
            ProfileQRScannerFlowView(
                onOpenProfile: { pubkey in
                    pendingScannedProfilePubkey = pubkey
                    isShowingScanner = false
                }
            )
        }
        .onChange(of: isShowingScanner) { _, isShowing in
            guard !isShowing, let pubkey = pendingScannedProfilePubkey else { return }
            pendingScannedProfilePubkey = nil
            dismiss()
            DispatchQueue.main.async {
                onOpenProfile?(pubkey)
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                if let handle = trimmedNonEmpty(handle) {
                    Text(handle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var avatarView: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
        .overlay {
            Circle().stroke(Color(.separator).opacity(0.3), lineWidth: 0.7)
        }
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            Text(String(displayName.prefix(1)).uppercased())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var qrCard: some View {
        VStack(spacing: 12) {
            Group {
                if let qrCodeImage {
                    Image(uiImage: qrCodeImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 92, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text("Scan to open this profile")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(shortNpub)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.2 : 0.45), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.1), radius: 18, x: 0, y: 8)
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = npub
                    toastCenter.show("Copied ID")
                } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .background(
                            Capsule()
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)

                ShareLink(item: qrPayload) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
            }

            Button {
                isShowingScanner = true
            } label: {
                Label("Scan Code", systemImage: "qrcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.primary)
                    .background(
                        Capsule()
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color(.separator).opacity(0.35), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var shortNpub: String {
        guard npub.count > 28 else { return npub }
        return "\(npub.prefix(14))...\(npub.suffix(10))"
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

private enum QRCodeRenderer {
    static func render(payload: String) -> UIImage? {
        let data = Data(payload.utf8)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext(options: [.useSoftwareRenderer: false])

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
