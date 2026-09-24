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
                ForEach(ModeChoice.allCases) { Text($0.label).tag($0) }
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

            if !model.status.isEmpty {
                Text(model.status.split(separator: "\n").first.map(String.init) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Button("Open tint…") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
        .task { await model.start() }
    }
}
#endif
