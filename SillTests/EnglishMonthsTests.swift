import Foundation
import Testing

@testable import Sill

/// The list of months with their English names under the days of the calendar popup.
struct EnglishMonthsTests {
    @Test func listsTheMonthsInEnglishAndMarksTheCurrentOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = DateComponents(calendar: calendar, year: 2026, month: 10, day: 12).date!

        let months = englishMonths(of: today, in: calendar)
        #expect(months.map(\.symbol) == [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ])
        #expect(months.map(\.number) == Array(1...12))
        #expect(months.filter(\.isCurrent).map(\.number) == [10])
    }

    @Test func listsTheGregorianMonthsWithAnotherCalendar() {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let today = DateComponents(calendar: gregorian, year: 2026, month: 10, day: 12).date!
        var chinese = Calendar(identifier: .chinese)
        chinese.locale = Locale(identifier: "ja_JP")
        chinese.timeZone = gregorian.timeZone

        let months = englishMonths(of: today, in: chinese)
        #expect(months.map(\.symbol).first == "Jan")
        #expect(months.count == 12)
        #expect(months.filter(\.isCurrent).map(\.number) == [10])
    }
}
