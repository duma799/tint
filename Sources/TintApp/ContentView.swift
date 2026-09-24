#if os(macOS)
import AppKit
import SwiftUI
import TintCore
import UniformTypeIdentifiers

/// The one window: an image on the left; its palette, the scheme made from it,
/// a terminal preview and the knobs on the right. The whole window takes the
/// scheme's colours, so what you see is what you'll get.
struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        let scheme = model.scheme
        HStack(alignment: .top, spacing: 28) {
            imageSide
            ScrollView {
                controls(scheme)
                    .padding(.trailing, 12)
            }
            .scrollIndicators(.automatic)
            .frame(width: 440)
        }
        .padding(28)
        .frame(minWidth: 920, minHeight: 640)
        .background(scheme.map { Color($0.background) } ?? Color(nsColor: .windowBackgroundColor), ignoresSafeAreaEdges: .all)
        .foregroundStyle(scheme.map { Color($0.foreground) } ?? Color.primary)
        .tint(scheme.map { Color($0[4]) } ?? Color.accentColor)
        .preferredColorScheme(scheme?.mode == .light ? .light : .dark)
        .animation(.easeInOut(duration: 0.25), value: scheme)
        .fileImporter(isPresented: $model.importing, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                Task { await model.load(url.path) }
            }
        }
        .task { await model.start() }
    }

    // MARK: Left: the image

    private var imageSide: some View {
        VStack(spacing: 14) {
            Color.white.opacity(0.06)
                .overlay {
                    if let image = model.image {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        Text("Drop an image here, or open one below").opacity(0.55)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    Task { await model.load(url.path) }
                    return true
                }

            HStack(spacing: 8) {
                Button("Current wallpaper") { Task { await model.loadCurrentWallpaper() } }
                Button("Open image…") { model.importing = true }
                Text(model.imagePath ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(0.6)
                    .help(model.imagePath ?? "")
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Right: what the image becomes, and the knobs

    @ViewBuilder
    private func controls(_ scheme: Scheme?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("tint").font(.system(size: 30, weight: .bold))
                if let palette = model.palette, let scheme {
                    Text("\(palette.isDark ? "a dark" : "a light") image → \(scheme.mode.rawValue) scheme").opacity(0.6)
                }
            }

            if let palette = model.palette, let scheme {
                SectionLabel("Palette")
                PaletteStrip(palette: palette)

                SectionLabel("Scheme — click a colour to copy it")
                SchemeGrid(scheme: scheme) { model.copy($0, index: $1) }

                SectionLabel("Preview")
                TerminalPreview(scheme: scheme)
            }

            SectionLabel("Mode")
            Picker("Mode", selection: $model.mode) {
                ForEach(ModeChoice.allCases) { Text($0 == .auto ? "Auto (from the image)" : $0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                SectionLabel("Saturation")
                Spacer()
                Text(String(format: "%.2f×", model.roundedSaturation)).font(.system(size: 12)).opacity(0.7)
            }
            Slider(value: $model.saturation, in: 0.5...1.5, step: 0.05)

            Toggle("Also set it as the desktop wallpaper", isOn: $model.setAsWallpaper)
                .disabled(!model.canSetWallpaper)

            Button { Task { await model.apply() } } label: {
                Text(model.busy ? "Applying…" : "Apply").frame(maxWidth: .infinity)
            }
            .buttonStyle(SchemeButtonStyle(scheme: scheme))
            .disabled(scheme == nil || model.busy)
            .keyboardShortcut(.return, modifiers: .command)

            Text("Apply also saves the mode and saturation for `tint apply` and the login service.")
                .font(.system(size: 11)).opacity(0.5)

            ServiceRow(model: model)

            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.2)
            .opacity(0.6)
            .padding(.top, 6)
    }
}

/// One bar per colour, as wide as its share of the image.
struct PaletteStrip: View {
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(Array(palette.swatches.sorted { $0.lab.l < $1.lab.l }.enumerated()), id: \.offset) { _, swatch in
                    Rectangle()
                        .fill(Color(swatch.color))
                        .frame(width: geometry.size.width * swatch.share)
                        .help("\(swatch.color.hex) · \(Int((swatch.share * 100).rounded()))% of the image")
                }
            }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            // Dark images' darkest colour is close to the background: outline the strip.
            RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 1)
        }
    }
}

/// The 16 terminal colours, with their hex codes.
struct SchemeGrid: View {
    let scheme: Scheme
    let copy: (Rgb, Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 8) {
            ForEach(0..<16, id: \.self) { i in
                VStack(spacing: 3) {
                    Button { copy(scheme[i], i) } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(scheme[i]))
                            .frame(height: 30)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(Color(scheme[8]), lineWidth: i == 0 ? 1 : 0)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("color\(i) \(scheme[i].hex)")

                    Text(scheme[i].strip).font(.system(size: 10, design: .monospaced)).opacity(0.6)
                }
            }
        }
    }
}

/// A few lines of a pretend terminal session, coloured the way a shell and git would colour them.
struct TerminalPreview: View {
    let scheme: Scheme

    var body: some View {
        Text(session)
            .font(.system(size: 12.5, design: .monospaced))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(scheme.background), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(scheme[8]), lineWidth: 1)
            }
    }

    private var session: AttributedString {
        var text = AttributedString()
        func add(_ s: String, _ color: Int? = nil, bold: Bool = false) {
            var run = AttributedString(s)
            run.foregroundColor = Color(color.map { scheme[$0] } ?? scheme.foreground)
            if bold { run.font = .system(size: 12.5, weight: .bold, design: .monospaced) }
            text += run
        }
        func prompt(_ command: String) {
            add("~/tint", 6)
            add(" main", 5)
            add(" ❯ ", 2)
            add(command + "\n")
        }

        prompt("ls")
        add("Sources", 4, bold: true); add("  "); add("Tests", 4, bold: true); add("  ")
        add("package.sh", 2, bold: true); add("  README.md  "); add("wall.heic\n", 5)
        prompt("git status --short")
        add(" M", 1); add(" Sources/TintCore/SchemeBuilder.swift\n")
        add("A ", 2); add(" Sources/TintApp/ContentView.swift\n")
        prompt("swift test")
        add("warning:", 3, bold: true); add(" 'foregroundColor' is deprecated\n")
        add("error:", 1, bold: true); add(" expected '}'\n")
        add("✔ Test run passed", 2, bold: true); add("  "); add("# all readable", 8)
        return text
    }
}

/// Apply, in the scheme's blue with its background as the text colour — always readable.
struct SchemeButtonStyle: ButtonStyle {
    let scheme: Scheme?
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.vertical, 10)
            .foregroundStyle(scheme.map { Color($0.background) } ?? Color.white)
            .background(
                scheme.map { Color($0[4]) } ?? Color.accentColor,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Whether the login service is on, and a button to turn it on.
struct ServiceRow: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.service?.running == true ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(model.service?.running == true ? "Re-theming on every wallpaper change" : "Not watching wallpaper changes")
                .font(.system(size: 12))
                .opacity(0.8)
            Spacer()
            if model.service?.running != true, model.cli != nil {
                Button("Turn on") { Task { await model.installService() } }
                    .controlSize(.small)
            }
        }
        .padding(.top, 6)
    }
}

extension Color {
    init(_ c: Rgb) {
        self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1)
    }
}
#endif
