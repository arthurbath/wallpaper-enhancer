import Foundation
import Darwin

public enum ResultWriter {
    public static func save(_ data: Data, to directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw EnhancerError.saving("The output folder is unavailable. Choose an existing folder and use Save Again. Your completed image is preserved.")
        }
        let temporary = directory.appendingPathComponent(".wallpaper-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do { try data.write(to: temporary, options: .withoutOverwriting) }
        catch { throw EnhancerError.saving("The output folder could not be written. Choose another folder and use Save Again. Your completed image is preserved.") }
        var hash = FileDigest.sha256(data)
        for _ in 0..<32 {
            let destination = directory.appendingPathComponent(hash + ".png")
            do {
                // Publish atomically and refuse an existing target even if another process wins the race.
                guard renamex_np(temporary.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                return destination
            } catch {
                if FileManager.default.fileExists(atPath: destination.path) {
                    if let existing = try? Data(contentsOf: destination, options: .mappedIfSafe), existing == data { return destination }
                    var salted = data
                    salted.append(Data(UUID().uuidString.utf8))
                    hash = FileDigest.sha256(salted)
                    continue
                }
                throw EnhancerError.saving("The enhanced image could not be moved into the output folder. It is preserved and can be saved again without using more credits.")
            }
        }
        throw EnhancerError.saving("A unique output filename could not be reserved. Existing files were preserved. Choose another folder and use Save Again.")
    }
}
