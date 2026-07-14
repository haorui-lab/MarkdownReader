import XCTest
@testable import MarkdownReader

/// 资源身份规范化测试：路径标准化、符号链接、目录/文件区分、不存在路径稳定 key。
final class ResourceIdentityServiceTests: TemporaryDirectoryTestCase {

    private let service = ResourceIdentityService()

    // MARK: - WindowID Codable 往返

    func testWindowIDRoundTripsThroughCodable() throws {
        let id = WindowID()
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(WindowID.self, from: data)
        XCTAssertEqual(id, decoded)
        XCTAssertEqual(id.id, decoded.id)
    }

    // MARK: - 路径标准化

    func testDotDotAndStandardPathResolveToSameIdentity() throws {
        let dir = try makeDirectory(named: "proj")
        let file = try makeFile(named: "a.md", in: dir, content: "# A")
        let parent = temporaryDirectory

        // 通过 .. 引用同一文件
        let dotDotPath = parent!.appendingPathComponent("proj/../proj/a.md")
        let direct = service.identity(for: file, kind: .file)
        let viaDotDot = service.identity(for: dotDotPath, kind: .file)

        XCTAssertEqual(direct, viaDotDot)
        XCTAssertEqual(direct.canonicalURL.path, file.standardizedFileURL.path)
    }

    // MARK: - 符号链接

    func testSymlinkAndDestinationResolveToSameIdentity() throws {
        let realDir = try makeDirectory(named: "real")
        let realFile = try makeFile(named: "doc.md", in: realDir, content: "x")
        let link = temporaryDirectory.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realFile)

        let direct = service.identity(for: realFile, kind: .file)
        let linked = service.identity(for: link, kind: .file)
        XCTAssertEqual(direct, linked)
    }

    // MARK: - 文件 vs 目录

    func testFileAndDirectoryAtSamePathUseDifferentKinds() throws {
        let dir = try makeDirectory(named: "notes")
        let fileDir = service.identity(for: dir, kind: .directory)
        let fileFile = service.identity(for: dir, kind: .file)
        XCTAssertNotEqual(fileDir, fileFile)
    }

    // MARK: - 不存在路径

    func testMissingPathProducesStableIdentity() throws {
        let missing1 = temporaryDirectory.appendingPathComponent("ghost.md")
        let missing2 = temporaryDirectory.appendingPathComponent("ghost.md")

        let id1 = service.identity(for: missing1, kind: .file)
        let id2 = service.identity(for: missing2, kind: .file)
        XCTAssertEqual(id1, id2)
    }

    func testMissingPathDiffersFromExistingSibling() throws {
        // 临时目录的卷在 CI 上是大小写不敏感的；用不同文件名而非仅大小写，
        // 确保「存在」与「不存在」两个不同路径身份不同。
        let existing = try makeFile(named: "present.md", content: "hi")
        let missing = temporaryDirectory!.appendingPathComponent("absent.md")

        let existingId = service.identity(for: existing, kind: .file)
        let missingId = service.identity(for: missing, kind: .file)
        // 不存在的路径与存在路径 comparisonKey 应不同，避免误判所有权
        XCTAssertNotEqual(existingId, missingId)
    }

    // MARK: - 不同路径不等

    func testDifferentFilesProduceDifferentIdentities() throws {
        let a = try makeFile(named: "a.md", content: "a")
        let b = try makeFile(named: "b.md", content: "b")
        XCTAssertNotEqual(service.identity(for: a, kind: .file),
                          service.identity(for: b, kind: .file))
    }
}
