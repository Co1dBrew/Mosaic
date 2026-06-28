import Foundation

/// Entry point for the MosaicKit core test suite. Run with `swift run mosaic-checks`.
@main
struct Checks {
    static func main() async {
        let r = CheckRunner()
        print("Running MosaicKit core checks…")

        runProviderChecks(r)
        runParserChecks(r)
        runDiffChecks(r)
        runAggregatorChecks(r)
        runRequestBuilderChecks(r)
        runKeychainChecks(r)
        await runClientChecks(r)

        r.finish()
    }
}
