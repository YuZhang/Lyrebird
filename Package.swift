// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicTrackRecorder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Lyrebird", targets: ["MusicTrackRecorder"])
    ],
    targets: [
        .executableTarget(
            name: "MusicTrackRecorder",
            path: "Sources/MusicTrackRecorder"
        ),
        .testTarget(
            name: "MusicTrackRecorderTests",
            dependencies: ["MusicTrackRecorder"],
            path: "Tests/MusicTrackRecorderTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
