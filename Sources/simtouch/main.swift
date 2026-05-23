import Foundation

let logger = Logger()

do {
    let cli = try CLI(arguments: CommandLine.arguments, logger: logger)
    try await cli.run()
} catch {
    logger.error("fatal: \(error)")
    exit(1)
}
