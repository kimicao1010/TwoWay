import Foundation
import Testing
@testable import TwoWay

/// Domain 层：Account 搜索匹配（FR-03）、参数校验、调试脱敏（S1/S2）
@Suite("Account 领域对象")
struct AccountTests {

    private func account(name: String, issuer: String?) -> Account {
        Account(displayName: name, issuer: issuer)
    }

    // MARK: FR-03 搜索

    @Test("FR-03：按账户名或发行方匹配，不区分大小写", arguments: [
        ("git", true), ("GIT", true), ("Git", true),
        ("hub", true),
        ("公司", true),        // 发行方中文
        ("ops", true),
        ("工作号", true),
        ("zzz", false),
        ("", true),            // 空查询 = 不过滤
        ("   ", true),
    ])
    func searchMatching(query: String, expected: Bool) {
        let target = account(name: "GitHub 工作号", issuer: "公司发行方 ops@example.com")
        #expect(target.matches(query: query) == expected, "query=\(query)")
    }

    @Test("FR-03：发行方为 nil 时不误判")
    func nilIssuerNeverMatches() {
        let target = account(name: "AWS", issuer: nil)
        #expect(target.matches(query: "AWS"))
        #expect(!target.matches(query: "anything-else"))
    }

    @Test("FR-03：首尾空白会被修剪后再匹配")
    func queryIsTrimmed() {
        let target = account(name: "GitHub", issuer: nil)
        #expect(target.matches(query: "  git  "))
    }

    // MARK: 参数校验

    @Test("digits 只允许 6 / 8")
    func digitsValidation() {
        #expect(throws: OTPParameters.ValidationError.invalidDigits(7)) {
            _ = try OTPParameters(algorithm: .sha1, digits: 7, period: 30)
        }
        #expect(throws: OTPParameters.ValidationError.invalidDigits(0)) {
            _ = try OTPParameters(algorithm: .sha1, digits: 0, period: 30)
        }
        #expect((try? OTPParameters(algorithm: .sha1, digits: 6, period: 30)) != nil)
        #expect((try? OTPParameters(algorithm: .sha1, digits: 8, period: 30)) != nil)
    }

    @Test("period 必须为正且有限")
    func periodValidation() {
        #expect(throws: OTPParameters.ValidationError.invalidPeriod(.infinity)) {
            _ = try OTPParameters(algorithm: .sha1, digits: 6, period: .infinity)
        }
        // NaN 与任何值都不相等（包括它自己），不能走 Equatable 的 throws 断言，
        // 必须手动 catch 后按 case 解构再判断
        do {
            _ = try OTPParameters(algorithm: .sha1, digits: 6, period: .nan)
            Issue.record("NaN period 应被拒绝")
        } catch let error as OTPParameters.ValidationError {
            guard case .invalidPeriod(let value) = error else {
                Issue.record("错误分支不对：\(error)")
                return
            }
            #expect(value.isNaN)
        } catch {
            Issue.record("意外错误：\(error)")
        }
    }

    @Test("默认参数即 PRD T1：SHA-1 / 6 位 / 30 秒")
    func standardParameters() {
        #expect(OTPParameters.standard.algorithm == .sha1)
        #expect(OTPParameters.standard.digits == 6)
        #expect(OTPParameters.standard.period == 30)
        #expect(OTPParameters.standard.modulus == 1_000_000)
        #expect(try! OTPParameters(algorithm: .sha1, digits: 8, period: 30).modulus == 100_000_000)
    }

    // MARK: S1/S2 调试脱敏

    @Test("debugDescription 不含密钥字样，且只暴露账户 UUID")
    func debugDescriptionIsRedacted() throws {
        let account = Account(displayName: "GitHub", issuer: "GitHub")
        let description = account.debugDescription

        #expect(description.contains(account.id.uuidString))
        #expect(description.contains("GitHub"))
        // 结构上就不可能含密钥，这里固定这条契约，防止将来有人往 Account 里塞 secret
        #expect(!description.lowercased().contains("secret"))
        #expect(!description.lowercased().contains("key"))
    }

    @Test("Account 是值类型：拷贝互不影响")
    func valueSemantics() {
        var a = Account(displayName: "A", issuer: nil)
        let b = a
        a.displayName = "B"
        #expect(b.displayName == "A")
    }

    @Test("Codable 往返无损")
    func codableRoundTrip() throws {
        let original = Account(
            displayName: "腾讯云",
            issuer: "Tencent Cloud",
            parameters: try OTPParameters(algorithm: .sha512, digits: 8, period: 60),
            addedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Account.self, from: data)
        #expect(restored == original)
    }
}
