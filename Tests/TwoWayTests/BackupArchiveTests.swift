import Foundation
import Testing
@testable import TwoWay

/// C4-3：加密备份 —— 往返 / 错口令 / 篡改 / 坏文件 / 弱口令 / 随机性 / 导入幂等
@MainActor
@Suite("BackupArchive（加密备份）")
struct BackupArchiveTests {

    private let password = "correct horse battery staple"

    private func sampleDocument() -> BackupArchive.Document {
        let parameters = (try? OTPParameters(algorithm: .sha256, digits: 8, period: 60))
            ?? OTPParameters.standard
        return BackupArchive.Document(
            exportedAt: Date(timeIntervalSince1970: 1_760_000_000),
            accounts: [
                BackupArchive.Entry(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    displayName: "GitHub",
                    issuer: "GitHub",
                    parameters: parameters,
                    addedAt: Date(timeIntervalSince1970: 1_759_000_000),
                    secret: Data([0x01, 0x02, 0x03, 0x04, 0x05])
                ),
                BackupArchive.Entry(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    displayName: "Acme Cloud",
                    issuer: nil,
                    parameters: OTPParameters.standard,
                    addedAt: Date(timeIntervalSince1970: 1_759_500_000),
                    secret: Data(repeating: 0xAB, count: 20)
                ),
            ]
        )
    }

    // MARK: 往返

    @Test("导出 → 导入往返：账户、密钥、高级参数完全一致")
    func roundTrip() throws {
        let document = sampleDocument()
        let data = try BackupArchive.encrypt(document, password: password)

        let restored = try BackupArchive.decrypt(data, password: password)
        #expect(restored == document)
        #expect(restored.format == BackupArchive.format)
        #expect(restored.accounts.count == 2)
    }

    @Test("文件头自描述：magic + 版本 + 迭代次数 + 盐长度，且密文不含明文密钥")
    func headerAndOpaqueCiphertext() throws {
        let data = try BackupArchive.encrypt(sampleDocument(), password: password)

        #expect(data.prefix(4) == BackupArchive.magic)
        #expect(data[data.index(data.startIndex, offsetBy: 4)] == 1)   // version
        let saltByte = data[data.index(data.startIndex, offsetBy: 9)]
        #expect(Int(saltByte) == BackupArchive.saltLength)

        // S1/S2：密文中不得出现明文密钥或账户名
        #expect(data.range(of: Data("GitHub".utf8)) == nil)
        #expect(data.range(of: Data([0x01, 0x02, 0x03, 0x04, 0x05])) == nil)
    }

    @Test("同一文档两次导出密文不同（随机盐 + 随机 nonce）")
    func randomizedOutput() throws {
        let document = sampleDocument()
        let first = try BackupArchive.encrypt(document, password: password)
        let second = try BackupArchive.encrypt(document, password: password)
        #expect(first != second)
        #expect(try BackupArchive.decrypt(first, password: password) == document)
        #expect(try BackupArchive.decrypt(second, password: password) == document)
    }

    // MARK: 失败路径

    @Test("口令错误 → wrongPasswordOrCorrupted（不泄露细节、不返回脏数据）")
    func wrongPassword() throws {
        let data = try BackupArchive.encrypt(sampleDocument(), password: password)
        #expect(throws: BackupArchive.ArchiveError.wrongPasswordOrCorrupted) {
            try BackupArchive.decrypt(data, password: "wrong password here")
        }
    }

    @Test("密文被篡改 → GCM 认证失败（与口令错误同样明确报错）")
    func tamperedCiphertext() throws {
        var data = try BackupArchive.encrypt(sampleDocument(), password: password)
        data[data.count - 1] ^= 0xFF
        #expect(throws: BackupArchive.ArchiveError.wrongPasswordOrCorrupted) {
            try BackupArchive.decrypt(data, password: password)
        }
    }

    @Test("非备份文件 → badMagic；版本不支持 → unsupportedVersion")
    func badFiles() throws {
        #expect(throws: BackupArchive.ArchiveError.badMagic) {
            try BackupArchive.decrypt(Data("not a backup file at all".utf8), password: password)
        }
        #expect(throws: BackupArchive.ArchiveError.badMagic) {
            try BackupArchive.decrypt(Data(), password: password)
        }

        var data = try BackupArchive.encrypt(sampleDocument(), password: password)
        data[data.index(data.startIndex, offsetBy: 4)] = 99   // 伪版本号
        #expect(throws: BackupArchive.ArchiveError.unsupportedVersion(99)) {
            try BackupArchive.decrypt(data, password: password)
        }
    }

    @Test("口令过短 → 导出时拦截（weakPassword）")
    func weakPassword() {
        #expect(throws: BackupArchive.ArchiveError.weakPassword(minimumLength: 8)) {
            try BackupArchive.encrypt(sampleDocument(), password: "short")
        }
    }

    // MARK: 导入合并（幂等）

    @Test("导入备份：新账户入库、同 id 跳过；再次导入全部跳过（幂等）")
    func importIsIdempotent() throws {
        let store = AccountStore(secrets: InMemorySecretStore())
        let document = sampleDocument()

        let first = try store.importBackup(document.accounts)
        #expect(first.imported == 2)
        #expect(first.skipped == 0)
        #expect(store.accounts.count == 2)
        // 与其他入口一致：按添加时间倒序
        #expect(store.accounts.map(\.displayName) == ["Acme Cloud", "GitHub"])

        let second = try store.importBackup(document.accounts)
        #expect(second.imported == 0)
        #expect(second.skipped == 2)
        #expect(store.accounts.count == 2, "重复导入不得产生副本")
    }

    @Test("导出 → 清空 → 导入 → 取码一致（逃生通道端到端）")
    func disasterRecoveryRoundTrip() throws {
        let backing = InMemorySecretStore()
        let store = AccountStore(secrets: backing)
        try store.add(displayName: "GitHub", issuer: "GitHub", secretBase32: "JBSWY3DPEHPK3PXP")
        let originalCode = try #require(store.code(for: store.accounts[0].id))

        // 导出
        let data = try BackupArchive.encrypt(
            BackupArchive.Document(accounts: store.backupEntries()),
            password: password
        )

        // 模拟「机器丢失」：全新空存储
        let restored = AccountStore(secrets: InMemorySecretStore())
        let document = try BackupArchive.decrypt(data, password: password)
        let result = try restored.importBackup(document.accounts)

        #expect(result.imported == 1)
        let restoredID = try #require(restored.accounts.first?.id)
        #expect(restored.accounts.first?.displayName == "GitHub")
        #expect(restored.accounts.first?.issuer == "GitHub")
        // 密钥一致 → 同一时刻的验证码必须相同
        #expect(restored.code(for: restoredID) == originalCode)
    }
}
