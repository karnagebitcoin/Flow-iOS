import SwiftUI

private let profileHeaderBannerHeight: CGFloat = 220
private let profileHeaderAvatarSize: CGFloat = 104
private let profileHeaderContentHorizontalPadding: CGFloat = 16
private let profileHeaderSkeletonInfoRowWidths: [CGFloat] = [184, 152, 228]

struct ProfileHeaderContent {
    let displayName: String
    let handle: String
    let about: String?
    let avatarURL: URL?
    let bannerURL: URL?
    let websiteURL: URL?
    let websiteDisplayText: String?
    let lightningAddress: String?
    let followsCurrentUser: Bool
    let followingCountText: String
    let followStatusIconName: String?
    let knownFollowers: [ProfileKnownFollower]
    let actionMessage: String?

    var hasVisibleInfoRows: Bool {
        if websiteURL != nil {
            return true
        }
        if let lightningAddress, !lightningAddress.isEmpty {
            return true
        }
        return false
    }
}

struct ProfileHeaderSection<BackButton: View, MenuButton: View, ActionRow: View>: View {
    let isLoading: Bool
    let content: ProfileHeaderContent
    let onFollowingTap: () -> Void
    let onProfileTap: (String) -> Void
    let onHashtagTap: (String) -> Void
    let onRelayTap: (URL) -> Void
    let onAvatarTap: () -> Void

    private let backButton: BackButton
    private let menuButton: MenuButton
    private let actionRow: ActionRow

    @EnvironmentObject private var appSettings: AppSettingsStore

    init(
        isLoading: Bool,
        content: ProfileHeaderContent,
        onFollowingTap: @escaping () -> Void,
        onProfileTap: @escaping (String) -> Void,
        onHashtagTap: @escaping (String) -> Void,
        onRelayTap: @escaping (URL) -> Void = { _ in },
        onAvatarTap: @escaping () -> Void,
        @ViewBuilder backButton: () -> BackButton,
        @ViewBuilder menuButton: () -> MenuButton,
        @ViewBuilder actionRow: () -> ActionRow
    ) {
        self.isLoading = isLoading
        self.content = content
        self.onFollowingTap = onFollowingTap
        self.onProfileTap = onProfileTap
        self.onHashtagTap = onHashtagTap
        self.onRelayTap = onRelayTap
        self.onAvatarTap = onAvatarTap
        self.backButton = backButton()
        self.menuButton = menuButton()
        self.actionRow = actionRow()
    }

    var body: some View {
        Group {
            if isLoading {
                ProfileHeaderSkeleton(
                    backButton: backButton,
                    menuButton: menuButton
                )
            } else {
                loadedContent
            }
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileBannerArtwork(bannerURL: content.bannerURL)
                .overlay(alignment: .top) {
                    ProfileHeaderTopControls(
                        backButton: backButton,
                        menuButton: menuButton
                    )
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    ProfileAvatarView(
                        displayName: content.displayName,
                        avatarURL: content.avatarURL,
                        onTap: onAvatarTap
                    )

                    Spacer(minLength: 0)

                    actionRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ProfileIdentityBlock(
                    displayName: content.displayName,
                    handle: content.handle,
                    followStatusIconName: content.followStatusIconName,
                    followsCurrentUser: content.followsCurrentUser,
                    followingCountText: content.followingCountText,
                    onFollowingTap: onFollowingTap
                )

                if let about = content.about, !about.isEmpty {
                    ProfileAboutTextView(
                        text: about,
                        onProfileTap: onProfileTap,
                        onHashtagTap: onHashtagTap,
                        onRelayTap: onRelayTap
                    )
                }

                if content.hasVisibleInfoRows {
                    ProfileInfoRows(content: content)
                }

                if !content.knownFollowers.isEmpty {
                    ProfileKnownFollowersRow(followers: content.knownFollowers)
                }

                if let actionMessage = content.actionMessage, !actionMessage.isEmpty {
                    Text(actionMessage)
                        .font(appSettings.appFont(.footnote))
                        .foregroundStyle(appSettings.themePalette.secondaryForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: profileContentWidth, alignment: .leading)
            .padding(.horizontal, profileHeaderContentHorizontalPadding)
            .padding(.top, -(profileHeaderAvatarSize / 2))
        }
        .frame(width: UIScreen.main.bounds.width, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var profileContentWidth: CGFloat {
        max(UIScreen.main.bounds.width - (profileHeaderContentHorizontalPadding * 2), 0)
    }
}

private struct ProfileHeaderTopControls<BackButton: View, MenuButton: View>: View {
    let backButton: BackButton
    let menuButton: MenuButton

    var body: some View {
        HStack {
            backButton

            Spacer(minLength: 0)

            menuButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .zIndex(4)
        .unredacted()
    }
}

private struct ProfileBannerArtwork: View {
    let bannerURL: URL?

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        ZStack {
            bannerContent

            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    appSettings.themePalette.groupedBackground.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: profileHeaderBannerHeight)
        .background(appSettings.themePalette.secondaryBackground)
        .clipped()
    }

    @ViewBuilder
    private var bannerContent: some View {
        if appSettings.textOnlyMode {
            bannerFallback
        } else if let bannerURL {
            CachedAsyncImage(url: bannerURL, kind: .profileBanner) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    bannerFallback
                }
            }
        } else {
            bannerFallback
        }
    }

    private var bannerFallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appSettings.themePalette.secondaryBackground,
                    appSettings.primaryColor.opacity(0.20),
                    appSettings.themePalette.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 152, height: 152)
                .blur(radius: 18)
                .offset(x: 120, y: -40)

            Circle()
                .fill(appSettings.primaryColor.opacity(0.16))
                .frame(width: 188, height: 188)
                .blur(radius: 28)
                .offset(x: -132, y: 54)
        }
    }
}

private struct ProfileAvatarView: View {
    let displayName: String
    let avatarURL: URL?
    let onTap: () -> Void

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        let isInteractive = !appSettings.textOnlyMode && avatarURL != nil

        Group {
            if isInteractive {
                Button(action: onTap) {
                    avatarContent
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View profile image")
            } else {
                avatarContent
            }
        }
    }

    private var avatarContent: some View {
        Group {
            if appSettings.textOnlyMode {
                avatarFallback
            } else if let avatarURL {
                if isProfileLoopingVideoURL(avatarURL) {
                    ZStack {
                        avatarFallback
                        ProfileLoopingVideoView(
                            url: avatarURL,
                            videoGravity: .resizeAspectFill
                        )
                    }
                } else {
                    CachedAsyncImage(url: avatarURL, kind: .avatar) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            avatarFallback
                        }
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(
            width: profileHeaderAvatarSize,
            height: profileHeaderAvatarSize
        )
        .background(Circle().fill(appSettings.themePalette.background))
        .clipShape(Circle())
        .overlay {
            Circle().stroke(appSettings.themePalette.background, lineWidth: 4)
        }
        .overlay {
            Circle().stroke(appSettings.themePalette.separator.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
    }

    private var avatarFallback: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.9),
                            appSettings.themePalette.tertiaryFill
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(String(displayName.prefix(1)).uppercased())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

private struct ProfileIdentityBlock: View {
    let displayName: String
    let handle: String
    let followStatusIconName: String?
    let followsCurrentUser: Bool
    let followingCountText: String
    let onFollowingTap: () -> Void

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName)
                .font(appSettings.appFont(size: 30, weight: .heavy))
                .foregroundStyle(appSettings.themePalette.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(handle)
                    .font(appSettings.appFont(.subheadline))
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let followStatusIconName {
                    Image(systemName: followStatusIconName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }

            if followsCurrentUser {
                Text("Follows you")
                    .font(appSettings.appFont(.footnote, weight: .medium))
                    .foregroundStyle(appSettings.themePalette.mutedForeground)
            }

            Button(action: onFollowingTap) {
                HStack(spacing: 4) {
                    Text(followingCountText)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
                .font(appSettings.appFont(.footnote, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View following list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct ProfileInfoRows: View {
    let content: ProfileHeaderContent

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let websiteURL = content.websiteURL {
                Link(destination: websiteURL) {
                    ProfileInfoRow(
                        text: content.websiteDisplayText ?? websiteURL.absoluteString,
                        systemImage: "link"
                    )
                }
                .buttonStyle(.plain)
            }
            if let lightning = content.lightningAddress, !lightning.isEmpty {
                ProfileInfoRow(text: lightning, systemImage: "bolt.fill")
            }
        }
    }
}

private struct ProfileKnownFollowersRow: View {
    let followers: [ProfileKnownFollower]

    @EnvironmentObject private var appSettings: AppSettingsStore

    private var visibleFollowers: [ProfileKnownFollower] {
        Array(followers.prefix(5))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ProfileKnownFollowersAvatarStack(followers: visibleFollowers)

            Text("Followed by \(namesText)")
                .font(appSettings.appFont(.footnote, weight: .medium))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Followed by \(namesText)")
    }

    private var namesText: String {
        visibleFollowers.map(\.displayName).joined(separator: ", ")
    }
}

private struct ProfileKnownFollowersAvatarStack: View {
    let followers: [ProfileKnownFollower]

    @EnvironmentObject private var appSettings: AppSettingsStore

    private let avatarSize: CGFloat = 34
    private let overlap: CGFloat = 11

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(followers.enumerated()), id: \.element.id) { index, follower in
                ProfileKnownFollowerAvatar(follower: follower, size: avatarSize)
                    .offset(x: CGFloat(index) * (avatarSize - overlap))
                    .zIndex(Double(followers.count - index))
            }
        }
        .frame(width: stackWidth, height: avatarSize, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var stackWidth: CGFloat {
        guard !followers.isEmpty else { return 0 }
        return avatarSize + CGFloat(max(followers.count - 1, 0)) * (avatarSize - overlap)
    }
}

private struct ProfileKnownFollowerAvatar: View {
    let follower: ProfileKnownFollower
    let size: CGFloat

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        Group {
            if appSettings.textOnlyMode {
                fallback
            } else if let avatarURL = follower.avatarURL {
                CachedAsyncImage(url: avatarURL, kind: .avatar) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(appSettings.themePalette.background, lineWidth: 2.5)
        }
        .overlay {
            Circle()
                .stroke(appSettings.themePalette.separator.opacity(0.35), lineWidth: 0.7)
        }
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)

            Text(String(follower.displayName.prefix(1)).uppercased())
                .font(appSettings.appFont(.caption1, weight: .semibold))
                .foregroundStyle(appSettings.themePalette.secondaryForeground)
        }
    }
}

private struct ProfileInfoRow: View {
    let text: String
    let systemImage: String

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .imageScale(.small)
                .foregroundStyle(appSettings.themePalette.mutedForeground)
            Text(text)
                .font(appSettings.appFont(.footnote))
                .foregroundStyle(appSettings.themePalette.mutedForeground)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProfileHeaderSkeleton<BackButton: View, MenuButton: View>: View {
    let backButton: BackButton
    let menuButton: MenuButton

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(height: profileHeaderBannerHeight)
                .overlay(alignment: .top) {
                    ProfileHeaderTopControls(
                        backButton: backButton,
                        menuButton: menuButton
                    )
                }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 16) {
                    Circle()
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(
                            width: profileHeaderAvatarSize,
                            height: profileHeaderAvatarSize
                        )

                    Spacer(minLength: 0)

                    HStack(spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule()
                                .fill(appSettings.themePalette.secondaryFill)
                                .frame(width: 44, height: 40)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 210, height: 32)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 150, height: 20)

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 120, height: 16)
                }

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(height: 15)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(height: 15)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(appSettings.themePalette.secondaryFill)
                        .frame(width: 236, height: 15)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(profileHeaderSkeletonInfoRowWidths, id: \.self) { width in
                        ProfileSkeletonInfoRow(width: width)
                    }
                }
            }
            .frame(width: profileContentWidth, alignment: .leading)
            .padding(.horizontal, profileHeaderContentHorizontalPadding)
            .padding(.top, -(profileHeaderAvatarSize / 2))
        }
        .frame(width: UIScreen.main.bounds.width, alignment: .leading)
        .padding(.bottom, 8)
        .redacted(reason: .placeholder)
    }

    private var profileContentWidth: CGFloat {
        max(UIScreen.main.bounds.width - (profileHeaderContentHorizontalPadding * 2), 0)
    }
}

private struct ProfileSkeletonInfoRow: View {
    let width: CGFloat

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: width, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
