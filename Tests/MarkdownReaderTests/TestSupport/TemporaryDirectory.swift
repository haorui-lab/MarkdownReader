import Foundation
import XCTest

/// 提供可复用临时目录的测试基类。
/// setUp 创建唯一临时目录，tearDown 递归删除，避免测试间互相污染。
class TemporaryDirectoryTestCase: XCTestCase {

    /// 当前测试用例专属的临时目录 URL
    var temporaryDirectory: URL!

    override func setUp() {
        super.setUp()
        // 使用 FileManager 临时目录 + UUID，避免 NSTemporaryDirectory() 的并发竞争
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("MarkdownReaderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        temporaryDirectory = dir
    }

    override func tearDown() {
        if let dir = temporaryDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    /// 在临时目录内创建一个文件，返回其 URL。content 默认为空字符串。
    @discardableResult
    func makeFile(named name: String, content: String = "") throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 在指定目录内创建一个文件，返回其 URL。
    @discardableResult
    func makeFile(named name: String, in directory: URL, content: String = "") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 在临时目录内创建子目录，返回其 URL。
    @discardableResult
    func makeDirectory(named name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
