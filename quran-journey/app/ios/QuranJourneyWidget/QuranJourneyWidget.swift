import SwiftUI
import WidgetKit

// MARK: - Timeline

struct QJEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct QJProvider: TimelineProvider {
    func placeholder(in context: Context) -> QJEntry {
        QJEntry(date: Date(), data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (QJEntry) -> Void) {
        let d = WidgetData.load()
        completion(QJEntry(date: Date(), data: (context.isPreview && d.isEmpty) ? .sample : d))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QJEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let data = WidgetData.load()
        var dates: [Date] = [now]
        // Refresh at each remaining session time today so "ready"/"next" stay accurate.
        let nowMinutes = TimeText.minutesSinceMidnight(now)
        for s in data.enabledSessions where s.minutes > nowMinutes {
            dates.append(TimeText.minutesToDate(s.minutes, on: now))
        }
        if let p = data.pausedUntil, p > now, cal.isDate(p, inSameDayAs: now) {
            dates.append(p)
        }
        // And just after midnight, when today's progress resets.
        let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        dates.append(midnight.addingTimeInterval(60))
        let entries = Array(Set(dates)).sorted().map { QJEntry(date: $0, data: data.normalized(for: $0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

extension WidgetData {
    static var sample: WidgetData {
        var d = WidgetData()
        d.arabic = "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ"
        d.translation = "Praise be to Allah, Lord of the Worlds,"
        d.translationName = "Pickthall"
        d.ref = "Al-Faatiha 1:2"
        d.studyTitle = "Al-Faatiha 1:1–4"
        d.progressPermille = 1
        d.progressLabel = "Beginning · Surah 1 of 114"
        d.todayDone = 1
        d.todayTotal = 3
        d.sessions = [
            SessionInfo(label: "Morning", minutes: 450, enabled: true, done: true),
            SessionInfo(label: "Afternoon", minutes: 810, enabled: true, done: false),
            SessionInfo(label: "Evening", minutes: 1170, enabled: true, done: false),
        ]
        d.updatedAt = Date()
        return d
    }
}

// MARK: - Palette

struct Palette {
    let background: Color
    let ink: Color
    let muted: Color
    let accent: Color
    let track: Color

    static func forScheme(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(background: Color(hex: 0x151216), ink: Color(hex: 0xEEE8EF),
                           muted: Color(hex: 0xEEE8EF).opacity(0.62), accent: Color(hex: 0xC9A9D1),
                           track: Color(hex: 0xEEE8EF).opacity(0.14))
        }
        return Palette(background: Color(hex: 0xFAF7F2), ink: Color(hex: 0x231F24),
                       muted: Color(hex: 0x231F24).opacity(0.6), accent: Color(hex: 0x5B3A63),
                       track: Color(hex: 0x231F24).opacity(0.1))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8) & 0xFF) / 255.0,
                  blue: Double(hex & 0xFF) / 255.0,
                  opacity: 1)
    }
}

// MARK: - Root view

struct QJWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var systemScheme
    let entry: QJEntry

    private var scheme: ColorScheme {
        switch entry.data.themePreference {
        case 0: return .light
        case 1: return .dark
        default: return systemScheme
        }
    }

    var body: some View {
        let p = Palette.forScheme(scheme)
        Group {
            switch family {
            case .accessoryInline:
                InlineAccessoryView(entry: entry)
            case .accessoryRectangular:
                RectangularAccessoryView(entry: entry)
            case .systemMedium:
                MediumView(entry: entry, p: p)
            case .systemLarge, .systemExtraLarge:
                LargeView(entry: entry, p: p)
            default:
                SmallView(entry: entry, p: p)
            }
        }
        .environment(\.colorScheme, scheme)
        .widgetURL(DeepLink.url(entry.data.studyLink))
        .containerBackground(for: .widget) {
            if family == .accessoryInline || family == .accessoryRectangular {
                Color.clear
            } else {
                p.background
            }
        }
    }
}

// MARK: - Building blocks

/// Arabic is shown only when it fits the widget comfortably. Long verses are
/// never cut mid-verse without an ellipsis: we omit them and point to the app.
struct ArabicVerse: View {
    let text: String
    let size: CGFloat
    let maxLines: Int
    let color: Color

    var body: some View {
        Text(text)
            .font(.custom(QJConfig.arabicFontName, size: size))
            .foregroundStyle(color)
            // Inside a right-to-left environment "leading" is the right edge.
            .multilineTextAlignment(.leading)
            .lineLimit(maxLines)
            .truncationMode(.tail)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.layoutDirection, .rightToLeft)
            .lineSpacing(2)
    }
}

struct ProgressLine: View {
    let permille: Int
    let p: Palette
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.track)
                Capsule().fill(p.accent)
                    .frame(width: max(height, geo.size.width * CGFloat(permille) / 1000.0))
            }
        }
        .frame(height: height)
        .accessibilityLabel(Text(String(format: "Journey progress %.1f percent", Double(permille) / 10.0)))
    }
}

struct TodayDots: View {
    let done: Int
    let total: Int
    let p: Palette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle()
                    .fill(i < done ? p.accent : Color.clear)
                    .overlay(Circle().stroke(p.accent.opacity(i < done ? 1 : 0.5), lineWidth: 1.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityLabel("\(done) of \(total) studies today")
    }
}

struct EmptyStateView: View {
    let brand: String
    let p: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(brand)
                .font(.system(.footnote, design: .serif).weight(.semibold))
                .foregroundStyle(p.accent)
            Spacer(minLength: 0)
            Text("Open to begin your journey")
                .font(.system(.subheadline))
                .foregroundStyle(p.ink)
            Text("3 verses. 3 moments. Every day.")
                .font(.caption2)
                .foregroundStyle(p.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Arabic thresholds (characters) per family.
private func arabicFits(_ s: String, limit: Int) -> Bool { !s.isEmpty && s.count <= limit }

// MARK: - Small

struct SmallView: View {
    let entry: QJEntry
    let p: Palette

    var body: some View {
        let d = entry.data
        if d.isEmpty {
            EmptyStateView(brand: d.brand, p: p)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if arabicFits(d.arabic, limit: 70) {
                    ArabicVerse(text: d.arabic, size: 17, maxLines: 2, color: p.ink)
                }
                Text(d.translation)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(p.ink)
                    .lineLimit(arabicFits(d.arabic, limit: 70) ? 3 : 5)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(d.ref)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(p.accent)
                    .lineLimit(1)
                ProgressLine(permille: d.progressPermille, p: p, height: 2)
            }
        }
    }
}

// MARK: - Medium

struct MediumView: View {
    let entry: QJEntry
    let p: Palette

    var body: some View {
        let d = entry.data
        if d.isEmpty {
            EmptyStateView(brand: d.brand, p: p)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(d.studyTitle.isEmpty ? d.ref : d.studyTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(p.accent)
                        .lineLimit(1)
                    Spacer()
                    if d.todayTotal > 0 {
                        TodayDots(done: d.todayDone, total: d.todayTotal, p: p)
                    }
                }
                if arabicFits(d.arabic, limit: 130) {
                    ArabicVerse(text: d.arabic, size: 18, maxLines: 2, color: p.ink)
                }
                Text(d.translation)
                    .font(.system(size: 12.5, design: .serif))
                    .foregroundStyle(p.ink)
                    .lineLimit(arabicFits(d.arabic, limit: 130) ? 2 : 4)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                HStack {
                    Text(d.ref + (d.translationName.isEmpty ? "" : " · \(d.translationName)"))
                        .font(.system(size: 10))
                        .foregroundStyle(p.muted)
                        .lineLimit(1)
                    Spacer()
                    Text(NextSessionState.compute(d, at: entry.date).text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(p.accent)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Large

struct LargeView: View {
    let entry: QJEntry
    let p: Palette

    var body: some View {
        let d = entry.data
        if d.isEmpty {
            EmptyStateView(brand: d.brand, p: p)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(d.brand)
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(p.accent)
                    Spacer()
                    Text(NextSessionState.compute(d, at: entry.date).text)
                        .font(.system(size: 11))
                        .foregroundStyle(p.muted)
                        .lineLimit(1)
                }
                Text(d.studyTitle)
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 6) {
                    if arabicFits(d.arabic, limit: 260) {
                        ArabicVerse(text: d.arabic, size: 21, maxLines: 4, color: p.ink)
                    }
                    Text(d.translation)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundStyle(p.ink)
                        .lineLimit(arabicFits(d.arabic, limit: 260) ? 4 : 7)
                        .truncationMode(.tail)
                    Text(d.ref + (d.translationName.isEmpty ? "" : " · \(d.translationName)"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(p.muted)
                }

                Spacer(minLength: 0)

                if !d.enabledSessions.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(d.enabledSessions, id: \.self) { s in
                            Link(destination: DeepLink.next) {
                                HStack(spacing: 8) {
                                    Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(s.done ? p.accent : p.muted)
                                    Text(s.label)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(p.ink)
                                    Spacer()
                                    Text(TimeText.format(s.minutes, on: entry.date))
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(p.muted)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ProgressLine(permille: d.progressPermille, p: p)
                    HStack {
                        Text(d.progressLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(p.muted)
                            .lineLimit(1)
                        Spacer()
                        Link(destination: DeepLink.url(d.studyLink)) {
                            Text("Continue")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(p.accent)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lock screen

struct RectangularAccessoryView: View {
    let entry: QJEntry

    var body: some View {
        let d = entry.data
        VStack(alignment: .leading, spacing: 1) {
            Text(d.isEmpty ? d.brand : (d.studyTitle.isEmpty ? d.ref : d.studyTitle))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if d.isEmpty {
                Text("Open to begin").font(.system(size: 12)).lineLimit(1)
            } else {
                Text(d.translation)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .widgetAccentable()
    }
}

struct InlineAccessoryView: View {
    let entry: QJEntry

    var body: some View {
        let d = entry.data
        if d.isEmpty {
            Text(d.brand)
        } else {
            Text("\(Image(systemName: "book.closed")) \(NextSessionState.compute(d, at: entry.date).text)")
        }
    }
}

// MARK: - Widget

struct QuranJourneyWidget: Widget {
    let kind: String = QJConfig.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QJProvider()) { entry in
            QJWidgetView(entry: entry)
        }
        .configurationDisplayName("The Quran Journey")
        .description("Your current verses, today's studies and your journey through the Quran.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}

@main
struct QuranJourneyWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuranJourneyWidget()
    }
}

#Preview(as: .systemMedium) {
    QuranJourneyWidget()
} timeline: {
    QJEntry(date: .now, data: .sample)
}
