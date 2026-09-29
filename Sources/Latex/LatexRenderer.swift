import AppKit
import ImageIO
import PDFKit
import WebKit

/// 描いた数式画像。クリップボードには PDF（ベクター）・PNG・TIFF と元の式を載せる（F-06）。
struct LatexImage {
    let latex: LatexSource
    let pdf: Data
    let png: Data
    let tiff: Data
    /// 大きさ（pt）。
    let size: CGSize

    var representations: [Representation] {
        [Representation(type: "com.adobe.pdf", data: pdf), Representation(type: "public.png", data: png),
         Representation(type: "public.tiff", data: tiff), Representation(type: Capture.latexType, data: Data(latex.json.utf8))]
    }
}

struct LatexError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// 同梱の KaTeX を画面外の WKWebView で動かして数式を描く。PDF は WebKit から、PNG・TIFF はその PDF から作る。
@MainActor
final class LatexRenderer: NSObject, WKNavigationDelegate {
    /// PNG・TIFF の倍率。288dpi で保存するので、貼った先では pt の大きさのまま細かく表示される。
    nonisolated static let rasterScale: CGFloat = 4

    private let resources: URL
    private var window: NSWindow?
    private var webView: WKWebView?
    private var loaded: CheckedContinuation<Void, Never>?
    private var ready = false
    private var loadError: String?

    /// resources は同梱の KaTeX のフォルダ（render.html がある所）。
    init(resources: URL = Bundle.main.resourceURL!.appendingPathComponent("katex")) {
        self.resources = resources
    }
    /// 同時に描かないよう、前の描画が終わるのを待つ。
    private var previous: Task<Void, Never>?

    private func prepare() async {
        if ready { return }
        if webView == nil {
            let configuration = WKWebViewConfiguration()
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1200), configuration: configuration)
            webView.setValue(false, forKey: "drawsBackground")
            webView.navigationDelegate = self
            // 画面の外に置いた見えないウィンドウに入れて、レイアウトとフォントの読み込みを動かす。
            let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 2000, height: 1200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = webView
            window.orderFrontRegardless()
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            self.window = window
            self.webView = webView
            webView.loadFileURL(resources.appendingPathComponent("render.html"), allowingReadAccessTo: resources)
        }
        await withCheckedContinuation { continuation in
            if ready || webView == nil { continuation.resume() } else { loaded = continuation }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishLoading(error: nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading(error: error.localizedDescription) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoading(error: error.localizedDescription) }
    }

    private func finishLoading(error: String?) {
        loadError = error
        ready = error == nil
        if error != nil { webView = nil; window?.orderOut(nil); window = nil }  // 次に描くときに読み込み直す
        loaded?.resume()
        loaded = nil
    }

    func render(_ latex: LatexSource, macros: String) async throws -> LatexImage {
        let wait = previous
        let task = Task { @MainActor () -> Result<LatexImage, Error> in
            await wait?.value
            do { return .success(try await renderNow(latex, macros: macros)) } catch { return .failure(error) }
        }
        previous = Task { _ = await task.value }
        return try await task.value.get()
    }

    private func renderNow(_ latex: LatexSource, macros: String) async throws -> LatexImage {
        await prepare()
        guard ready, let webView else { throw LatexError(message: "数式を描く準備ができませんでした。\(loadError ?? "")") }
        let source = LatexSource.stripDelimiters(latex.source)
        guard !source.isEmpty else { throw LatexError(message: "式を入力してください。") }
        let options = latex.options
        let result = try await webView.callAsyncJavaScript(
            "return await render(source, macros, displayMode, color, background, fontSize, padding);",
            arguments: ["source": source, "macros": macros, "displayMode": options.displayMode, "color": options.color, "background": options.background ?? "",
                        "fontSize": options.fontSize, "padding": options.padding],
            in: nil, contentWorld: .page) as? [String: Any]
        if let message = result?["error"] as? String { throw LatexError(message: message) }
        guard let width = (result?["width"] as? NSNumber)?.doubleValue, let height = (result?["height"] as? NSNumber)?.doubleValue, width > 0, height > 0 else {
            throw LatexError(message: "数式を描けませんでした。")
        }
        let x = (result?["x"] as? NSNumber)?.doubleValue ?? 0, y = (result?["y"] as? NSNumber)?.doubleValue ?? 0
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: x, y: y, width: width, height: height)
        let rawPDF = try await webView.pdf(configuration: configuration)
        return try Self.makeImage(latex, pdf: rawPDF)
    }

    /// PDF に元の式を埋め込み、同じ PDF から PNG・TIFF を作る。
    nonisolated static func makeImage(_ latex: LatexSource, pdf rawPDF: Data) throws -> LatexImage {
        guard let document = PDFDocument(data: rawPDF), let page = document.page(at: 0) else { throw LatexError(message: "数式の PDF を作れませんでした。") }
        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.keywordsAttribute] = latex.embedded
        attributes[PDFDocumentAttribute.subjectAttribute] = latex.source
        attributes[PDFDocumentAttribute.creatorAttribute] = "Pastephant"
        document.documentAttributes = attributes
        guard let pdf = document.dataRepresentation() else { throw LatexError(message: "数式の PDF を作れませんでした。") }
        let bounds = page.bounds(for: .mediaBox)
        let scale = rasterScale
        let width = max(1, Int(ceil(bounds.width * scale))), height = max(1, Int(ceil(bounds.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pageRef = page.pageRef else { throw LatexError(message: "数式の画像を作れませんでした。") }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        context.drawPDFPage(pageRef)
        guard let image = context.makeImage() else { throw LatexError(message: "数式の画像を作れませんでした。") }
        let dpi = 72 * scale
        func encode(_ type: String, _ extra: [CFString: Any]) -> Data? {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }
            var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
            properties.merge(extra) { _, new in new }
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? output as Data : nil
        }
        guard let png = encode("public.png", [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: latex.embedded]]),
              let tiff = encode("public.tiff", [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: latex.embedded]]) else {
            throw LatexError(message: "数式の画像を作れませんでした。")
        }
        return LatexImage(latex: latex, pdf: pdf, png: png, tiff: tiff, size: bounds.size)
    }
}
