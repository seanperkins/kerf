import AppKit
import CADCore
import CAMCore
import Foundation
import Testing
@testable import KerfApp

@Suite struct IOFileThumbnailTests {
    func xattrs(_ url: URL) -> [String] {
        url.withUnsafeFileSystemRepresentation { p -> [String] in
            let n = listxattr(p!, nil, 0, 0)
            guard n > 0 else { return [] }
            var buf = [CChar](repeating: 0, count: n)
            listxattr(p!, &buf, n, 0)
            return String(decoding: buf.map { UInt8(bitPattern: $0) }, as: UTF8.self).split(separator: "\0").map(String.init)
        }
    }

    @Test func iconIsSetAndModificationTimeKept() throws {
        let url = AppTestSupport.tempDir().appendingPathComponent("job.kerf")
        let content = try AppTestSupport.project().encoded()
        try content.write(to: url)
        var before = stat()
        #expect(stat(url.path, &before) == 0)
        Thread.sleep(forTimeInterval: 0.05)
        let img = try #require(FileThumbnail.image(for: AppTestSupport.project().document))
        #expect(img.size == NSSize(width: 256, height: 256))
        #expect(FileThumbnail.apply(img, to: url))
        var after = stat()
        #expect(stat(url.path, &after) == 0)
        #expect(after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec)
        #expect(after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
        #expect(xattrs(url).contains("com.apple.ResourceFork"))
        // The file content is untouched.
        #expect(try Data(contentsOf: url) == content)
    }
}
