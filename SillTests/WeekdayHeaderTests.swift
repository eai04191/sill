import Foundation
import Testing

@testable import Sill

/// The weekday header of the calendar popup, with and without the English names.
struct WeekdayHeaderTests {
    private func calendar(locale: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    @Test func showsEnglishUnderJapanese() {
        let headers = weekdayHeaders(in: calendar(locale: "ja_JP", firstWeekday: 1), showsEnglish: true)
        #expect(headers.map(\.symbol) == ["日", "月", "火", "水", "木", "金", "土"])
        #expect(headers.map(\.englishSymbol) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(headers.map(\.isWeekend) == [true, false, false, false, false, false, true])
    }

    @Test func followsFirstWeekday() {
        let headers = weekdayHeaders(in: calendar(locale: "ja_JP", firstWeekday: 2), showsEnglish: true)
        #expect(headers.first == WeekdayHeader(symbol: "月", englishSymbol: "Mon", isWeekend: false))
        #expect(headers.last == WeekdayHeader(symbol: "日", englishSymbol: "Sun", isWeekend: true))
    }

    @Test func leavesOutEnglishWhenOff() {
        let headers = weekdayHeaders(in: calendar(locale: "ja_JP", firstWeekday: 1), showsEnglish: false)
        #expect(headers.allSatisfy { $0.englishSymbol == nil })
    }

    @Test func leavesOutEnglishWhenTheSame() {
        let headers = weekdayHeaders(in: calendar(locale: "en_US", firstWeekday: 1), showsEnglish: true)
        #expect(headers.map(\.symbol) == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(headers.allSatisfy { $0.englishSymbol == nil })
    }
}
