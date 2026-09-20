// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BabjiFlow",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Vendored FluidAudio (Parakeet ASR, diarization, VAD as CoreML).
        // NemoTextProcessing trait disabled: we do not need TTS text normalisation.
        .package(path: "Vendor/FluidAudio"),
    ],
    targets: [
        .executableTarget(
            name: "BabjiFlow",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/BabjiFlow",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
