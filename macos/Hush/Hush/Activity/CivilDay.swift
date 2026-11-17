import Foundation

/// A calendar day as the user lived it ("2026-11-16"), independent of time zones, the way
/// HealthKit identifies activity summaries by date components rather than by an instant.
/// Daily summaries are stored under its key; grouping, ranges and charts compute the day's
/// start in the time zone in effect when they read it, so changing time zones or a
/// daylight-saving switch never moves a stored day or merges two of them.
struct CivilDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// The day `date` falls on in `calendar`. The default follows time zone changes while
    /// the app runs; `Calendar.current` keeps the zone it had when first read.
    init(_ date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 1970
        month = components.month ?? 1
        day = components.day ?? 1
    }

    /// Parses a stored key ("2026-11-16").
    init?(key: String) {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midnight of this day in `calendar`'s time zone. Built from noon, which every day
    /// has, so a zone whose clocks skip midnight still yields the day's first instant.
    func start(in calendar: Calendar = .autoupdatingCurrent) -> Date {
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        return calendar.startOfDay(for: noon)
    }

    static func < (lhs: CivilDay, rhs: CivilDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
