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
        runSearchChecks(r)
        runTagsChecks(r)
        runPinningChecks(r)
        runMarkdownChecks(r)
        runExportChecks(r)
        await runClientChecks(r)
        await runTranscriptionChecks(r)
        await RetrievalFoundationChecks.run(r)
        await RetrievalWeek2Checks.run(r)
        await EmbeddingProviderChecks.run(r)
        EmbeddingProviderChecks.runCloud(r)
        await runLiveChecks(r)

        r.finish()
    }
}
