// swift-tools-version: 5.9
// ════════════════════════════════════════════════════════════
// FremaRegi — 開発・CI用のSwiftパッケージ。
// SwiftUI を使わない Core/Logic/Store/Services のみを含めるので、
// Linux の `swift build` でもロジックのコンパイル確認ができる。
// Views 層とアプリの入口（FremaRegiApp.swift）は Xcode プロジェクト
// （project.yml → xcodegen generate）でビルドする。
// ════════════════════════════════════════════════════════════

import PackageDescription

let package = Package(
    name: "FremaRegi",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FremaRegiCore", targets: ["FremaRegiCore"]),
    ],
    targets: [
        .target(
            name: "FremaRegiCore",
            path: "FremaRegi",
            exclude: ["FremaRegiApp.swift", "Views"]
        )
    ]
)
