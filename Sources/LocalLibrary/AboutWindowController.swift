import AppKit

/// A small native About window. It never reads the user's library.
final class AboutWindowController: NSWindowController {
    static let projectURL = URL(string: "https://github.com/YouDiSN/fishtouching-reader")!

    init(bundle: Bundle = .main) {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 290),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "关于 FishTouching Reader"
        panel.isReleasedWhenClosed = false
        super.init(window: panel)

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = bundle.url(forResource: "fish", withExtension: "png", subdirectory: "Icons")
            .flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "FishTouching Reader")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        content.addArrangedSubview(icon)

        let name = NSTextField(labelWithString: "FishTouching Reader")
        name.font = .systemFont(ofSize: 20, weight: .semibold)
        content.addArrangedSubview(name)

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let versionLabel = NSTextField(labelWithString: version.map { "版本 \($0)" } ?? "本地开发版本")
        versionLabel.textColor = .secondaryLabelColor
        content.addArrangedSubview(versionLabel)

        let description = NSTextField(labelWithString: "安静阅读，随时切换。")
        description.textColor = .secondaryLabelColor
        content.addArrangedSubview(description)

        let github = NSButton(title: "访问 GitHub ↗", target: self, action: #selector(openGitHub))
        github.bezelStyle = .rounded
        github.toolTip = Self.projectURL.absoluteString
        github.setAccessibilityLabel("在浏览器中打开 FishTouching Reader 的 GitHub 项目")
        content.addArrangedSubview(github)
        content.setCustomSpacing(16, after: description)

        let copyright = NSTextField(labelWithString: "Copyright © 2026 YouDiSN · MIT License")
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor
        content.addArrangedSubview(copyright)
        content.setCustomSpacing(16, after: github)

        guard let root = panel.contentView else { return }
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            content.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24)
        ])
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openGitHub() {
        if !NSWorkspace.shared.open(Self.projectURL) {
            let alert = NSAlert()
            alert.messageText = "暂时无法打开浏览器"
            alert.informativeText = "请在浏览器中访问 \(Self.projectURL.absoluteString)"
            if let window { alert.beginSheetModal(for: window) }
        }
    }
}
