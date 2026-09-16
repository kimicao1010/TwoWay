import Foundation
import Testing
@testable import TwoWay

/// 诊断：默认真实时钟（Date.init）下取码是否随时间推进
/// （回归用户反馈：环在动但码文本冻结）
@MainActor
@Suite("AccountStore 默认真时钟")
struct AccountStoreRealtimeClockTests {

    @Test("默认 now = Date.init：时间推进后验证码必须变化（period=1s）")
    func realtimeClockAdvances() async throws {
        let store = AccountStore(secrets: InMemorySecretStore())

        // period 设为 1 秒，1.2 秒后必然跨周期
        let parameters = try OTPParameters(algorithm: .sha1, digits: 6, period: 1)
        try store.add(displayName: "probe", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP", parameters: parameters)

        let id = try #require(store.accounts.first?.id)
        let first = try #require(store.displayCode(for: id))
        let firstState = try #require(store.timeState(for: id))

        try await Task.sleep(nanoseconds: 1_200_000_000)

        let second = try #require(store.displayCode(for: id))
        let secondState = try #require(store.timeState(for: id))

        #expect(secondState.counter != firstState.counter, "counter 未推进 → now 时钟冻结")
        #expect(second != first, "验证码未变化 → 缓存未失效")
    }

    @Test("默认 now = Date.init：addedAt 接近当前时间")
    func addedAtUsesRealtime() throws {
        let store = AccountStore(secrets: InMemorySecretStore())
        try store.add(displayName: "probe", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP")
        let addedAt = try #require(store.accounts.first?.addedAt)
        #expect(abs(addedAt.timeIntervalSinceNow) < 5)
    }
}
