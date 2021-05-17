![Platform](https://img.shields.io/badge/Platform-Linux%20&%20OSX%20&%20tvOS-4BC51D.svg?style=flat)
![Swift](https://img.shields.io/badge/Swift-4.x,_5.0-4BC51D.svg?style=flat)
![Protocols](https://img.shields.io/badge/Protocols-HTTP%201.1%20&%20WebSockets-4BC51D.svg?style=flat)
[![CocoaPods](https://img.shields.io/cocoapods/v/Swifter.svg?style=flat)](https://cocoapods.org/pods/Swifter)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

### What is Swifter?

Tiny http server engine written in [Swift](https://developer.apple.com/swift/) programming language.

### Branches
`* stable` - lands on CocoaPods and others. Supports the latest non-beta XCode and SPM. Stable.

`* master` - stable branch plus experimental web-framework layer.

`* 2.0   ` - next version of Swifter (async IO). Experimental.


### How to start?
```swift
let server = HttpServer()
server["/hello"] = { .ok(.htmlBody("You asked for \($0)"))  }
server.start()
```

### How to load HTML by string?
```swift
let server = HttpServer()
server[path] = { request in
    return HttpResponse.ok(.text("<html string>"))
}
server.start()
```

### How to share files?
```swift
let server = HttpServer()
server["/desktop/:path"] = shareFilesFromDirectory("/Users/me/Desktop")
server.start()
```
### How to redirect?
```swift
let server = HttpServer()
server["/redirect"] = { request in
  return .movedPermanently("http://www.google.com")
}
server.start()
```
### How to HTML ?
```swift
let server = HttpServer()
server["/my_html"] = scopes { 
  html {
    body {
      h1 { inner = "hello" }
    }
  }
}
server.start()
```
### How to WebSockets ?
```swift
let server = HttpServer()
server["/websocket-echo"] = websocket(text: { session, text in
  session.writeText(text)
}, binary: { session, binary in
  session.writeBinary(binary)
})
server.start()
```
### CocoaPods? Yes.
```ruby
use_frameworks!

pod 'Swifter', '~> 1.5.0'
```

### Carthage? Also yes.
```
github "httpswift/swifter" ~> 1.5.0
```

### Swift Package Manager.
```swift
import PackageDescription

let package = Package(
    name: "MyServer",
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0"))
    ]
)
```

### Docker.
```
docker run -d -p 9080:9080 -v `pwd`:/Swifter -w /Swifter --name Swifter swift bash -c "swift run"
```

