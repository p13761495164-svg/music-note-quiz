import UIKit
import WebKit
import CoreMIDI

final class ViewController: UIViewController, WKNavigationDelegate {
    private let hostedQuizURL = URL(string: "https://p13761495164-svg.github.io/music-note-quiz/")!
    private var webView: WKWebView!
    private var midiClient = MIDIClientRef()
    private var midiInputPort = MIDIPortRef()
    private var hasLoadedBundledFallback = false
    private var latestMIDIStatus: (message: String, connected: Bool)?

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "MusicNoteQuizIOS"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        self.webView = webView

        let container = UIView()
        container.backgroundColor = webView.backgroundColor
        container.addSubview(webView)
        view = container

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadHostedQuiz()
        startNativeMIDI()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .darkContent
    }

    private func loadHostedQuiz() {
        var request = URLRequest(url: hostedQuizURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        webView.load(request)
    }

    private func loadBundledQuiz() {
        guard !hasLoadedBundledFallback else { return }
        hasLoadedBundledFallback = true
        guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
            assertionFailure("Missing bundled index.html")
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
    }

    private func startNativeMIDI() {
        var status = MIDIClientCreateWithBlock("Music Note Quiz MIDI" as CFString, &midiClient) { [weak self] _ in
            DispatchQueue.main.async {
                self?.connectMIDISources()
            }
        }
        guard status == noErr else {
            sendMIDIStatus("iOS MIDI 初始化失败", connected: false)
            return
        }

        status = MIDIInputPortCreateWithBlock(midiClient, "Music Note Quiz Input" as CFString, &midiInputPort) { [weak self] packetList, _ in
            self?.handleMIDIPacketList(packetList)
        }
        guard status == noErr else {
            sendMIDIStatus("iOS MIDI 输入失败", connected: false)
            return
        }

        connectMIDISources()
    }

    private func connectMIDISources() {
        let sourceCount = MIDIGetNumberOfSources()
        guard sourceCount > 0 else {
            sendMIDIStatus("未发现 iOS MIDI 输入", connected: false)
            return
        }

        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(midiInputPort, source, nil)
        }
        sendMIDIStatus("\(sourceCount) 个 iOS MIDI 输入", connected: true)
    }

    private func handleMIDIPacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(Int(packet.length)))
            }
            handleMIDIBytes(bytes)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func handleMIDIBytes(_ bytes: [UInt8]) {
        var index = 0
        while index + 2 < bytes.count {
            let status = bytes[index]
            let command = status & 0xF0
            if command == 0x90 {
                let midi = Int(bytes[index + 1])
                let velocity = bytes[index + 2]
                if velocity > 0 {
                    DispatchQueue.main.async { [weak self] in
                        self?.sendMIDINote(midi)
                    }
                }
                index += 3
            } else if command == 0x80 {
                index += 3
            } else {
                index += 1
            }
        }
    }

    private func sendMIDINote(_ midi: Int) {
        webView.evaluateJavaScript("window.musicNoteQuizReceiveMidi && window.musicNoteQuizReceiveMidi(\(midi));")
    }

    private func sendMIDIStatus(_ message: String, connected: Bool) {
        latestMIDIStatus = (message, connected)
        pushMIDIStatusToWeb(message, connected: connected)
    }

    private func pushMIDIStatusToWeb(_ message: String, connected: Bool) {
        let escapedMessage = javascriptStringLiteral(message)
        let connectedValue = connected ? "true" : "false"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript("window.musicNoteQuizNativeMidiStatus && window.musicNoteQuizNativeMidiStatus(\(escapedMessage), \(connectedValue));")
        }
    }

    private func javascriptStringLiteral(_ value: String) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: [value]),
            let json = String(data: data, encoding: .utf8),
            json.count >= 2
        else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let latestMIDIStatus {
            pushMIDIStatusToWeb(latestMIDIStatus.message, connected: latestMIDIStatus.connected)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadBundledQuiz()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadBundledQuiz()
    }
}
