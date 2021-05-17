//
//  HttpHandlers+Files.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

public func shareFile(_ path: String) -> ((HttpRequest) -> HttpResponse) {
    return { _ in
        if let file = try? path.openForReading() {
            return .raw(200, "OK", [:], { writer in
                try? writer.write(file)
                file.close()
            })
        }
        return .notFound
    }
}

public func shareFilesFromDirectory(_ directoryPath: String, defaults: [String] = ["index.html", "default.html"]) -> ((HttpRequest) -> HttpResponse) {
    return { request in
        guard let fileRelativePath = request.params.first else {
            return .notFound
        }
        if fileRelativePath.value.isEmpty {
            for path in defaults {
                if let file = try? (directoryPath + String.pathSeparator + path).openForReading() {
                    return .raw(200, "OK", [:], { writer in
                        try? writer.write(file)
                        file.close()
                    })
                }
            }
        }
        let filePath = directoryPath + String.pathSeparator + fileRelativePath.value

        if let file = try? filePath.openForReading() {
            let mimeType = fileRelativePath.value.mimeType()
            var responseHeader: [String: String] = ["Content-Type": mimeType]

            if let attr = try? FileManager.default.attributesOfItem(atPath: filePath),
                let fileSize = attr[FileAttributeKey.size] as? UInt64 {
                responseHeader["Content-Length"] = String(fileSize)
            }

            return .raw(200, "OK", responseHeader, { writer in
                try? writer.write(file)
                file.close()
            })
        }
        return .notFound
    }
}

public func directoryBrowser(_ dir: String) -> ((HttpRequest) -> HttpResponse) {
    return { request in
        guard let (_, value) = request.params.first else {
            return HttpResponse.notFound
        }
        let filePath = dir + String.pathSeparator + value
        do {
            guard try filePath.exists() else {
                return .notFound
            }
            if try filePath.directory() {
                var files = try filePath.files()
                files.sort(by: {$0.lowercased() < $1.lowercased()})
                return scopes {
                    html {
                        body {
                            table(files) { file in
                                tr {
                                    td {
                                        a {
                                            href = request.path + "/" + file
                                            inner = file
                                        }
                                    }
                                }
                            }
                        }
                    }
                    }(request)
            } else {
                guard let file = try? filePath.openForReading() else {
                    return .notFound
                }
                return .raw(200, "OK", [:], { writer in
                    try? writer.write(file)
                    file.close()
                })
            }
        } catch {
            return HttpResponse.internalServerError
        }
    }
}
