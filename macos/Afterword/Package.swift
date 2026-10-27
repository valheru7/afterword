// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Afterword",
    // Matches afterword-capture: the recorder it drives needs macOS 14.4 for Core Audio process taps.
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "Afterword",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
