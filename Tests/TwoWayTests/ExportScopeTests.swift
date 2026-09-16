import Foundation
import Testing
@testable import TwoWay

/// 导出范围（C4-10）：全部账户 / 指定账户
@MainActor
@Suite("导出范围选择")
struct ExportScopeTests {

    @Test("effectiveIDs：全部 → nil（导出全部）；选择 → 所选集合（可多个）")
    func effectiveIDs() {
        let first = UUID()
        let second = UUID()

        #expect(ExportScopePicker.effectiveIDs(scope: .all, selectedIDs: []) == nil)
        #expect(ExportScopePicker.effectiveIDs(scope: .all, selectedIDs: [first, second]) == nil)
        #expect(ExportScopePicker.effectiveIDs(scope: .selected, selectedIDs: [first]) == [first])
        #expect(ExportScopePicker.effectiveIDs(scope: .selected, selectedIDs: [first, second]) == [first, second])
        #expect(ExportScopePicker.effectiveIDs(scope: .selected, selectedIDs: []) == [])
    }

    @Test("多选过滤：一次导出覆盖所选多个账户（不必导出多次）")
    func multiSelectionFiltersInOnePass() throws {
        let store = AccountStore(secrets: InMemorySecretStore())
        try store.add(displayName: "GitHub", issuer: "GitHub", secretBase32: "JBSWY3DPEHPK3PXP")
        try store.add(displayName: "Acme Cloud", issuer: "Acme Cloud", secretBase32: "GEZDGNBVGY3TQOJQ")
        try store.add(displayName: "Homelab", issuer: "Homelab", secretBase32: "KRSXG5CTMVRXEZLU")

        let picked = Set(store.accounts.filter { $0.displayName != "Acme Cloud" }.map(\.id))
        #expect(picked.count == 2)

        let entries = store.backupEntries().filter { picked.contains($0.id) }
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.displayName)) == ["GitHub", "Homelab"])

        // 一次加密即可承载多个账户
        let data = try BackupArchive.encrypt(
            BackupArchive.Document(accounts: entries),
            password: "multi account password"
        )
        let document = try BackupArchive.decrypt(data, password: "multi account password")
        #expect(document.accounts.count == 2)
    }

    @Test("账户标签：有发行方 → 「发行方：账户名」；缺失/与名称相同 → 仅名称")
    func labels() {
        let withIssuer = Account(displayName: "ops", issuer: "Acme 控制台")
        #expect(ExportScopePicker.label(for: withIssuer) == "Acme 控制台：ops")

        let noIssuer = Account(displayName: "ops", issuer: nil)
        #expect(ExportScopePicker.label(for: noIssuer) == "ops")

        let sameName = Account(displayName: "GitHub", issuer: "GitHub")
        #expect(ExportScopePicker.label(for: sameName) == "GitHub")

        let emptyIssuer = Account(displayName: "ops", issuer: "")
        #expect(ExportScopePicker.label(for: emptyIssuer) == "ops")
    }

    @Test("按范围过滤导出条目：全部 = 全量；指定 = 单条，且内容与源一致")
    func filteredEntries() throws {
        let store = AccountStore(secrets: InMemorySecretStore())
        try store.add(displayName: "GitHub", issuer: "GitHub", secretBase32: "JBSWY3DPEHPK3PXP")
        try store.add(displayName: "Acme Cloud", issuer: "Acme Cloud", secretBase32: "GEZDGNBVGY3TQOJQ")

        let all = store.backupEntries()
        #expect(all.count == 2)

        let onlyID = try #require(store.accounts.first(where: { $0.displayName == "Acme Cloud" })?.id)
        let single = all.filter { $0.id == onlyID }
        #expect(single.count == 1)
        #expect(single.first?.displayName == "Acme Cloud")
        #expect(single.first?.secret == (try Base32.decode("GEZDGNBVGY3TQOJQ")))
    }

    @Test("单账户导出的备份可完整恢复（GA 迁移码同路径）")
    func singleAccountBackupRoundTrip() throws {
        let store = AccountStore(secrets: InMemorySecretStore())
        try store.add(displayName: "GitHub", issuer: "GitHub", secretBase32: "JBSWY3DPEHPK3PXP")
        try store.add(displayName: "Acme Cloud", issuer: "Acme Cloud", secretBase32: "GEZDGNBVGY3TQOJQ")

        let onlyID = try #require(store.accounts.first(where: { $0.displayName == "GitHub" })?.id)
        let entries = store.backupEntries().filter { $0.id == onlyID }

        // 加密备份往返
        let data = try BackupArchive.encrypt(
            BackupArchive.Document(accounts: entries),
            password: "single account password"
        )
        let document = try BackupArchive.decrypt(data, password: "single account password")
        #expect(document.accounts.count == 1)

        let restored = AccountStore(secrets: InMemorySecretStore())
        let result = try restored.importBackup(document.accounts)
        #expect(result.imported == 1)
        #expect(restored.accounts.first?.displayName == "GitHub")

        // GA 迁移码路径：编码 → 解析
        let uri = OTPMigration.migrationURI(
            entries: entries.map {
                OTPMigration.Entry(
                    displayName: $0.displayName,
                    issuer: $0.issuer,
                    secret: $0.secret,
                    parameters: $0.parameters
                )
            }
        )
        let parsed = try OTPMigration.parse(uri)
        #expect(parsed.entries.count == 1)
        #expect(parsed.entries.first?.displayName == "GitHub")
    }
}
