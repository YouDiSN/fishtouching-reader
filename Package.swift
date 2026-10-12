// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalLibrary",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LocalLibrary", targets: ["LocalLibrary"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [.executableTarget(name: "LocalLibrary", dependencies: [.product(name: "Sparkle", package: "Sparkle")],
                                linkerSettings: [.unsafeFlags(["/opt/homebrew/lib/libsodium.a", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-rpath", "-Xlinker", "@executable_path"])])]
)
