import Foundation
import Testing
@testable import Hush

@Suite("Activity days across time zones")
struct ActivityDayTests {

    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test("A day key round-trips and rejects anything that is not a date")
    func keys() {
        let day = CivilDay(Self.instant("2026-11-16T15:00:00Z"), calendar: Self.calendar("Europe/Berlin"))
        #expect(day.key == "2026-11-16")
        #expect(CivilDay(key: day.key) == day)
        for invalid in ["", "2026-11", "2026-13-01", "2026-11-32", "abcd-ef-gh"] {
            #expect(CivilDay(key: invalid) == nil)
        }
    }

    @Test("A dictation counts on the day it was where the user was")
    func dayFollowsTheZoneAtWriteTime() {
        let instant = Self.instant("2026-11-17T02:00:00Z")
        #expect(CivilDay(instant, calendar: Self.calendar("Europe/Berlin")).key == "2026-11-17")
        #expect(CivilDay(instant, calendar: Self.calendar("America/Argentina/Buenos_Aires")).key == "2026-11-16")
    }

    /// The crash of 2026-11-17: a day written under UTC+1 and a day written under UTC-3 fell
    /// on one local day after the time zone changed, and the chart's unique-key dictionary
    /// aborted the app when the dashboard opened.
    @Test("Days written in one time zone stay distinct when read in another")
    func timeZoneChangeKeepsDays() {
        let berlin = Self.calendar("Europe/Berlin")
        let buenosAires = Self.calendar("America/Argentina/Buenos_Aires")
        let writtenInBerlin = CivilDay(Self.instant("2026-11-16T23:30:00Z"), calendar: berlin)       // Nov 17 there
        let writtenInBuenosAires = CivilDay(Self.instant("2026-11-16T12:00:00Z"), calendar: buenosAires) // Nov 16 there
        #expect(writtenInBerlin.key == "2026-11-17")
        #expect(writtenInBuenosAires.key == "2026-11-16")

        let points = [
            DailyActivityPoint(date: writtenInBerlin.start(in: buenosAires), words: 40, dictations: 2),
            DailyActivityPoint(date: writtenInBuenosAires.start(in: buenosAires), words: 25, dictations: 1),
        ]
        let now = Self.instant("2026-11-17T16:00:00Z")
        let series = DailyActivityPoint.series(points, range: .sevenDays, now: now, calendar: buenosAires)
        #expect(series.count == 7)
        #expect(series.map { CivilDay($0.date, calendar: buenosAires).key }.suffix(2) == ["2026-11-16", "2026-11-17"])
        #expect(series.suffix(2).map(\.words) == [25, 40])
    }

    @Test("Two points on one day are added together instead of crashing")
    func pointsOnOneDayMerge() {
        let buenosAires = Self.calendar("America/Argentina/Buenos_Aires")
        // The exact stored instants that collided: Berlin midnight of Nov 17 and Buenos Aires midnight of Nov 16.
        let points = [
            DailyActivityPoint(date: Self.instant("2026-11-16T23:00:00Z"), words: 40, dictations: 2),
            DailyActivityPoint(date: Self.instant("2026-11-16T03:00:00Z"), words: 25, dictations: 1),
        ]
        let now = Self.instant("2026-11-17T16:00:00Z")
        for range in [ActivityRange.sevenDays, .thirtyDays, .allTime] {
            let series = DailyActivityPoint.series(points, range: range, now: now, calendar: buenosAires)
            #expect(series.map(\.words).reduce(0, +) == 65)
            #expect(series.map(\.dictations).reduce(0, +) == 3)
        }
    }

    @Test("Every day of the year has a start that maps back to it, also on daylight-saving days")
    func daylightSaving() {
        for zone in ["Europe/Berlin", "America/Santiago", "America/Sao_Paulo", "America/Argentina/Buenos_Aires", "Pacific/Kiritimati", "Asia/Kolkata"] {
            let calendar = Self.calendar(zone)
            var day = CivilDay(key: "2026-01-01")!
            for _ in 0..<366 {
                let start = day.start(in: calendar)
                #expect(CivilDay(start, calendar: calendar) == day, "\(zone) \(day.key)")
                day = CivilDay(calendar.date(byAdding: .day, value: 1, to: start.addingTimeInterval(12 * 3600))!, calendar: calendar)
            }
        }
    }
}
