// swift-tools-version: 6.0
import PackageDescription
import Foundation

let package = Package(
    name: "FluidAudio",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "FluidAudio",
            targets: ["FluidAudio"]
        ),
        .executable(
            name: "fluidaudiocli",
            targets: ["FluidAudioCLI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FluidAudio",
            dependencies: [
                "FastClusterWrapper",
                "MachTaskSelfWrapper",
                "NemoTextProcessing",
            ],
            path: "Sources/FluidAudio",
            exclude: ["ASR/Parakeet/Unified/benchmark.md"],
            resources: [
                // Keep .process: .copy of a Resources-named directory breaks Apple code signing on iOS.
                .process("TTS/LuxTts/G2p/Resources")
            ]
        ),
        // Vendored NeMo inverse-text-normalisation engine (was a remote binaryTarget).
        .binaryTarget(
            name: "NemoTextProcessing",
            path: "../NemoTextProcessing/NemoTextProcessing.xcframework"
        ),
        .target(
            name: "FastClusterWrapper",
            path: "Sources/FastClusterWrapper",
            publicHeadersPath: "include"
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "FluidAudioCLI",
            dependencies: ["FluidAudio"],
            path: "Sources/FluidAudioCLI",
            exclude: ["README.md"],
            resources: [
                .process("Utils/english.json")
            ]
        ),
        .testTarget(
            name: "FluidAudioTests",
            dependencies: [
                "FluidAudio",
                "FluidAudioCLI",
            ],
            resources: [
                .process("TTS/LuxTts/Resources"),
                .process("TTS/PocketTTS/Fixtures"),
                // Real recordings (cleared for public release by the speaker) for the
                // streaming final-window regression, issue #855.
                .copy("ASR/Parakeet/SlidingWindow/Fixtures"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
