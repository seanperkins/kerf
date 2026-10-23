import Foundation

// `loftline-cli export …` (and `LoftLine export …`) posts a project and exits before the app, or any window system, starts.
if let status = LoftLineCLI.runIfRequested(CommandLine.arguments) { exit(status) }
LoftLineApp.main()
