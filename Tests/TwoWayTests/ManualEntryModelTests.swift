import Foundation
import Testing
@testable import TwoWay

/// C2-5：手动输入页的表单状态机 —— E3 清洗 / E4 校验 / 参数组装 / 空名兜底 / 提交
@MainActor
@Suite("ManualEntryModel（手动输入表单）")
struct ManualEntryModelTests {

    private func makeStore() -> (AccountStore, InMemorySecretStore) {
        let backing = InMemorySecretStore()
        return (AccountStore(secrets: backing), backing)
    }

    // MARK: E3 清洗预览

    @Test("E3：sanitizedSecret 去空白连字符、转大写")
    func sanitized() {
        let model = ManualEntryModel()
        model.secretRaw = " jbsw y3dp-ehp k3pxp "
        #expect(model.sanitizedSecret == "JBSWY3DPEHPK3PXP")
    }

    // MARK: E4 校验

    @Test("E4：空输入不报错（留到提交时拦截）；非法字符报错；合法通过")
    func secretValidation() {
        let model = ManualEntryModel()
        #expect(model.secretError == nil)                       // 空 → 不报

        model.secretRaw = "JBSWY3DPEHPK3PXP"
        #expect(model.secretError == nil)                       // 合法

        model.secretRaw = "JBSWY3DPEHPK3PXP1"                   // '1' 不在 Base32 字符集
        #expect(model.secretError?.contains("无法识别的字符") == true)
    }

    @Test("E4：空格与连字符不算非法字符（E3 清洗后参与校验）")
    func whitespaceIsLegal() {
        let model = ManualEntryModel()
        model.secretRaw = "JBSW Y3DP-EHPK 3PXP"
        #expect(model.secretError == nil)
    }

    // MARK: 名称兜底

    @Test("名称为空 / 纯空白 → 提交名「新账户」（PRD §7.4）")
    func resolvedName() {
        let model = ManualEntryModel()
        #expect(model.resolvedName == "新账户")
        model.displayName = "   "
        #expect(model.resolvedName == "新账户")
        model.displayName = " GitHub · kimi "
        #expect(model.resolvedName == "GitHub · kimi")
    }

    // MARK: 参数组装

    @Test("高级选项组装参数；默认 SHA-1 / 6 位 / 30 秒（T1）")
    func parameters() throws {
        let model = ManualEntryModel()
        let params = try #require(model.parameters)
        #expect(params.algorithm == .sha1)
        #expect(params.digits == 6)
        #expect(params.period == 30)

        model.algorithm = .sha512
        model.digits = 8
        model.period = 60
        let changed = try #require(model.parameters)
        #expect(changed.algorithm == .sha512)
        #expect(changed.digits == 8)
        #expect(changed.period == 60)
    }

    // MARK: 提交

    @Test("submit 写入账户（密钥经 E3 清洗）、返回 toast 名、自清空表单")
    func submitSucceeds() throws {
        let (store, backing) = makeStore()
        let model = ManualEntryModel()
        model.displayName = "GitHub"
        model.secretRaw = "jbsw y3dp-ehp k3pxp"

        let name = try model.submit(into: store)
        #expect(name == "GitHub")
        #expect(model.secretRaw.isEmpty)          // 成功后自清空
        #expect(store.accounts.map(\.displayName) == ["GitHub"])

        // 清洗后的密钥真的能算出码（写进去的是解码后的原始字节）
        let stored = try #require(backing.readAllMetadata().first)
        let secret = try backing.read(id: stored.id).secret
        let expected = try Base32.decode("JBSWY3DPEHPK3PXP")
        #expect(secret == expected)
    }

    @Test("E4：提交时再次拦截非法密钥（不产出错误账户）")
    func submitRejectsInvalidSecret() {
        let (store, _) = makeStore()
        let model = ManualEntryModel()
        model.secretRaw = "!!!"

        #expect(throws: Base32.DecodingError.invalidCharacter("!")) {
            try model.submit(into: store)
        }
        #expect(store.accounts.isEmpty)
    }

    @Test("E4：提交空密钥被拦截（empty）")
    func submitRejectsEmptySecret() {
        let (store, _) = makeStore()
        let model = ManualEntryModel()
        #expect(throws: Base32.DecodingError.empty) {
            try model.submit(into: store)
        }
    }

    // MARK: 编辑模式（P1 C4-2）

    @Test("编辑模式：prefillForEditing 填入现值，提交走 update 而非新增")
    func editModeUpdatesExisting() throws {
        let (store, backing) = makeStore()
        try store.add(displayName: "GitHub", issuer: "GitHub", secretBase32: "JBSWY3DPEHPK3PXP")
        let account = try #require(store.accounts.first)

        let model = ManualEntryModel()
        model.prefillForEditing(account: account, secretBase32: store.secretBase32(for: account.id) ?? "")

        // 预填 = 现值
        #expect(model.displayName == "GitHub")
        #expect(model.issuer == "GitHub")
        #expect(model.secretRaw == "JBSWY3DPEHPK3PXP")
        #expect(model.editingAccountID == account.id)

        // 改动后提交 → 更新，不新增
        model.displayName = "GitHub 主号"
        model.algorithm = .sha256
        model.digits = 8
        let name = try model.submit(into: store)

        #expect(name == "GitHub 主号")
        #expect(store.accounts.count == 1, "编辑不应新增账户")
        #expect(store.accounts.first?.displayName == "GitHub 主号")
        #expect(store.accounts.first?.parameters.algorithm == .sha256)
        #expect(store.accounts.first?.parameters.digits == 8)
        #expect(store.accounts.first?.id == account.id, "id 不变（密钥条目绑定）")

        // 存储层也已更新（含密钥重写）
        let stored = try #require(backing.readAllMetadata().first)
        let entry = try backing.read(id: stored.id)
        #expect(entry.secret == (try Base32.decode("JBSWY3DPEHPK3PXP")))
        #expect(model.editingAccountID == nil, "提交后退出编辑模式")
    }

    @Test("编辑模式：改密钥后必须用新密钥取码（旧码缓存清除）")
    func editModeUpdatesSecretAndCode() throws {
        let (store, _) = makeStore()
        try store.add(displayName: "probe", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP")
        let account = try #require(store.accounts.first)
        let before = try #require(store.code(for: account.id))

        let model = ManualEntryModel()
        model.prefillForEditing(account: account, secretBase32: "GEZDGNBVGY3TQOJQ")
        try model.submit(into: store)

        let after = try #require(store.code(for: account.id))
        #expect(after != before, "换密钥后取码必须变化")
        #expect(store.accounts.count == 1)
    }

    @Test("编辑模式：空名称回落「新账户」")
    func editModeEmptyName() throws {
        let (store, _) = makeStore()
        try store.add(displayName: "old", issuer: nil, secretBase32: "JBSWY3DPEHPK3PXP")
        let account = try #require(store.accounts.first)

        let model = ManualEntryModel()
        model.prefillForEditing(account: account, secretBase32: "JBSWY3DPEHPK3PXP")
        model.displayName = "   "

        let name = try model.submit(into: store)
        #expect(name == "新账户")
        #expect(store.accounts.first?.displayName == "新账户")
    }

    // MARK: reset

    @Test("reset 恢复全部默认值（含退出编辑模式）")
    func reset() {
        let model = ManualEntryModel()
        model.displayName = "x"
        model.secretRaw = "JBSWY3DPEHPK3PXP"
        model.algorithm = .sha256
        model.digits = 8
        model.period = 60

        model.reset()
        #expect(model.displayName.isEmpty)
        #expect(model.secretRaw.isEmpty)
        #expect(model.algorithm == .sha1)
        #expect(model.digits == 6)
        #expect(model.period == 30)
    }
}
