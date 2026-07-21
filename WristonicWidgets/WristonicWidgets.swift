import SwiftUI
import WidgetKit

// MARK: - Timeline (static launcher: one entry, never refresh)

struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

// MARK: - Views per accessory family

struct WristonicLauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCorner:
                Image(systemName: "music.note")
                    .font(.title.bold())
                    .widgetLabel("Wristonic")
            case .accessoryInline:
                Label("Wristonic", systemImage: "music.note")
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wristonic")
                            .font(.headline)
                        Text("Tap to play")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            default: // .accessoryCircular
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "music.note")
                        .font(.title2.bold())
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget + bundle

struct WristonicLauncherWidget: Widget {
    let kind = "WristonicLauncher"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LauncherProvider()) { _ in
            WristonicLauncherView()
        }
        .configurationDisplayName("Wristonic")
        .description("Launch Wristonic from the watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

@main
struct WristonicWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WristonicLauncherWidget()
    }
}
