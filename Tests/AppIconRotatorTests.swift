import XCTest
@testable import Flow

final class AppIconRotatorTests: XCTestCase {
    func testWeeklyIconNamesStartWithThirteenBundledSlots() {
        XCTAssertEqual(AppIconRotator.weeklyIconNames.count, 13)
        XCTAssertEqual(AppIconRotator.weeklyIconNames.first, "AppIcon-Weekly-01")
        XCTAssertEqual(AppIconRotator.weeklyIconNames.last, "AppIcon-Weekly-13")
    }

    func testSelectsSameIconWithinSameISOWeek() throws {
        let calendar = Calendar(identifier: .iso8601)
        let monday = try XCTUnwrap(date(year: 2026, month: 4, day: 20))
        let sunday = try XCTUnwrap(date(year: 2026, month: 4, day: 26))

        let first = AppIconRotator.weeklyIconName(
            for: monday,
            iconNames: AppIconRotator.weeklyIconNames,
            calendar: calendar
        )
        let second = AppIconRotator.weeklyIconName(
            for: sunday,
            iconNames: AppIconRotator.weeklyIconNames,
            calendar: calendar
        )

        XCTAssertEqual(first, second)
    }

    func testSelectsNextIconWhenISOWeekChanges() throws {
        let calendar = Calendar(identifier: .iso8601)
        let weekOne = try XCTUnwrap(date(year: 2026, month: 4, day: 20))
        let weekTwo = try XCTUnwrap(date(year: 2026, month: 4, day: 27))

        let first = AppIconRotator.weeklyIconName(
            for: weekOne,
            iconNames: AppIconRotator.weeklyIconNames,
            calendar: calendar
        )
        let second = AppIconRotator.weeklyIconName(
            for: weekTwo,
            iconNames: AppIconRotator.weeklyIconNames,
            calendar: calendar
        )

        XCTAssertNotEqual(first, second)
    }

    func testReturnsNilWhenNoAlternateIconsAreAvailable() throws {
        let date = try XCTUnwrap(date(year: 2026, month: 4, day: 20))

        let iconName = AppIconRotator.weeklyIconName(
            for: date,
            iconNames: [],
            calendar: Calendar(identifier: .iso8601)
        )

        XCTAssertNil(iconName)
    }

    func testDetectsXCTestEnvironmentForAutomaticRotationGuard() {
        XCTAssertTrue(
            AppIconRotator.isRunningUnderXCTest(
                environment: ["XCTestConfigurationFilePath": "/tmp/FlowTests.xctestconfiguration"]
            )
        )
        XCTAssertFalse(AppIconRotator.isRunningUnderXCTest(environment: [:]))
    }

    func testDoesNotRotateAgainInsideAlreadyAppliedWeek() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let date = try XCTUnwrap(date(year: 2026, month: 4, day: 20))
        var appliedNames: [String?] = []
        let rotator = AppIconRotator(
            defaults: defaults,
            iconNames: AppIconRotator.weeklyIconNames,
            dateProvider: { date },
            currentIconNameProvider: { appliedNames.last ?? nil },
            setIconName: { iconName in
                appliedNames.append(iconName)
            }
        )

        rotator.rotateIfNeeded()
        rotator.rotateIfNeeded()

        XCTAssertEqual(appliedNames.count, 1)
    }

    private func date(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }
}
