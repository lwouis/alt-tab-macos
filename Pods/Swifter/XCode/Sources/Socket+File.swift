//
//  Socket+File.swift
//  Swifter
//
//  Created by Damian Kolakowski on 13/07/16.
//

import Foundation

#if os(iOS) || os(tvOS) || os (Linux)
// swiftlint:disable type_name function_parameter_count
    struct sf_hdtr { }

    private func sendfileImpl(_ source: UnsafeMutablePointer<FILE>, _ target: Int32, _: off_t, _: UnsafeMutablePointer<off_t>, _: UnsafeMutablePointer<sf_hdtr>, _: Int32) -> Int32 {
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let readResult = fread(&buffer, 1, buffer.count, source)
            guard readResult > 0 else {
                return Int32(readResult)
            }
            var writeCounter = 0
            while writeCounter < readResult {
                let writeResult = buffer.withUnsafeBytes { (ptr) -> Int in
                  let start = ptr.baseAddress! + writeCounter
                  let len = readResult - writeCounter
                  #if os(Linux)
                  return send(target, start, len, Int32(MSG_NOSIGNAL))
                  #else
                  return write(target, start, len)
                  #endif
                }
                guard writeResult > 0 else {
                    return Int32(writeResult)
                }
                writeCounter += writeResult
            }
        }
    }
#endif

extension Socket {

    public func writeFile(_ file: String.File) throws {
        var offset: off_t = 0
        var sf: sf_hdtr = sf_hdtr()

        #if os(iOS) || os(tvOS) || os (Linux)
        let result = sendfileImpl(file.pointer, self.socketFileDescriptor, 0, &offset, &sf, 0)
        #else
        let result = sendfile(fileno(file.pointer), self.socketFileDescriptor, 0, &offset, &sf, 0)
        #endif

        if result == -1 {
            throw SocketError.writeFailed("sendfile: " + Errno.description())
        }
    }
}
