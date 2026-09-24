import Testing
@testable import TintCore

struct ColorTests {
    @Test(arguments: ["#000000", "#ffffff", "#1b2233", "#c68a65", "#6d9c5a", "#b8455a"])
    func labRoundTripsEveryColour(hex: String) {
        let rgb = Rgb(hex: hex)!
        #expect(rgb.lab.rgb == rgb)
    }

    @Test func hexParsesAndPrints() {
        #expect(Rgb(hex: "#1B2233")?.hex == "#1b2233")
        #expect(Rgb(hex: "1b2233")?.strip == "1b2233")
        #expect(Rgb(hex: "#12345") == nil)
        #expect(Rgb(hex: "#zzzzzz") == nil)
    }

    @Test func whiteAndBlackAreTheEndsOfTheScale() {
        let white = Rgb(255, 255, 255).lab, black = Rgb(0, 0, 0).lab
        #expect(abs(white.l - 100) < 0.01)
        #expect(abs(black.l) < 0.01)
        #expect(white.chroma < 0.01)
    }

    @Test func contrastMatchesWcag() {
        #expect(abs(Contrast.ratio(Rgb(0, 0, 0), Rgb(255, 255, 255)) - 21) < 0.01)
        #expect(abs(Contrast.ratio(Rgb(119, 119, 119), Rgb(255, 255, 255)) - 4.48) < 0.01)
    }

    @Test func hueIsInRangeAndLchRoundTrips() {
        let lab = Lab.lch(l: 60, chroma: 40, hue: 280)
        #expect(abs(lab.hue - 280) < 0.001)
        #expect(abs(lab.chroma - 40) < 0.001)
        #expect(lab.withMaxChroma(10).chroma <= 10.0001)
    }
}
