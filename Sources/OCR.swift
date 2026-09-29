import Foundation
import ImageIO
import Vision

/// 画像の中の文字を読む（F-08）。日本語と英語。どのスレッドからでも呼べる（重いので裏のキューで呼ぶ）。
enum OCR {
    static func recognize(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ja-JP", "en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }
        // 上の行から順に並べる（Vision の座標は左下が原点）。
        let lines = (request.results ?? [])
            .sorted { lhs, rhs in abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.01 ? lhs.boundingBox.midY > rhs.boundingBox.midY : lhs.boundingBox.minX < rhs.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
