import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("VEXRankKit_VEXRankKitTests.bundle").path
        let buildPath = "/Users/stevenqqian/Documents/Vex-Rank/ios/VEXRankKit/.build/arm64-apple-macosx/debug/VEXRankKit_VEXRankKitTests.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}