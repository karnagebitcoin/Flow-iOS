import Foundation

struct ComposePollOption: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var text: String

    init(id: String = ComposePollOption.makeIdentifier(), text: String = "") {
        self.id = id
        self.text = text
    }

    private static func makeIdentifier() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(9))
    }
}

struct ComposePollDraft: Hashable, Codable, Sendable {
    var allowsMultipleChoice: Bool
    var options: [ComposePollOption]
    var endsAt: Date?

    init(
        allowsMultipleChoice: Bool = false,
        options: [ComposePollOption],
        endsAt: Date? = ComposePollDraft.defaultEndDate()
    ) {
        self.allowsMultipleChoice = allowsMultipleChoice
        self.options = options
        self.endsAt = endsAt.map(Self.roundToMinute(_:))
    }

    static func defaultDraft(now: Date = Date()) -> ComposePollDraft {
        ComposePollDraft(
            allowsMultipleChoice: false,
            options: [ComposePollOption(), ComposePollOption()],
            endsAt: defaultEndDate(from: now)
        )
    }

    static func defaultEndDate(from now: Date = Date()) -> Date {
        let roundedNow = roundToMinute(now)
        let fallback = roundedNow.addingTimeInterval(24 * 60 * 60)
        return Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: roundedNow) ?? fallback
    }

    var validOptions: [ComposePollOption] {
        options.compactMap { option in
            let trimmedText = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else { return nil }
            return ComposePollOption(id: option.id, text: trimmedText)
        }
    }

    var validOptionCount: Int {
        validOptions.count
    }

    var hasMinimumOptions: Bool {
        validOptionCount >= 2
    }

    static func roundToMinute(_ date: Date) -> Date {
        let timeInterval = date.timeIntervalSinceReferenceDate
        let minuteInterval = floor(timeInterval / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: minuteInterval)
    }
}
