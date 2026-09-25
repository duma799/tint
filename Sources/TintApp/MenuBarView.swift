#if os(macOS)
import AppKit
import SwiftUI
import TintCore

/// The menu bar popover: the scheme at a glance, the mode, and one-click re-theming.
struct MenuBarView: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("tint").font(.headline)
                Spacer()
                Text(model.service?.running == true ? "watching" : "not watching")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let scheme = model.scheme {
                HStack(spacing: 2) {
                    ForEach(0..<16, id: \.self) { i in
                        Rectangle().fill(Color(scheme[i])).frame(height: 18)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Picker("Mode", selection: $model.mode) {
                ForEach(ModePreference.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                Task { await model.applyCurrentWallpaper() }
            } label: {
                Label(model.busy ? "Applying…" : "Theme from the wallpaper", systemImage: "paintbrush")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.busy)

            HStack {
                Button {
                    Task { await model.back() }
                } label: {
                    Label("Back", systemImage: "arrow.uturn.backward")
                }
                .disabled(model.busy || model.history.count < 2)
                .help("Bring back the previous theme")

                Spacer()

                Toggle("Pause", isOn: Binding(get: { model.paused }, set: { model.setPaused($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Leave wallpaper changes alone for now")
            }

            if model.history.count > 1 {
                Text("RECENT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(model.history.dropFirst().prefix(5).enumerated()), id: \.offset) { _, entry in
                    Button {
                        Task { await model.restore(entry) }
                    } label: {
                        HStack(spacing: 8) {
                            HStack(spacing: 0) {
                                ForEach(Array(entry.colors.prefix(8).enumerated()), id: \.offset) { _, hex in
                                    Rectangle().fill(Rgb(hex: hex).map(Color.init) ?? .clear)
                                }
                            }
                            .frame(width: 64, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            Text((entry.wallpaper as NSString).lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                            Spacer(minLength: 0)
                            Text(entry.mode.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            }

            if !model.status.isEmpty {
                Text(model.status.split(separator: "\n").first.map(String.init) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Toggle("Open at login", isOn: Binding(
                get: { model.openAtLogin },
                set: { model.setOpenAtLogin($0) }))
                .font(.caption)

            Divider()

            HStack {
                Button("Open tint…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Log") { model.openLog() }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .task { await model.start() }
        .onAppear { model.refreshHistory() }
    }
}
#endif
