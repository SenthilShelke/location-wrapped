// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "RecapCore", platforms: [.macOS(.v13)], products: [.library(name: "RecapCore", targets: ["RecapCore"])], targets: [.target(name: "RecapCore", path: "LocationRecap/Core"), .testTarget(name: "RecapCoreTests", dependencies: ["RecapCore"], path: "Tests/RecapCoreTests")])
