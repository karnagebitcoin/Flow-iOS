import SwiftUI

struct SettingsInterestsFeedView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var toastCenter: AppToastCenter
    @ObservedObject private var interestFeedStore = InterestFeedStore.shared

    @State private var hashtagInput = ""
    @State private var validationMessage: String?

    var body: some View {
        ThemedSettingsForm {
            Section("Add Hashtag") {
                TextField("#technology", text: $hashtagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(addHashtag)

                Button("Add Hashtag") {
                    addHashtag()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hashtagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                if interestFeedStore.hashtags.isEmpty {
                    Text("No interest hashtags added yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(interestFeedStore.hashtags, id: \.self) { hashtag in
                        HStack(spacing: 10) {
                            Label("#\(hashtag)", systemImage: "number")
                                .foregroundStyle(.primary)

                            Spacer(minLength: 8)

                            Button {
                                interestFeedStore.removeHashtag(hashtag)
                                toastCenter.show("Removed #\(hashtag) from Interests", style: .info)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(AppSettingsStore.shared.primaryColor)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove #\(hashtag)")
                        }
                    }
                }
            } header: {
                Text("Hashtags")
            } footer: {
                Text("These hashtags power the Interests feed created during onboarding.")
            }

            if let validationMessage, !validationMessage.isEmpty {
                Section {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Interests")
        .navigationBarTitleDisplayMode(.large)
        .task {
            interestFeedStore.configure(accountPubkey: auth.currentAccount?.pubkey)
        }
        .onChange(of: auth.currentAccount?.pubkey) { _, newValue in
            interestFeedStore.configure(accountPubkey: newValue)
        }
    }

    private func addHashtag() {
        validationMessage = nil
        let normalizedHashtag = InterestTopic.normalizeHashtag(hashtagInput)
        let wasAlreadyAdded = interestFeedStore.hashtags.contains(normalizedHashtag)

        do {
            try interestFeedStore.addHashtag(hashtagInput)
            hashtagInput = ""
            if wasAlreadyAdded {
                toastCenter.show("#\(normalizedHashtag) is already in Interests", style: .info)
            } else {
                toastCenter.show("Added #\(normalizedHashtag) to Interests")
            }
        } catch {
            validationMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
