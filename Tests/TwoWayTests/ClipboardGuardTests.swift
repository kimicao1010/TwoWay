import Foundation
import Testing
@testable import TwoWay

/// S4：剪贴板自动清除 —— 关键是「不误清用户后来复制的内容」（TECH_PLAN §4.7）
@MainActor
@Suite("ClipboardGuard（S4 剪贴板自动清除）")
struct ClipboardGuardTests {

    /// 可模拟「其他应用写入」的剪贴板
    private final class FakePasteboard: Pasteboard {
        private(set) var content: String?
        private(set) var changeCount = 0
        var writeSucceeds = true

        @discardableResult
        func write(_ string: String) -> Bool {
            guard writeSucceeds else { return false }
            content = string
            changeCount += 1
            return true
        }

        func clearContents() {
            content = nil
            changeCount += 1
        }

        /// 模拟其他应用 / 用户复制了新内容
        func externalWrite(_ string: String) {
            content = string
            changeCount += 1
        }
    }

    private let code = "123456"

    @Test("复制成功 → 到期自动清除（默认 30s 的量级用短延迟验证）")
    func clearsAfterDelay() async throws {
        let pasteboard = FakePasteboard()
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 0.05)

        #expect(guardInstance.copy(code))
        #expect(pasteboard.content == code)

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(pasteboard.content == nil, "到期应清空剪贴板")
    }

    @Test("期间他方写入 → 绝不误清（changeCount 已易主）")
    func doesNotClearOthersContent() async throws {
        let pasteboard = FakePasteboard()
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 0.05)

        #expect(guardInstance.copy(code))
        // 用户/其他应用复制了别的内容
        pasteboard.externalWrite("用户的新内容")

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(pasteboard.content == "用户的新内容", "不得清除他人内容（PRD §4.7 关键约束）")
    }

    @Test("手动触发：仍归我们所有 → 清除；已易主 → 返回 false 且不动剪贴板")
    func clearIfStillOwned() {
        let pasteboard = FakePasteboard()
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 30)

        #expect(guardInstance.copy(code))
        #expect(guardInstance.clearIfStillOwned())      // 归我们 → 清除
        #expect(pasteboard.content == nil)
        #expect(guardInstance.clearIfStillOwned() == false)   // 已清过，无待清除记录

        #expect(guardInstance.copy(code))
        pasteboard.externalWrite("他人内容")
        #expect(guardInstance.clearIfStillOwned() == false)
        #expect(pasteboard.content == "他人内容")
    }

    @Test("写入失败（E1）→ 返回 false，不安排清除")
    func writeFailure() async throws {
        let pasteboard = FakePasteboard()
        pasteboard.writeSucceeds = false
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 0.05)

        #expect(guardInstance.copy(code) == false)
        #expect(guardInstance.pendingChangeCount == nil)
    }

    @Test("关闭开关 → 复制成功但不清除（设置页落地后由用户控制）")
    func disabled() async throws {
        let pasteboard = FakePasteboard()
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 0.05)
        guardInstance.isEnabled = false

        #expect(guardInstance.copy(code))
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(pasteboard.content == code, "关闭时不应清除")
    }

    @Test("连续复制：计时重置，只清最后一次")
    func consecutiveCopies() async throws {
        let pasteboard = FakePasteboard()
        let guardInstance = ClipboardGuard(pasteboard: pasteboard, delay: 0.08)

        #expect(guardInstance.copy("111111"))
        #expect(guardInstance.copy("222222"))   // 第二次复制重置计时与记录

        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(pasteboard.content == nil)
    }

    @Test("默认延迟为 PRD 规定的 30 秒")
    func defaultDelay() {
        #expect(ClipboardGuard.defaultDelay == 30)
    }
}
