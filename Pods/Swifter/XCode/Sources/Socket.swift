//
//  Socket.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public enum SocketError: Error {
    case socketCreationFailed(String)
    case socketSettingReUseAddrFailed(String)
    case bindFailed(String)
    case listenFailed(String)
    case writeFailed(String)
    case getPeerNameFailed(String)
    case convertingPeerNameFailed
    case getNameInfoFailed(String)
    case acceptFailed(String)
    case recvFailed(String)
    case getSockNameFailed(String)
}

// swiftlint: disable identifier_name
open class Socket: Hashable, Equatable {

    let socketFileDescriptor: Int32
    private var shutdown = false

    public init(socketFileDescriptor: Int32) {
        self.socketFileDescriptor = socketFileDescriptor
    }

    deinit {
        close()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.socketFileDescriptor)
    }

    public func close() {
        if shutdown {
            return
        }
        shutdown = true
        Socket.close(self.socketFileDescriptor)
    }

    public func port() throws -> in_port_t {
        var addr = sockaddr_in()
        return try withUnsafePointer(to: &addr) { pointer in
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(socketFileDescriptor, UnsafeMutablePointer(OpaquePointer(pointer)), &len) != 0 {
                throw SocketError.getSockNameFailed(Errno.description())
            }
            let sin_port = pointer.pointee.sin_port
            #if os(Linux)
                return ntohs(sin_port)
            #else
                return Int(OSHostByteOrder()) != OSLittleEndian ? sin_port.littleEndian : sin_port.bigEndian
            #endif
        }
    }

    public func isIPv4() throws -> Bool {
        var addr = sockaddr_in()
        return try withUnsafePointer(to: &addr) { pointer in
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(socketFileDescriptor, UnsafeMutablePointer(OpaquePointer(pointer)), &len) != 0 {
                throw SocketError.getSockNameFailed(Errno.description())
            }
            return Int32(pointer.pointee.sin_family) == AF_INET
        }
    }

    public func writeUTF8(_ string: String) throws {
        try writeUInt8(ArraySlice(string.utf8))
    }

    public func writeUInt8(_ data: [UInt8]) throws {
        try writeUInt8(ArraySlice(data))
    }

    public func writeUInt8(_ data: ArraySlice<UInt8>) throws {
        try data.withUnsafeBufferPointer {
            try writeBuffer($0.baseAddress!, length: data.count)
        }
    }

    public func writeData(_ data: NSData) throws {
        try writeBuffer(data.bytes, length: data.length)
    }

    public func writeData(_ data: Data) throws {
        #if compiler(>=5.0)
        try data.withUnsafeBytes { (body: UnsafeRawBufferPointer) -> Void in
            if let baseAddress = body.baseAddress, body.count > 0 {
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                try self.writeBuffer(pointer, length: data.count)
            }
        }
        #else
        try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) -> Void in
            try self.writeBuffer(pointer, length: data.count)
        }
        #endif
    }

    private func writeBuffer(_ pointer: UnsafeRawPointer, length: Int) throws {
        var sent = 0
        while sent < length {
            #if os(Linux)
                let result = send(self.socketFileDescriptor, pointer + sent, Int(length - sent), Int32(MSG_NOSIGNAL))
            #else
                let result = write(self.socketFileDescriptor, pointer + sent, Int(length - sent))
            #endif
            if result <= 0 {
                throw SocketError.writeFailed(Errno.description())
            }
            sent += result
        }
    }

    /// Read a single byte off the socket. This method is optimized for reading
    /// a single byte. For reading multiple bytes, use read(length:), which will
    /// pre-allocate heap space and read directly into it.
    ///
    /// - Returns: A single byte
    /// - Throws: SocketError.recvFailed if unable to read from the socket
    open func read() throws -> UInt8 {
        var byte: UInt8 = 0

        #if os(Linux)
	    let count = Glibc.read(self.socketFileDescriptor as Int32, &byte, 1)
	    #else
	    let count = Darwin.read(self.socketFileDescriptor as Int32, &byte, 1)
	    #endif

        guard count > 0 else {
            throw SocketError.recvFailed(Errno.description())
        }
        return byte
    }

    /// Read up to `length` bytes from this socket
    ///
    /// - Parameter length: The maximum bytes to read
    /// - Returns: A buffer containing the bytes read
    /// - Throws: SocketError.recvFailed if unable to read bytes from the socket
    open func read(length: Int) throws -> [UInt8] {
        var buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: length)

        let bytesRead = try read(into: &buffer, length: length)

        let rv = [UInt8](buffer[0..<bytesRead])
        buffer.deallocate()
        return rv
    }

    static let kBufferLength = 1024

    /// Read up to `length` bytes from this socket into an existing buffer
    ///
    /// - Parameter into: The buffer to read into (must be at least length bytes in size)
    /// - Parameter length: The maximum bytes to read
    /// - Returns: The number of bytes read
    /// - Throws: SocketError.recvFailed if unable to read bytes from the socket
    func read(into buffer: inout UnsafeMutableBufferPointer<UInt8>, length: Int) throws -> Int {
        var offset = 0
        guard let baseAddress = buffer.baseAddress else { return 0 }

        while offset < length {
            // Compute next read length in bytes. The bytes read is never more than kBufferLength at once.
            let readLength = offset + Socket.kBufferLength < length ? Socket.kBufferLength : length - offset

            #if os(Linux)
            let bytesRead = Glibc.read(self.socketFileDescriptor as Int32, baseAddress + offset, readLength)
	        #else
	        let bytesRead = Darwin.read(self.socketFileDescriptor as Int32, baseAddress + offset, readLength)
	        #endif

            guard bytesRead > 0 else {
                throw SocketError.recvFailed(Errno.description())
            }

            offset += bytesRead
        }

        return offset
    }

    private static let CR: UInt8 = 13
    private static let NL: UInt8 = 10

    public func readLine() throws -> String {
        var characters: String = ""
        var index: UInt8 = 0
        repeat {
            index = try self.read()
            if index > Socket.CR { characters.append(Character(UnicodeScalar(index))) }
        } while index != Socket.NL
        return characters
    }

    public func peername() throws -> String {
        var addr = sockaddr(), len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        if getpeername(self.socketFileDescriptor, &addr, &len) != 0 {
            throw SocketError.getPeerNameFailed(Errno.description())
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) != 0 {
            throw SocketError.getNameInfoFailed(Errno.description())
        }
        return String(cString: hostBuffer)
    }

    public class func setNoSigPipe(_ socket: Int32) {
        #if os(Linux)
            // There is no SO_NOSIGPIPE in Linux (nor some other systems). You can instead use the MSG_NOSIGNAL flag when calling send(),
            // or use signal(SIGPIPE, SIG_IGN) to make your entire application ignore SIGPIPE.
        #else
            // Prevents crashes when blocking calls are pending and the app is paused ( via Home button ).
            var no_sig_pipe: Int32 = 1
            setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    public class func close(_ socket: Int32) {
        #if os(Linux)
            _ = Glibc.close(socket)
        #else
            _ = Darwin.close(socket)
        #endif
    }
}

public func == (socket1: Socket, socket2: Socket) -> Bool {
    return socket1.socketFileDescriptor == socket2.socketFileDescriptor
}
