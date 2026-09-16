import Foundation
import Testing
@testable import TwoWay

/// C1-3：`otpauth://` 解析（含 PRD E10 非 otpauth 内容、范围外 HOTP 的拦截）
@Suite("otpauth URI 解析")
struct OTPAuthURITests {

    private let standardSecret = try! Base32.decode("JBSWY3DPEHPK3PXP")

    // MARK: 合法输入

    @Test("标准格式：label 带发行方前缀")
    func standardWithIssuerPrefix() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/GitHub:you@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub"
        )
        #expect(parsed.issuer == "GitHub")
        #expect(parsed.accountLabel == "you@example.com")
        #expect(parsed.secret == standardSecret)
        #expect(parsed.parameters.algorithm == .sha1)
        #expect(parsed.parameters.digits == 6)
        #expect(parsed.parameters.period == 30)
    }

    @Test("label 无前缀时回落到 query 的 issuer")
    func issuerFromQuery() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/you@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Acme%20Corp"
        )
        #expect(parsed.issuer == "Acme Corp")
        #expect(parsed.accountLabel == "you@example.com")
    }

    @Test("两者都缺 issuer 时为 nil")
    func issuerAbsent() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/you@example.com?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(parsed.issuer == nil)
        #expect(parsed.accountLabel == "you@example.com")
    }

    @Test("percent-encoded 的 label 能正确解码")
    func percentEncodedLabel() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/GitHub%3Akimi%40example.com?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(parsed.issuer == "GitHub")
        #expect(parsed.accountLabel == "you@example.com")
    }

    @Test("label 含多个冒号时只按第一个切分（账户名允许含冒号）")
    func multipleColonsInLabel() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/Acme:ops:team@example.com?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(parsed.issuer == "Acme")
        #expect(parsed.accountLabel == "ops:team@example.com")
    }

    @Test("scheme 大小写不敏感")
    func uppercaseScheme() throws {
        let parsed = try OTPAuthURI.parse(
            "OTPAUTH://totp/a?secret=JBSWY3DPEHPK3PXP"
        )
        #expect(parsed.accountLabel == "a")
    }

    @Test("secret 中的空格与连字符按 E3 清洗")
    func secretSanitized() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/a?secret=jbsw%20y3dp-ehpk%203pxp"
        )
        #expect(parsed.secret == standardSecret)
    }

    // MARK: 高级参数

    @Test("digits=8 / period=60 / SHA256 均可解析")
    func advancedParameters() throws {
        let parsed = try OTPAuthURI.parse(
            "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&digits=8&period=60&algorithm=SHA256"
        )
        #expect(parsed.parameters.digits == 8)
        #expect(parsed.parameters.period == 60)
        #expect(parsed.parameters.algorithm == .sha256)
    }

    @Test("algorithm 的连字符与大小写变体（SHA-1 / sha512）")
    func algorithmVariants() throws {
        let a = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&algorithm=SHA-1")
        let b = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&algorithm=sha512")
        #expect(a.parameters.algorithm == .sha1)
        #expect(b.parameters.algorithm == .sha512)
    }

    @Test("参数可省略，回落到 PRD T1 默认值")
    func defaultsWhenOmitted() throws {
        let parsed = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP")
        #expect(parsed.parameters == .standard)
    }

    // MARK: 拒绝路径

    @Test("缺 secret → missingSecret")
    func missingSecret() {
        #expect(throws: OTPAuthURI.ParseError.missingSecret) {
            _ = try OTPAuthURI.parse("otpauth://totp/a")
        }
        #expect(throws: OTPAuthURI.ParseError.missingSecret) {
            _ = try OTPAuthURI.parse("otpauth://totp/a?secret=")
        }
    }

    @Test("非 otpauth scheme → invalidScheme（PRD E10：不静默失败）", arguments: [
        ("https://example.com/whatever", "https"),
        ("http://totp/a?secret=JBSWY3DPEHPK3PXP", "http"),
        ("ftp://x/y", "ftp"),
    ])
    func invalidScheme(_ raw: String, scheme: String) {
        #expect(throws: OTPAuthURI.ParseError.invalidScheme(scheme)) {
            _ = try OTPAuthURI.parse(raw)
        }
    }

    @Test("完全无法解析为 URL → malformed", arguments: [
        "",
        "   ",
        "random text",
        "::::",
    ])
    func malformed(_ raw: String) {
        #expect(throws: OTPAuthURI.ParseError.malformed) {
            _ = try OTPAuthURI.parse(raw)
        }
    }

    @Test("HOTP 属范围外 → unsupportedType", arguments: [
        "otpauth://hotp/a?secret=JBSWY3DPEHPK3PXP&counter=1",
    ])
    func unsupportedType(_ raw: String) {
        #expect(throws: OTPAuthURI.ParseError.unsupportedType("hotp")) {
            _ = try OTPAuthURI.parse(raw)
        }
    }

    @Test("未知算法 / 非法位数 / 非法周期 → invalidParameter")
    func invalidParameters() {
        #expect(throws: OTPAuthURI.ParseError.invalidParameter("algorithm: MD5")) {
            _ = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&algorithm=MD5")
        }
        #expect(throws: OTPAuthURI.ParseError.invalidParameter("digits: 7")) {
            _ = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&digits=7")
        }
        #expect(throws: OTPAuthURI.ParseError.invalidParameter("period: 0")) {
            _ = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PXP&period=0")
        }
    }

    @Test("secret 含非法 base32 字符 → invalidSecret（E4）")
    func invalidSecret() {
        #expect(throws: OTPAuthURI.ParseError.invalidSecret(.invalidCharacter("1"))) {
            _ = try OTPAuthURI.parse("otpauth://totp/a?secret=JBSWY3DPEHPK3PX1")
        }
    }

    @Test("空 label → emptyLabel", arguments: [
        "otpauth://totp/?secret=JBSWY3DPEHPK3PXP",
        "otpauth://totp?secret=JBSWY3DPEHPK3PXP",
    ])
    func emptyLabel(_ raw: String) {
        #expect(throws: OTPAuthURI.ParseError.emptyLabel) {
            _ = try OTPAuthURI.parse(raw)
        }
    }

    @Test("label 仅含冒号前缀（无账户名）→ emptyLabel")
    func colonOnlyLabel() {
        #expect(throws: OTPAuthURI.ParseError.emptyLabel) {
            _ = try OTPAuthURI.parse("otpauth://totp/GitHub:?secret=JBSWY3DPEHPK3PXP")
        }
    }
}
