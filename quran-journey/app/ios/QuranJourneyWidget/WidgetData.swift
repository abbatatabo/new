import Foundation

/// Shared configuration. Keep in sync with lib/config/brand.dart (`iosAppGroup`)
/// and docs/CONTRACTS.md section 4.
enum QJConfig {
    static let appGroup = "group.app.quranjourney.shared"
    static let widgetKind = "QuranJourneyWidget"
    static let defaultBrand = "The Quran Journey"
    static let arabicFontName = "Amiri Quran"
}

struct SessionInfo: Codable, Hashable {
    let label: String
    let minutes: Int
    let enabled: Bool
    let done: Bool
}

/// Snapshot of the data the Flutter app writes with `HomeWidget.saveWidgetData`.
struct WidgetData {
    var brand: String = QJConfig.defaultBrand
    var arabic: String = ""
    var translation: String = ""
    var translationName: String = ""
    var ref: String = ""
    var studyTitle: String = ""
    var studyLink: String = "quranjourney://next"
    var progressPermille: Int = 0
    var progressLabel: String = ""
    var todayDone: Int = 0
    var todayTotal: Int = 0
    var sessions: [SessionInfo] = []
    var pausedUntil: Date? = nil
    var updatedAt: Date? = nil
    /// -1 follow system, 0 light, 1 dark
    var themePreference: Int = -1

    /// True when the app has never written data (first install).
    var isEmpty: Bool { translation.isEmpty && studyTitle.isEmpty }

    static func load() -> WidgetData {
        var d = WidgetData()
        guard let ud = UserDefaults(suiteName: QJConfig.appGroup) else { return d }
        func str(_ k: String) -> String? {
            if let s = ud.string(forKey: k), !s.isEmpty { return s }
            return nil
        }
        func int(_ k: String) -> Int? {
            guard let v = ud.object(forKey: k) else { return nil }
            if let n = v as? NSNumber { return n.intValue }
            if let s = v as? String { return Int(s) }
            return nil
        }
        d.brand = str("qj_brand") ?? QJConfig.defaultBrand
        d.arabic = str("qj_arabic") ?? ""
        d.translation = str("qj_translation") ?? ""
        d.translationName = str("qj_translation_name") ?? ""
        d.ref = str("qj_ref") ?? ""
        d.studyTitle = str("qj_study_title") ?? ""
        d.studyLink = str("qj_study_link") ?? "quranjourney://next"
        d.progressPermille = max(0, min(1000, int("qj_progress_permille") ?? 0))
        d.progressLabel = str("qj_progress_label") ?? ""
        d.todayDone = max(0, int("qj_today_done") ?? 0)
        d.todayTotal = max(0, int("qj_today_total") ?? 0)
        if let json = str("qj_sessions"), let data = json.data(using: .utf8),
           let s = try? JSONDecoder().decode([SessionInfo].self, from: data) {
            d.sessions = s.sorted { $0.minutes < $1.minutes }
        }
        if let p = int("qj_paused_until"), p > 0 {
            d.pausedUntil = Date(timeIntervalSince1970: Double(p) / 1000.0)
        }
        if let u = int("qj_updated_at"), u > 0 {
            d.updatedAt = Date(timeIntervalSince1970: Double(u) / 1000.0)
        }
        d.themePreference = int("qj_dark") ?? -1
        return d
    }

    /// The app writes "done" flags for the day it last ran. If that was before
    /// today, nothing has been completed yet today.
    func normalized(for date: Date, calendar: Calendar = .current) -> WidgetData {
        var d = self
        if let u = updatedAt, !calendar.isDate(u, inSameDayAs: date) {
            d.todayDone = 0
            d.sessions = sessions.map {
                SessionInfo(label: $0.label, minutes: $0.minutes, enabled: $0.enabled, done: false)
            }
        }
        return d
    }

    var enabledSessions: [SessionInfo] { sessions.filter { $0.enabled } }

    func isPaused(at date: Date) -> Bool {
        if let p = pausedUntil { return p > date }
        return false
    }
}

/// Deep links: home_widget only reports a click to Dart when the URL carries a
/// `homeWidget` query item, so every widget URL gets one.
enum DeepLink {
    static func url(_ raw: String) -> URL {
        let base = raw.isEmpty ? "quranjourney://next" : raw
        guard var c = URLComponents(string: base), c.scheme == "quranjourney" else {
            return URL(string: "quranjourney://next?homeWidget=1")!
        }
        var items = c.queryItems ?? []
        if !items.contains(where: { $0.name == "homeWidget" }) {
            items.append(URLQueryItem(name: "homeWidget", value: "1"))
        }
        c.queryItems = items
        return c.url ?? URL(string: "quranjourney://next?homeWidget=1")!
    }
    static let next = url("quranjourney://next")
    static let today = url("quranjourney://today")
}

enum TimeText {
    static func minutesToDate(_ minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    static func format(_ minutes: Int, on day: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: minutesToDate(minutes, on: day))
    }

    static func minutesSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// What the widget should say about the user's next session.
enum NextSessionState: Equatable {
    case noSchedule
    case paused
    case allDone
    case ready(label: String)              // a session time has passed and is not done
    case upcoming(label: String, time: String)

    static func compute(_ d: WidgetData, at date: Date) -> NextSessionState {
        let sessions = d.enabledSessions
        if sessions.isEmpty { return .noSchedule }
        if d.isPaused(at: date) { return .paused }
        let total = d.todayTotal > 0 ? d.todayTotal : sessions.count
        if d.todayDone >= total { return .allDone }
        let now = TimeText.minutesSinceMidnight(date)
        if let ready = sessions.first(where: { !$0.done && $0.minutes <= now }) {
            return .ready(label: ready.label)
        }
        if let next = sessions.first(where: { !$0.done && $0.minutes > now }) {
            return .upcoming(label: next.label, time: TimeText.format(next.minutes, on: date))
        }
        return .allDone
    }

    var text: String {
        switch self {
        case .noSchedule: return "Read at your own pace"
        case .paused: return "Reminders paused"
        case .allDone: return "Today's studies complete"
        case .ready(let label): return "\(label) study is ready"
        case .upcoming(let label, let time): return "Next · \(label) \(time)"
        }
    }
}
