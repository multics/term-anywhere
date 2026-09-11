// swift-tools-version: 6.0
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let ssl = root + "/.build/references/OpenSSL/Frameworks/OpenSSL.xcframework/macos-arm64_x86_64"
let package = Package(
    name: "TermAnywhere",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "TermCore", targets: ["TermCore"]), .executable(name: "connection-check", targets: ["ConnectionCheck"])],
    targets: [
        .target(name: "CSSH", cSettings: [.unsafeFlags(["-I", root + "/.build/native/include"])], linkerSettings: [.unsafeFlags([root + "/.build/native/macos/src/libssh2.a", "-F", ssl, "-Xlinker", "-rpath", "-Xlinker", ssl]), .linkedFramework("OpenSSL"), .linkedLibrary("z")]),
        .target(name: "TermCore", dependencies: ["CSSH"]),
        .executableTarget(name: "ConnectionCheck", dependencies: ["TermCore"]),
        .testTarget(name: "TermCoreTests", dependencies: ["TermCore"])
    ], swiftLanguageModes: [.v5]
)
