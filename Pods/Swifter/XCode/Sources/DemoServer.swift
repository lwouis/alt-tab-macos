//
//  DemoServer.swift
//  Swifter
//
//  Copyright (c) 2014-2016 Damian Kołakowski. All rights reserved.
//

import Foundation

// swiftlint:disable function_body_length
public func demoServer(_ publicDir: String) -> HttpServer {

    print(publicDir)

    let server = HttpServer()

    server["/public/:path"] = shareFilesFromDirectory(publicDir)

    server["/files/:path"] = directoryBrowser("/")

    server["/"] = scopes {
        html {
            body {
                ul(server.routes) { service in
                    li {
                        a { href = service; inner = service }
                    }
                }
            }
        }
    }

    server["/magic"] = { .ok(.htmlBody("You asked for " + $0.path)) }

    server["/test/:param1/:param2"] = { request in
        scopes {
            html {
                body {
                    h3 { inner = "Address: \(request.address ?? "unknown")" }
                    h3 { inner = "Url: \(request.path)" }
                    h3 { inner = "Method: \(request.method)" }

                    h3 { inner = "Query:" }

                    table(request.queryParams) { param in
                        tr {
                            td { inner = param.0 }
                            td { inner = param.1 }
                        }
                    }

                    h3 { inner = "Headers:" }

                    table(request.headers) { header in
                        tr {
                            td { inner = header.0 }
                            td { inner = header.1 }
                        }
                    }

                    h3 { inner = "Route params:" }

                    table(request.params) { param in
                        tr {
                            td { inner = param.0 }
                            td { inner = param.1 }
                        }
                    }
                }
            }
        }(request)
    }

    server.GET["/upload"] = scopes {
        html {
            body {
                form {
                    method = "POST"
                    action = "/upload"
                    enctype = "multipart/form-data"

                    input { name = "my_file1"; type = "file" }
                    input { name = "my_file2"; type = "file" }
                    input { name = "my_file3"; type = "file" }

                    button {
                        type = "submit"
                        inner = "Upload"
                    }
                }
            }
        }
    }

    server.POST["/upload"] = { request in
        var response = ""
        for multipart in request.parseMultiPartFormData() {
            guard let name = multipart.name, let fileName = multipart.fileName else { continue }
            response += "Name: \(name) File name: \(fileName) Size: \(multipart.body.count)<br>"
        }
        return HttpResponse.ok(.htmlBody(response))
    }

    server.GET["/login"] = scopes {
        html {
            head {
                script { src = "http://cdn.staticfile.org/jquery/2.1.4/jquery.min.js" }
                stylesheet { href = "http://cdn.staticfile.org/twitter-bootstrap/3.3.0/css/bootstrap.min.css" }
            }
            body {
                h3 { inner = "Sign In" }

                form {
                    method = "POST"
                    action = "/login"

                    fieldset {
                        input { placeholder = "E-mail"; name = "email"; type = "email"; autofocus = "" }
                        input { placeholder = "Password"; name = "password"; type = "password"; autofocus = "" }
                        a {
                            href = "/login"
                            button {
                                type = "submit"
                                inner = "Login"
                            }
                        }
                    }

                }
                javascript {
                    src = "http://cdn.staticfile.org/twitter-bootstrap/3.3.0/js/bootstrap.min.js"
                }
            }
        }
    }

    server.POST["/login"] = { request in
        let formFields = request.parseUrlencodedForm()
        return HttpResponse.ok(.htmlBody(formFields.map({ "\($0.0) = \($0.1)" }).joined(separator: "<br>")))
    }

    server["/demo"] = scopes {
        html {
            body {
                center {
                    h2 { inner = "Hello Swift" }
                    img { src = "https://devimages.apple.com.edgekey.net/swift/images/swift-hero_2x.png" }
                }
            }
        }
    }

    server["/raw"] = { _ in
        return HttpResponse.raw(200, "OK", ["XXX-Custom-Header": "value"], { try $0.write([UInt8]("test".utf8)) })
    }

    server["/redirect/permanently"] = { _ in
        return .movedPermanently("http://www.google.com")
    }

    server["/redirect/temporarily"] = { _ in
        return .movedTemporarily("http://www.google.com")
    }

    server["/long"] = { _ in
        var longResponse = ""
        for index in 0..<1000 { longResponse += "(\(index)),->" }
        return .ok(.htmlBody(longResponse))
    }

    server["/wildcard/*/test/*/:param"] = { request in
        return .ok(.htmlBody(request.path))
    }

    server["/stream"] = { _ in
        return HttpResponse.raw(200, "OK", nil, { writer in
            for index in 0...100 {
                try writer.write([UInt8]("[chunk \(index)]".utf8))
            }
        })
    }

    server["/websocket-echo"] = websocket(text: { (session, text) in
        session.writeText(text)
    }, binary: { (session, binary) in
        session.writeBinary(binary)
    }, pong: { (_, _) in
        // Got a pong frame
    }, connected: { _ in
        // New client connected
    }, disconnected: { _ in
        // Client disconnected
    })

    server.notFoundHandler = { _ in
        return .movedPermanently("https://github.com/404")
    }

    server.middleware.append { request in
        print("Middleware: \(request.address ?? "unknown address") -> \(request.method) -> \(request.path)")
        return nil
    }

    return server
}
