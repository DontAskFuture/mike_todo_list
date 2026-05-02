import Foundation

/// Parses informal English date/time cues from title + notes (e.g. "tomorrow 3 pm", "next week", "today").
enum ReminderPhraseParser {
    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )
    private static let relativeIntervalPatterns: [(NSRegularExpression, Calendar.Component)] = [
        (try! NSRegularExpression(pattern: #"\bin\s+(\d+)\s+minutes?\b"#, options: .caseInsensitive), .minute),
        (try! NSRegularExpression(pattern: #"\bin\s+(\d+)\s+hours?\b"#, options: .caseInsensitive), .hour),
        (try! NSRegularExpression(pattern: #"\bin\s+(\d+)\s+days?\b"#, options: .caseInsensitive), .day),
    ]
    private static let weekdayRegex = try! NSRegularExpression(
        pattern: #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
        options: .caseInsensitive
    )
    private static let clockWithMinutesRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2}):(\d{2})\s*(am|pm|a\.m\.|p\.m\.)?\b"#
    )
    private static let clockWithMeridiemRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(\d{1,2})\s*(am|pm|a\.m\.|p\.m\.)\b"#
    )

    private static func normalizedCombined(title: String, notes: String) -> String {
        [title, notes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Recurrence cue from phrases like "every week", "daily", "monthly" (leftmost match wins).
    static func suggestedRecurrence(title: String, notes: String) -> Recurrence? {
        let combined = normalizedCombined(title: title, notes: notes)
        guard !combined.isEmpty else { return nil }
        let lowered = combined.lowercased()

        let phrases: [(String, Recurrence)] = [
            ("every weekday", .daily),
            ("every seven days", .weekly),
            ("once a week", .weekly),
            ("every week", .weekly),
            ("each week", .weekly),
            ("per week", .weekly),
            ("weekly", .weekly),
            ("every 30 days", .monthly),
            ("every month", .monthly),
            ("each month", .monthly),
            ("monthly", .monthly),
            ("every morning", .daily),
            ("every evening", .daily),
            ("every night", .daily),
            ("every day", .daily),
            ("each day", .daily),
            ("daily", .daily),
        ]

        var bestPos = Int.max
        var bestLen = -1
        var picked: Recurrence?

        for (phrase, value) in phrases {
            guard let range = lowered.range(of: phrase) else { continue }
            let pos = lowered.distance(from: lowered.startIndex, to: range.lowerBound)
            let len = phrase.count
            if pos < bestPos || (pos == bestPos && len > bestLen) {
                bestPos = pos
                bestLen = len
                picked = value
            }
        }

        return picked
    }

    /// Returns a suggested reminder instant when title + notes contain a recognizable cue.
    /// Uses the earliest cue in the combined text when multiple exist.
    static func suggestedReminderDate(
        title: String,
        notes: String,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let combined = normalizedCombined(title: title, notes: notes)
        guard !combined.isEmpty else { return nil }

        var bestPosition = Int.max
        var bestDate: Date?

        func consider(position: Int, date: Date?) {
            guard let date, position < bestPosition else { return }
            bestPosition = position
            bestDate = date
        }

        if let (pos, date) = leftmostDataDetectorMatch(combined) {
            consider(position: pos, date: date)
        }

        if let (pos, date) = leftmostRelativeInterval(combined, reference: reference, calendar: calendar) {
            consider(position: pos, date: date)
        }

        if let (pos, date) = leftmostPhraseAnchor(combined, reference: reference, calendar: calendar) {
            consider(position: pos, date: date)
        }

        if let (pos, date) = leftmostWeekday(combined, reference: reference, calendar: calendar) {
            consider(position: pos, date: date)
        }

        guard let picked = bestDate else { return nil }
        return ensureNonPastReminder(picked, reference: reference, calendar: calendar)
    }

    // MARK: - NSDataDetector

    private static func leftmostDataDetectorMatch(_ text: String) -> (Int, Date)? {
        guard let detector = dateDetector else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var bestLoc = Int.max
        var bestDate: Date?

        detector.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match, match.resultType.contains(.date), let date = match.date else { return }
            let loc = match.range.location
            guard loc < bestLoc else { return }
            bestLoc = loc
            bestDate = date
        }

        guard let d = bestDate else { return nil }
        return (bestLoc, d)
    }

    // MARK: - "in 20 minutes" / hours / days

    private static func leftmostRelativeInterval(
        _ text: String,
        reference: Date,
        calendar: Calendar
    ) -> (Int, Date)? {
        let lowered = text.lowercased()
        let ns = lowered as NSString
        let full = NSRange(location: 0, length: ns.length)

        var bestLoc = Int.max
        var bestDate: Date?

        for (rx, component) in relativeIntervalPatterns {
            rx.enumerateMatches(in: lowered, options: [], range: full) { match, _, _ in
                guard let match, match.numberOfRanges >= 2,
                      let n = Int(ns.substring(with: match.range(at: 1))),
                      n > 0,
                      let date = calendar.date(byAdding: component, value: n, to: reference)
                else { return }
                let loc = match.range.location
                guard loc < bestLoc else { return }
                bestLoc = loc
                bestDate = date
            }
        }

        guard let d = bestDate else { return nil }
        return (bestLoc, d)
    }

    // MARK: - today / tomorrow / next week / …

    private static func leftmostPhraseAnchor(
        _ text: String,
        reference: Date,
        calendar: Calendar
    ) -> (Int, Date)? {
        let lowered = text.lowercased()
        /// Order: longest phrases first so "next month" beats "next".
        let anchors: [(phrase: String, dayStart: Date, defaultHour: Int)] = [
            ("next month", calendar.date(byAdding: .month, value: 1, to: calendar.startOfDay(for: reference))!, 9),
            ("next week", calendar.date(byAdding: .weekOfYear, value: 1, to: calendar.startOfDay(for: reference))!, 9),
            ("tomorrow", calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: reference))!, 9),
            ("tonight", calendar.startOfDay(for: reference), 21),
            ("today", calendar.startOfDay(for: reference), 9),
        ]

        var bestIdx = Int.max
        var dayStart = calendar.startOfDay(for: reference)
        var defaultHour = 9

        for (phrase, day, dh) in anchors {
            guard let r = lowered.range(of: phrase) else { continue }
            let idx = lowered.distance(from: lowered.startIndex, to: r.lowerBound)
            guard idx < bestIdx else { continue }
            bestIdx = idx
            dayStart = day
            defaultHour = dh
        }

        guard bestIdx != Int.max else { return nil }

        let clock = extractFirstClockTime(from: text) ?? (hour: defaultHour, minute: 0)
        let merged = merge(dayStart: dayStart, hour: clock.hour, minute: clock.minute, calendar: calendar)
        return (bestIdx, merged)
    }

    // MARK: - Weekday names

    private static let weekdayIndex: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
        "thursday": 5, "friday": 6, "saturday": 7,
    ]

    private static func leftmostWeekday(
        _ text: String,
        reference: Date,
        calendar: Calendar
    ) -> (Int, Date)? {
        let lowered = text.lowercased()
        let ns = lowered as NSString

        guard let match = weekdayRegex.firstMatch(in: lowered, range: NSRange(location: 0, length: ns.length)),
              let wordRange = Range(match.range(at: 1), in: lowered),
              let weekday = weekdayIndex[String(lowered[wordRange]).lowercased()]
        else {
            return nil
        }

        let idx = match.range.location

        var parts = DateComponents()
        parts.weekday = weekday
        parts.hour = 0
        parts.minute = 0
        parts.second = 0

        guard let anchorMidnight = calendar.nextDate(
            after: reference.addingTimeInterval(-1),
            matching: parts,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) else {
            return nil
        }

        let dayStart = calendar.startOfDay(for: anchorMidnight)
        let clock = extractFirstClockTime(from: text) ?? (hour: 9, minute: 0)
        let merged = merge(dayStart: dayStart, hour: clock.hour, minute: clock.minute, calendar: calendar)
        return (idx, merged)
    }

    // MARK: - Clock parsing

    /// First explicit clock reading in `text` (prefers tokens with am/pm).
    private static func extractFirstClockTime(from text: String) -> (hour: Int, minute: Int)? {
        let ns = text as NSString
        let len = ns.length
        let full = NSRange(location: 0, length: len)

        struct Hit { let loc: Int; let hour: Int; let minute: Int }
        var hits: [Hit] = []

        // H:MM with optional am/pm
        clockWithMinutesRegex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m, m.numberOfRanges >= 3,
                  let h12 = Int(ns.substring(with: m.range(at: 1))),
                  let minute = Int(ns.substring(with: m.range(at: 2))),
                  minute <= 59
            else { return }

            let merRaw = m.range(at: 3).location != NSNotFound
                ? ns.substring(with: m.range(at: 3)).lowercased()
                : ""

            let hour24: Int
            if merRaw.isEmpty {
                // Treat as 24h only when clearly afternoon per clock face.
                guard h12 >= 13, h12 <= 23 else { return }
                hour24 = h12
            } else {
                hour24 = adjustTo24Hour(hour12: h12, meridiem: merRaw)
            }

            hits.append(Hit(loc: m.range.location, hour: hour24, minute: minute))
        }

        // H am/pm without minutes
        clockWithMeridiemRegex.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m, m.numberOfRanges >= 3,
                  let h12 = Int(ns.substring(with: m.range(at: 1))),
                  h12 >= 1, h12 <= 12
            else { return }
            let mer = ns.substring(with: m.range(at: 2)).lowercased()
            let hour24 = adjustTo24Hour(hour12: h12, meridiem: mer)
            hits.append(Hit(loc: m.range.location, hour: hour24, minute: 0))
        }

        guard let best = hits.min(by: { $0.loc < $1.loc }) else { return nil }
        guard best.hour >= 0, best.hour < 24 else { return nil }
        return (best.hour, best.minute)
    }

    private static func adjustTo24Hour(hour12: Int, meridiem: String) -> Int {
        var h = hour12
        if meridiem.hasPrefix("p"), h < 12 { h += 12 }
        if meridiem.hasPrefix("a"), h == 12 { h = 0 }
        return h
    }

    private static func merge(dayStart: Date, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var dc = calendar.dateComponents([.year, .month, .day], from: dayStart)
        dc.hour = hour
        dc.minute = minute
        dc.second = 0
        return calendar.date(from: dc) ?? dayStart
    }

    /// If the datetime is slightly before `reference`, advance by whole days until it's in the future.
    private static func ensureNonPastReminder(_ date: Date, reference: Date, calendar: Calendar) -> Date {
        let slack = reference.addingTimeInterval(-120)
        guard date <= slack else { return date }

        var shifted = date
        var guardrails = 0
        while shifted <= slack, guardrails < 400 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: shifted) else { break }
            shifted = next
            guardrails += 1
        }
        return shifted
    }
}
