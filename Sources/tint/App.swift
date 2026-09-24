import ArgumentParser
import Foundation
import TintCore

/// `tint app` — open the desktop app.
struct App: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open the tint app: pick an image, preview, tweak, apply.")

    func run() throws {
        guard let app = App.find() else {
            Terminal.error("couldn't find Tint.app. Install it: brew install --cask duma799/tint/tint-app")
            throw ExitCode.failure
        }
        let result = try ProcessRunner.run("open", [app])
        if !result.succeeded {
            Terminal.error("open failed: \(result.stderr)")
            throw ExitCode.failure
        }
    }

    /// In Applications, or next to this tint (a build folder).
    static func find() -> String? {
        var candidates = ["/Applications/Tint.app", TintPaths.home + "/Applications/Tint.app"]
        if let me = Bundle.main.executablePath {
            let dir = (TintPaths.realPath(me) as NSString).deletingLastPathComponent
            candidates += [dir + "/Tint.app", dir + "/../Tint.app"]
        }
        return candidates.first(where: TintPaths.isDirectory)
    }
}
