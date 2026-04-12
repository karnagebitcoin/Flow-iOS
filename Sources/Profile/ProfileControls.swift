import SwiftUI

struct ProfileActionIconButton: View {
    let systemImage: String
    let isPrimary: Bool
    let isDisabled: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        let style = appSettings.themePalette.profileActionStyle
        let disabledOpacity = isDisabled ? 0.48 : 1.0
        let foreground = isPrimary
            ? (style?.primaryForeground ?? Color.white)
            : (style?.foreground ?? (isDisabled ? appSettings.themePalette.mutedForeground : appSettings.themePalette.foreground))
        let background = isPrimary
            ? (style?.primaryBackground ?? Color.accentColor)
            : (style?.background ?? appSettings.themePalette.secondaryGroupedBackground)
        let borderColor = isPrimary ? style?.primaryBorder : style?.border

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 18, height: 18)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .foregroundStyle(foreground.opacity(disabledOpacity))
                .background(
                    Capsule()
                        .fill(background.opacity(isDisabled && style != nil ? 0.72 : 1))
                )
                .overlay {
                    if let borderColor {
                        Capsule()
                            .stroke(borderColor.opacity(disabledOpacity), lineWidth: 0.8)
                    } else if !isPrimary {
                        Capsule()
                            .stroke(appSettings.themePalette.separator.opacity(0.7), lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct ProfileBannerCircleIcon: View {
    let systemImage: String
    let foreground: Color
    let border: Color
    let background: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(background)
            )
            .overlay {
                Circle()
                    .stroke(border, lineWidth: 1)
            }
    }
}

struct ProfileMenuOptionLabel: View {
    let title: String
    let systemImage: String

    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        Label {
            Text(title)
                .font(appSettings.appFont(.body))
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(appSettings.primaryColor)
        }
    }
}

struct ProfileFeedLoadingRow: View {
    @EnvironmentObject private var appSettings: AppSettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(appSettings.themePalette.secondaryFill)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(width: 150, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(appSettings.themePalette.secondaryFill)
                    .frame(width: 180, height: 14)
            }
        }
        .padding(.vertical, 10)
        .redacted(reason: .placeholder)
    }
}
