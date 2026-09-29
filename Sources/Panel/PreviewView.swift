import AppKit
import SwiftUI

/// 選んだ・カーソルを当てた項目の中身を、パネルの上部に大きく出す。
struct PreviewView: View {
    @ObservedObject var model: PanelModel

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let detail = model.preview {
                header(detail)
                content(detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer(detail)
            }
        }
    }

    private func header(_ detail: ClipDetail) -> some View {
        HStack(spacing: 6) {
            if let icon = model.appIcon(for: detail.summary.sourceBundleID), !detail.summary.isSnippet {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            }
            Text(detail.summary.isSnippet ? "定型文" : detail.summary.sourceAppName ?? "不明なアプリ").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            if !detail.summary.tags.isEmpty {
                Text(detail.summary.tags.map { "#\($0)" }.joined(separator: " ")).font(.system(size: 11)).foregroundStyle(Theme.accent).lineLimit(1)
            }
            Spacer()
            Label(detail.summary.kind.label, systemImage: detail.summary.kind.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func content(_ detail: ClipDetail) -> some View {
        if model.hovered == nil || model.hovered == model.selection, let result = model.styleResult, let style = model.currentStyle {
            // 元の形以外の貼り方を選んでいるときは、実際に貼られる内容を出す。
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Label("「\(style.label)」で貼られる内容", systemImage: style.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(result)
                        .font(.system(size: 12.5, design: style.id.hasPrefix("table") || style.id.hasPrefix("path") ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        } else if let image = model.previewImage {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(Checkerboard())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let latex = detail.latex {
                    Text(latex.source).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                } else if let text = detail.text ?? detail.ocrText, !text.isEmpty {
                    Text((detail.text == nil ? "画像の文字：" : "") + text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        } else if !detail.filePaths.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(detail.filePaths, id: \.self) { path in
                        HStack(alignment: .top, spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28)
                                .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.4)
                            VStack(alignment: .leading, spacing: 2) {
                                Text((path as NSString).lastPathComponent).font(.system(size: 12))
                                Text(FileManager.default.fileExists(atPath: path) ? (path as NSString).deletingLastPathComponent : "見つかりません：\(path)")
                                    .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        } else if let text = detail.text, !text.isEmpty {
            ScrollView {
                Text(text)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        } else {
            Text(detail.summary.preview.isEmpty ? "プレビューできる中身がありません" : detail.summary.preview)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(12)
        }
    }

    private func footer(_ detail: ClipDetail) -> some View {
        let summary = detail.summary
        var parts = ["\(Self.dateFormatter.string(from: summary.copiedAt))", "コピー\(summary.copyCount)回・貼り付け\(summary.pasteCount)回",
                     ByteCountFormatter.string(fromByteCount: Int64(detail.totalBytes), countStyle: .file)]
        if let text = detail.text, !text.isEmpty { parts.append("\(text.count)文字") }
        if summary.oversized { parts.append("大きいため文字だけ保存") }
        return Text(parts.joined(separator: "・") + (detail.types.isEmpty ? "" : "\n型：" + detail.types.joined(separator: ", ")))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 2)
    }
}
