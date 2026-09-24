import Testing
@testable import TintCore

func palette(_ hexes: String...) -> Palette {
    Palette(swatches: hexes.map { Swatch(color: Rgb(hex: $0)!, share: 1 / Double(hexes.count)) })
}

struct SchemeTests {
    /// A wallpaper-like palette: dark blues and greys with a few accents.
    static let night = palette("#1b2233", "#2a3450", "#48596f", "#606b7e", "#8f8e9a", "#c68a65", "#d8f4ff", "#6d9c5a", "#b8455a", "#c9b46a")

    @Test(arguments: ThemeMode.allCases)
    func hasPywalsShape(mode: ThemeMode) throws {
        let s = try SchemeBuilder.build(Self.night, mode: mode)
        #expect(s.colors.count == 16)
        #expect(s[0] == s.background)
        #expect(s[15] == s.foreground)
        #expect(s.cursor == s.foreground)
        #expect(s.mode == mode)
    }

    @Test(arguments: ThemeMode.allCases)
    func everyColourIsReadable(mode: ThemeMode) throws {
        let s = try SchemeBuilder.build(Self.night, mode: mode)
        #expect(Contrast.ratio(s.foreground, s.background) >= Contrast.enhanced)
        for i in [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14] {
            #expect(Contrast.ratio(s[i], s.background) >= Contrast.text, "color\(i)")
        }
        #expect(Contrast.ratio(s[8], s.background) >= Contrast.large)
    }

    @Test func darkSchemeIsDarkAndLightIsLight() throws {
        #expect(try SchemeBuilder.build(Self.night, mode: .dark).background.lab.l < 20)
        #expect(try SchemeBuilder.build(Self.night, mode: .light).background.lab.l > 90)
    }

    @Test func accentsLandInTheirHueSlots() throws {
        let s = try SchemeBuilder.build(Self.night, mode: .dark)
        // The image's red (#b8455a) is the red slot, its green (#6d9c5a) the green one.
        #expect(abs(s[1].lab.hue - Rgb(hex: "#b8455a")!.lab.hue) < 8)
        #expect(abs(s[2].lab.hue - Rgb(hex: "#6d9c5a")!.lab.hue) < 8)
    }

    @Test func aWarmPhotoGetsABlueBlueNotABrownOne() throws {
        let warm = palette("#20150f", "#5a3a22", "#a06a3a", "#d9a066", "#f2dcc0", "#8a5a30")
        let blue = try SchemeBuilder.build(warm, mode: .dark)[4].lab.hue
        #expect(blue > 230 && blue < 330)
    }

    @Test(arguments: ThemeMode.allCases)
    func aGreyImageStillGetsSixDistinctAccents(mode: ThemeMode) throws {
        let s = try SchemeBuilder.build(palette("#808080"), mode: mode)
        #expect(Set(s.colors[1...6]).count == 6)
    }

    @Test func saturationScalesHowColourfulTheAccentsAre() throws {
        func chroma(_ s: Scheme) -> Double { s.colors[1...6].map(\.lab.chroma).reduce(0, +) / 6 }
        let muted = chroma(try SchemeBuilder.build(Self.night, mode: .dark, saturation: 0.5))
        let normal = chroma(try SchemeBuilder.build(Self.night, mode: .dark))
        let vivid = chroma(try SchemeBuilder.build(Self.night, mode: .dark, saturation: 1.5))
        #expect(muted < normal && normal < vivid)
        #expect(throws: SchemeBuilder.BuildError.self) { try SchemeBuilder.build(Self.night, mode: .dark, saturation: 3) }
        #expect(throws: SchemeBuilder.BuildError.self) { try SchemeBuilder.build(Self.night, mode: .dark, saturation: .nan) }
    }

    @Test func lightThemesKeepANavyBlueFromLookingBlack() throws {
        let s = try SchemeBuilder.build(palette("#10142e", "#1b2233", "#f4e9dc", "#2c255c"), mode: .light)
        #expect(s[4].lab.l >= 30)
    }
}
