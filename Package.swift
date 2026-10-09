// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalLibrary",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LocalLibrary", targets: ["LocalLibrary"])],
    dependencies: [],
    targets: [.executableTarget(name: "LocalLibrary", dependencies: [],
                                linkerSettings: [.unsafeFlags(["/opt/homebrew/lib/libsodium.a"])])]
)
