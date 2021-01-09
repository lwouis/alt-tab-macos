//
//  String+File.swift
//  Swifter
//
//  Copyright © 2016 Damian Kołakowski. All rights reserved.
//

import Foundation

extension String {

    public enum FileError: Error {
        case error(Int32)
    }

    public class File {

        let pointer: UnsafeMutablePointer<FILE>

        public init(_ pointer: UnsafeMutablePointer<FILE>) {
            self.pointer = pointer
        }

        public func close() {
            fclose(pointer)
        }

        public func seek(_ offset: Int) -> Bool {
            return (fseek(pointer, offset, SEEK_SET) == 0)
        }

        public func read(_ data: inout [UInt8]) throws -> Int {
            if data.count <= 0 {
                return data.count
            }
            let count = fread(&data, 1, data.count, self.pointer)
            if count == data.count {
                return count
            }
            if feof(self.pointer) != 0 {
                return count
            }
            if ferror(self.pointer) != 0 {
                throw FileError.error(errno)
            }
            throw FileError.error(0)
        }

        public func write(_ data: [UInt8]) throws {
            if data.count <= 0 {
                return
            }
            try data.withUnsafeBufferPointer {
                if fwrite($0.baseAddress, 1, data.count, self.pointer) != data.count {
                    throw FileError.error(errno)
                }
            }
        }

        public static func currentWorkingDirectory() throws -> String {
            guard let path = getcwd(nil, 0) else {
                throw FileError.error(errno)
            }
            return String(cString: path)
        }
    }

    public static var pathSeparator = "/"

    public func openNewForWriting() throws -> File {
        return try openFileForMode(self, "wb")
    }

    public func openForReading() throws -> File {
        return try openFileForMode(self, "rb")
    }

    public func openForWritingAndReading() throws -> File {
        return try openFileForMode(self, "r+b")
    }

    public func openFileForMode(_ path: String, _ mode: String) throws -> File {
        guard let file = path.withCString({ pathPointer in mode.withCString({ fopen(pathPointer, $0) }) }) else {
            throw FileError.error(errno)
        }
        return File(file)
    }

    public func exists() throws -> Bool {
        return try self.withStat {
            if $0 != nil {
                return true
            }
            return false
        }
    }

    public func directory() throws -> Bool {
        return try self.withStat {
            if let stat = $0 {
                return stat.st_mode & S_IFMT == S_IFDIR
            }
            return false
        }
    }

    public func files() throws -> [String] {
        guard let dir = self.withCString({ opendir($0) }) else {
            throw FileError.error(errno)
        }
        defer { closedir(dir) }
        var results = [String]()
        while let ent = readdir(dir) {
            var name = ent.pointee.d_name
            let fileName = withUnsafePointer(to: &name) { (ptr) -> String? in
                #if os(Linux)
                  return String(validatingUTF8: ptr.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_reclen), { (ptrc) -> [CChar] in
                    return [CChar](UnsafeBufferPointer(start: ptrc, count: 256))
                  }))
                #else
                    var buffer = ptr.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.d_reclen), { (ptrc) -> [CChar] in
                      return [CChar](UnsafeBufferPointer(start: ptrc, count: Int(ent.pointee.d_namlen)))
                    })
                    buffer.append(0)
                    return String(validatingUTF8: buffer)
                #endif
            }
            if let fileName = fileName {
                results.append(fileName)
            }
        }
        return results
    }

    private func withStat<T>(_ closure: ((stat?) throws -> T)) throws -> T {
        return try self.withCString({
            var statBuffer = stat()
            if stat($0, &statBuffer) == 0 {
                return try closure(statBuffer)
            }
            if errno == ENOENT {
                return try closure(nil)
            }
            throw FileError.error(errno)
        })
    }
}
