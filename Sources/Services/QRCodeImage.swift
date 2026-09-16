import AppKit
import CoreImage
import Foundation

/// 二维码图片**生成**（C4-4：导出 GA 迁移码 PNG 供手机扫描）
///
/// 与 `QRImageDecoder`（Vision 解码）相反方向：这里用 CoreImage 的
/// `CIQRCodeGenerator` 把字符串编成二维码位图。
enum QRCodeImage {

    enum GenerationError: Error, Equatable {
        case generationFailed
    }

    /// 生成二维码 PNG 数据。
    ///
    /// - Parameters:
    ///   - string: 待编码内容（如 `otpauth-migration://…`）
    ///   - scale: 放大倍数 —— CIQRCodeGenerator 输出是 1px/模块，直接存会太小；
    ///     默认放大 10 倍，保证手机可扫。
    ///   - correctionLevel: 纠错等级（L/M/Q/H），默认 M
    static func pngData(
        for string: String,
        scale: CGFloat = 10,
        correctionLevel: String = "M"
    ) throws -> Data {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw GenerationError.generationFailed
        }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else {
            throw GenerationError.generationFailed
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            throw GenerationError.generationFailed
        }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw GenerationError.generationFailed
        }
        return data
    }
}
