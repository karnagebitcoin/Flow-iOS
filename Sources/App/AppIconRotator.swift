import Foundation
import UIKit

public struct AppIconRotator {
    public typealias SetIconNameWithCompletion = (_ iconName: String?, _ completion: @escaping (Bool) -> Void) -> Void

    public static let weeklyIconNames: [String] = (1...13).map {
        String(format: "AppIcon-Weekly-%02d", $0)
    }

    private static let lastAppliedWeekKey = "flow.appIconRotator.lastAppliedWeek.v1"
    private static let rotationEpochComponents = DateComponents(
        calendar: Calendar(identifier: .iso8601),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 1,
        day: 5
    )

    private let defaults: UserDefaults
    private let iconNames: [String]
    private let dateProvider: () -> Date
    private let calendar: Calendar
    private let currentIconNameProvider: () -> String?
    private let setIconNameWithCompletion: SetIconNameWithCompletion

    public init(
        defaults: UserDefaults = .standard,
        iconNames: [String],
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .iso8601),
        currentIconNameProvider: @escaping () -> String?,
        setIconName: @escaping (String?) -> Void
    ) {
        self.init(
            defaults: defaults,
            iconNames: iconNames,
            dateProvider: dateProvider,
            calendar: calendar,
            currentIconNameProvider: currentIconNameProvider,
            setIconNameWithCompletion: { iconName, completion in
                setIconName(iconName)
                completion(true)
            }
        )
    }

    public init(
        defaults: UserDefaults = .standard,
        iconNames: [String],
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .iso8601),
        currentIconNameProvider: @escaping () -> String?,
        setIconNameWithCompletion: @escaping SetIconNameWithCompletion
    ) {
        self.defaults = defaults
        self.iconNames = iconNames
        self.dateProvider = dateProvider
        self.calendar = calendar
        self.currentIconNameProvider = currentIconNameProvider
        self.setIconNameWithCompletion = setIconNameWithCompletion
    }

    public func rotateIfNeeded() {
        let date = dateProvider()
        let weekIdentifier = Self.weekIdentifier(for: date, calendar: calendar)
        guard defaults.string(forKey: Self.lastAppliedWeekKey) != weekIdentifier else { return }
        guard let iconName = Self.weeklyIconName(for: date, iconNames: iconNames, calendar: calendar) else { return }

        guard currentIconNameProvider() != iconName else {
            defaults.set(weekIdentifier, forKey: Self.lastAppliedWeekKey)
            return
        }

        setIconNameWithCompletion(iconName) { didApply in
            guard didApply else { return }
            defaults.set(weekIdentifier, forKey: Self.lastAppliedWeekKey)
        }
    }

    public static func weeklyIconName(
        for date: Date,
        iconNames: [String],
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> String? {
        guard !iconNames.isEmpty else { return nil }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let epochStart = rotationEpochComponents.date ?? weekStart
        let weekOffset = calendar.dateComponents([.weekOfYear], from: epochStart, to: weekStart).weekOfYear ?? 0
        let index = nonnegativeModulo(weekOffset, iconNames.count)
        return iconNames[index]
    }

    static func availableWeeklyIconNames(bundle: Bundle = .main) -> [String] {
        let alternateIconNames = Set(availableAlternateIconNames(bundle: bundle))
        return weeklyIconNames.filter { alternateIconNames.contains($0) }
    }

    @MainActor
    static func rotateWeeklyIfNeeded(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        rotateWeeklyIfNeeded(
            defaults: defaults,
            bundle: bundle,
            application: .shared
        )
    }

    @MainActor
    static func rotateWeeklyIfNeeded(
        defaults: UserDefaults,
        bundle: Bundle,
        application: UIApplication
    ) {
        guard !isRunningUnderXCTest() else { return }
        guard application.supportsAlternateIcons else { return }
        let availableIconNames = availableWeeklyIconNames(bundle: bundle)
        guard !availableIconNames.isEmpty else { return }

        let rotator = AppIconRotator(
            defaults: defaults,
            iconNames: availableIconNames,
            currentIconNameProvider: { application.alternateIconName },
            setIconNameWithCompletion: { iconName, completion in
                application.setAlternateIconName(iconName) { error in
                    completion(error == nil)
                }
            }
        )
        rotator.rotateIfNeeded()
    }

    private static func weekIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    static func isRunningUnderXCTest(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil ||
        environment["XCTestSessionIdentifier"] != nil
    }

    private static func availableAlternateIconNames(bundle: Bundle) -> [String] {
        let infoDictionaryKeys = ["CFBundleIcons", "CFBundleIcons~ipad"]
        return infoDictionaryKeys.flatMap { key -> [String] in
            guard let iconDictionary = bundle.object(forInfoDictionaryKey: key) as? [String: Any],
                  let alternateIcons = iconDictionary["CFBundleAlternateIcons"] as? [String: Any] else {
                return []
            }
            return Array(alternateIcons.keys)
        }
    }

    private static func nonnegativeModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
