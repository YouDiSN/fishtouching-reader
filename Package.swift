// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalLibrary",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LocalLibrary", targets: ["LocalLibrary"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.9.6")
    ],
    targets: [.executableTarget(name: "LocalLibrary", dependencies: ["SwiftSoup"],
                                linkerSettings: [.unsafeFlags(["/opt/homebrew/lib/libsodium.a"])])]
)
