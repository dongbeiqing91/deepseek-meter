import AppKit

@main
struct DeepSeekMeterMain {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--debug-widget"), args.count > index + 1 {
            RenderPreview.debugWidget(to: args[index + 1], active: true)
            exit(0)
        }
        if args.contains("--stats-test") {
            StoreDiagnostics.run()
            exit(0)
        }
        if let index = args.firstIndex(of: "--render"), args.count > index + 1 {
            RenderPreview.write(to: args[index + 1])
            exit(0)
        }

        LegacyMigration.run()
        let app = NSApplication.shared
        let demo = args.contains("--demo") || args.contains("--selftest")
        let delegate = AppDelegate(demo: demo)
        if args.contains("--selftest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                delegate.selfTest()
            }
        }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
