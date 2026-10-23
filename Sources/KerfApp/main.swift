import Foundation

// `kerf-cli export …` (and `Kerf export …`) posts a project and exits before the app, or any window system, starts.
if let status = KerfCLI.runIfRequested(CommandLine.arguments) { exit(status) }
KerfApp.main()
