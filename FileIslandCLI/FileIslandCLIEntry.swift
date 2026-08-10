import Darwin
import Dispatch
import Foundation

@main
enum FileIslandCLIEntry {
    static func main() async {
        let locator = CLIResourceLocator(
            executableURL: URL(fileURLWithPath: CommandLine.arguments[0])
        )
        let output = FileHandleCLIOutput()
        do {
            let core = FileIslandCore.live(
                presetResourceURL: try locator.presetCatalogURL(),
                ffmpegExecutableURL: try locator.ffmpegExecutableURL()
            )
            let application = FileIslandCLIApplication(core: core, output: output)
            Darwin.signal(SIGINT, SIG_IGN)
            let execution = Task {
                await application.run(arguments: Array(CommandLine.arguments.dropFirst()))
            }
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            interrupt.setEventHandler { execution.cancel() }
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
