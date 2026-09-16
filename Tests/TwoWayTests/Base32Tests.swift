import Foundation
import Testing
@testable import TwoWay

@Suite("Base32 编解码（PRD E3 清洗 / E4 校验）")
struct Base32Tests {

    // MARK: RFC 4648 §10 标准向量（已用独立实现核对，非凭记忆）

    @Test("RFC 4648 编码向量", arguments: [
        ("", ""),
        ("f", "MY"),
        ("fo", "MZXQ"),
        ("foo", "MZXW6"),
        ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"),
        ("foobar", "MZXW6YTBOI"),
    ])
    func rfc4648Encode(input: String, expected: String) throws {
        #expect(Base32.encode(Data(input.utf8)) == expected)
    }

    @Test("RFC 6238 附录 B 的 secret 映射正确")
    func rfc6238SecretMapping() throws {
        let decoded = try Base32.decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
        #expect(decoded == Data("12345678901234567890".utf8))
    }

    @Test("编码后可无损往返")
    func roundTrip() throws {
        for length in 1...24 {
            let bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
            let data = Data(bytes)
            #expect(try Base32.decode(Base32.encode(data)) == data, "长度 \(length) 往返失败")
        }
    }

    // MARK: E3 清洗

    @Test("E3：小写、空格、连字符、padding 全部清洗", arguments: [
        "jbswy3dpehpk3pxp",
        "JBSW Y3DP EHPK 3PXP",
        "jbsw-y3dp-ehpk-3pxp",
        "JBSWY3DPEHPK3PXP",
        "jbsw\ty3dp\nehpk\r3pxp",
        "JBSWY3DPEHPK3PXP======",
    ])
    func sanitizeVariants(input: String) throws {
        let expected = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(try Base32.decode(input) == expected)
    }

    @Test("E3：清洗后的文本可用于编码往返")
    func sanitizeThenEncode() throws {
        let raw = " mzxw 6ytb-oi "
        let decoded = try Base32.decode(raw)
        #expect(Base32.encode(decoded) == "MZXW6YTBOI")
    }

    // MARK: E4 非法输入

    @Test("E4：非法字符必须抛错，不静默忽略", arguments: [
        ("JBSWY3DPEHPK3PX1", Character("1")),
        ("JBSWY3DPEHPK3PXP8", Character("8")),
        ("JBSWY3DP，EHPK3PXP", Character("，")),
        ("JBSWY3DP.EHPK3PXP", Character(".")),
    ])
    func invalidCharacterThrows(input: String, expected: Character) {
        #expect(throws: Base32.DecodingError.invalidCharacter(expected)) {
            _ = try Base32.decode(input)
        }
    }

    @Test("E4：清洗后为空必须抛错")
    func emptyThrows() {
        #expect(throws: Base32.DecodingError.empty) { _ = try Base32.decode("   ---===  ") }
        #expect(throws: Base32.DecodingError.empty) { _ = try Base32.decode("") }
    }

    @Test("sanitize 不吞掉非法字符（留给 decode 报错）")
    func sanitizeKeepsInvalidCharacters() {
        let cleaned = Base32.sanitize("abc 1 -9 =xyz")
        #expect(cleaned == "ABC19XYZ")
    }
}
