// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "afterword-capture",
    // Core Audio process taps (system audio capture without screen recording) need macOS 14.4.
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "afterword-capture",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
