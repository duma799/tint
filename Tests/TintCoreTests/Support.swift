import Foundation
@testable import TintCore

/// A fresh temporary folder, removed when the value goes away.
final class TempDir {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "tint-test-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: path) }

    func file(_ name: String) -> String { path + "/" + name }

    @discardableResult
    func write(_ name: String, _ content: String, executable: Bool = false) -> String {
        let p = file(name)
        try! FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! content.write(toFile: p, atomically: true, encoding: .utf8)
        if executable { try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p) }
        return p
    }

    func read(_ name: String) -> String { try! String(contentsOfFile: file(name), encoding: .utf8) }
}

let testScheme = try! SchemeBuilder.build(palette("#1b2233", "#48596f", "#c68a65", "#d8f4ff", "#6d9c5a", "#b8455a"), mode: .dark)
