import Foundation

/// Base32（RFC 4648）编解码
///
/// 承担 PRD E3（清洗）与 E4（提交时校验，不产出错误验证码）。
enum Base32 {

    enum DecodingError: Error, Equatable {
        /// 非法字符（PRD E4：不静默忽略 —— 会掩盖用户输错的密钥）
        case invalidCharacter(Character)
        /// 清洗后为空
        case empty
    }

    static let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// PRD E3 清洗规则：去空白与连字符、去 base32 padding（=）、转大写
    ///
    /// padding 一并去除：真实服务商给出的密钥常带 `=` 结尾，
    /// 去掉后参与计算的位数与不带 padding 的写法一致。
    ///
    /// 注意：这里**只删**空白 / 连字符 / padding，不删其它字符 ——
    /// 非法字符必须留给 `decode` 抛错（E4），静默忽略会掩盖用户输错的密钥。
    static func sanitize(_ raw: String) -> String {
        raw.uppercased().filter { character in
            !character.isWhitespace && character != "-" && character != "="
        }
    }

    /// 解码。遇到非法字符抛错（E4：不忽略、不产生错误验证码）
    static func decode(_ raw: String) throws -> Data {
        let sanitized = sanitize(raw)
        guard !sanitized.isEmpty else { throw DecodingError.empty }

        var buffer = 0
        var bits = 0
        var output = [UInt8]()
        output.reserveCapacity(sanitized.count * 5 / 8)

        for character in sanitized {
            guard let index = alphabet.firstIndex(of: character) else {
                throw DecodingError.invalidCharacter(character)
            }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        // 剩余 bits < 8 的部分是 padding 产生的尾位，按 RFC 4648 丢弃
        return Data(output)
    }

    /// 编码（主要用于测试往返与调试）
    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var buffer = 0
        var bits = 0
        var output = ""
        output.reserveCapacity((data.count * 8 + 4) / 5)

        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            output.append(alphabet[(buffer << (5 - bits)) & 0x1F])
        }
        return output
    }
}
