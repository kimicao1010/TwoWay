import Vision

/// 二维码图片解码（C2-6）—— v1.1 起 Vision 是**唯一**解码路径（RK2b，无摄像头兜底）
///
/// E11（多二维码）：按二维码包围盒面积**降序**返回，调用方优先取最大者。
/// 只认 `.qr` symbology，其余条码（Code128 等）不算验证器二维码。
enum QRImageDecoder {

    enum DecodeError: Error {
        /// Vision 管线本身失败（图片无法构造成 handler 等）
        case pipelineFailed
    }

    /// 解码图片中的全部 QR 内容，按包围盒面积从大到小排序。
    ///
    /// 返回空数组 = 图中没有可识别的二维码（PRD E9 由调用方提示）。
    static func decode(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw DecodeError.pipelineFailed
        }

        return (request.results ?? [])
            .compactMap { observation -> (payload: String, area: Double)? in
                guard let payload = observation.payloadStringValue else { return nil }
                let box = observation.boundingBox
                return (payload, Double(box.width * box.height))
            }
            .sorted { $0.area > $1.area }
            .map(\.payload)
    }
}
