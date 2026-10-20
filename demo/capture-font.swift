// Capture the current macOS font settings with the real system font list.
// Uses an ephemeral WKWebView; never opens a user library.
import AppKit
import WebKit
final class FontCapture: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 760), configuration: config)
        web.navigationDelegate = self
        window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        web.loadFileURL(resources.appendingPathComponent("index.html"), allowingReadAccessTo: resources)
    }
    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                let fonts = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
                let data = try JSONSerialization.data(withJSONObject: ["fonts": fonts])
                let json = String(data: data, encoding: .utf8)!
                _ = try await web.evaluateJavaScript("receive({type:'normal',pdfs:[]});showInlineSettings();receiveSettings({name:'FishTouching Reader',passwordScope:'public',canChangePassword:false,canCreatePrivate:true});receiveReadingPreferences({theme:'forest',font:'PingFang SC',fontSize:19});receiveSystemFonts(\(json));document.getElementById('navFont').click();")
                try await Task.sleep(nanoseconds: 500_000_000)
                let image = try await web.takeSnapshot(configuration: nil)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
                print("Captured current macOS font UI with \(fonts.count) system font families")
                NSApp.terminate(nil)
            } catch { print(error); exit(1) }
        }
    }
}
guard CommandLine.arguments.count == 3 else { fatalError("Usage: capture-font Resources output.png") }
let app = NSApplication.shared
let capture = FontCapture()
app.delegate = capture
app.setActivationPolicy(.accessory)
app.run()
