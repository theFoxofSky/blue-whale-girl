import AppKit
guard CommandLine.arguments.count >= 3 && ["quit","status"].contains(CommandLine.arguments[1]) else {
    fputs("Usage: manage-pet quit|status /absolute/path.app [expected-version]\n",stderr)
    exit(2)
}
let target=URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL.path
func matches() -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier:"local.bluewhale.desktop.pet").filter {
        $0.bundleURL?.standardizedFileURL.path == target && $0.processIdentifier != getpid()
    }
}
if CommandLine.arguments[1] == "quit" {
    let apps=matches()
    for app in apps {
        guard app.terminate() else { fputs("Could not request pet termination\n",stderr); exit(1) }
    }
    let deadline=Date().addingTimeInterval(5)
    while apps.contains(where:{ !$0.isTerminated }) && Date()<deadline {
        RunLoop.current.run(until:Date().addingTimeInterval(0.05))
    }
    guard apps.allSatisfy({$0.isTerminated}) else { fputs("Old pet still running\n",stderr); exit(1) }
    print("Gracefully stopped \(apps.count) previous pet instance(s).")
} else {
    let apps=matches()
    guard apps.count == 1, let app=apps.first else { fputs("Expected one running installed pet\n",stderr); exit(1) }
    let version=Bundle(url:app.bundleURL!)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown"
    print("Running installed pet: pid=\(app.processIdentifier), version=\(version), path=\(target)")
    let expected=CommandLine.arguments.count>3 ? CommandLine.arguments[3] : Bundle(path:target)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String
    guard version == expected else { exit(1) }
}
