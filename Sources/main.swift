import Cocoa

// --diagnose：不打开窗口，只输出环境与权限诊断信息
if CommandLine.arguments.contains("--diagnose") {
    Diagnose.run()
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
