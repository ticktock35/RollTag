import CryptoKit
import Foundation

protocol ContentHashing: Sendable {
    func hashFile(at url: URL) throws -> String
}

struct FileHasher: ContentHashing {
    static let chunkSize = 256 * 1024

    func hashFile(at url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values.fileSize ?? 0)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var digest = SHA256()
        var sizeBytes = size.littleEndian
        withUnsafeBytes(of: &sizeBytes) { digest.update(data: Data($0)) }

        let first = try handle.read(upToCount: Self.chunkSize) ?? Data()
        digest.update(data: first)

        if size > Self.chunkSize * 2 {
            let mid = max(0, size / 2 - Int64(Self.chunkSize / 2))
            try handle.seek(toOffset: UInt64(mid))
            let middle = try handle.read(upToCount: Self.chunkSize) ?? Data()
            digest.update(data: middle)
        }

        if size > Self.chunkSize {
            try handle.seek(toOffset: UInt64(max(0, size - Int64(Self.chunkSize))))
            let last = try handle.read(upToCount: Self.chunkSize) ?? Data()
            digest.update(data: last)
        }

        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

struct ClosureHasher: ContentHashing {
    let block: @Sendable (URL) throws -> String

    func hashFile(at url: URL) throws -> String {
        try block(url)
    }
}
