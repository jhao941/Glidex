import Testing
@testable import GlidexCore

@Suite("Logger")
struct LoggerTests {
    @Test("recent diagnostics retain structured log lines")
    func recentEntries() {
        let logger = Logger()
        logger.info("compatibility status=compatible")
        logger.error("sample failure")

        let entries = logger.recentEntries()
        #expect(entries.count == 2)
        #expect(entries[0].contains("[INFO]"))
        #expect(entries[0].contains("compatibility status=compatible"))
        #expect(entries[1].contains("[ERROR]"))
    }
}
