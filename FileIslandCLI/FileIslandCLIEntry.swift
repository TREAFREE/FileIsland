import Darwin
import Dispatch
import Foundation

@main
enum FileIslandCLIEntry {
    static func main() async {
        let output = FileHandleCLIOutput()
        do {
            let locator = CLIResourceLocator(
                executableURL: try CLIExecutableURLResolver().resolve()
            )
            let core = FileIslandCore.live(
                presetResourceURL: try locator.presetCatalogURL(),
                ffmpegExecutableURL: try locator.ffmpegExecutableURL(),
                ffprobeExecutableURL: try locator.ffprobeExecutableURL(),
                mediaValidatorExecutableURL: try locator.mediaValidatorExecutableURL()
            )
            let application = FileIslandCLIApplication(core: core, output: output)
            Darwin.signal(SIGINT, SIG_IGN)
            let execution = Task {
                await application.run(arguments: Array(CommandLine.arguments.dropFirst()))
            }
            let cancellationRelay = CLIExecutionCancellationRelay {
                execution.cancel()
            }
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            let signalHandler: @Sendable () -> Void = {
                cancellationRelay.cancel()
            }
            interrupt.setEventHandler(handler: signalHandler)
            interrupt.resume()
            let exitCode = await execution.value
            interrupt.cancel()
            Darwin.exit(exitCode.rawValue)
        } catch {
            output.writeStandardError(
                Data("fileisland: required runtime resources are unavailable.\n".utf8)
            )
            Darwin.exit(CLIExitCode.conversionFailure.rawValue)
        }
    }
}

/// Dispatch signal handlers execute on their configured queue. Keeping the
/// handler explicitly Sendable prevents Swift 6 from inheriting the async
/// main executor and trapping when SIGINT arrives on the dispatch worker.
private final class CLIExecutionCancellationRelay: @unchecked Sendable {
    private let operation: @Sendable () -> Void

    init(operation: @Sendable @escaping () -> Void) {
        self.operation = operation
    }

    func cancel() {
        operation()
    }
}
