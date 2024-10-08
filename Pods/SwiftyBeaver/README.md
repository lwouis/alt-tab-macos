<p align="center"><a href="https://swiftybeaver.com"><img src="https://cloud.githubusercontent.com/assets/564725/19889302/73b1ee84-a034-11e6-8753-2d060502397c.jpg" style="width: 888px;" alt="SwiftyBeaver"></a><br/><b>Colorful</b>, flexible, <b>lightweight</b> logging for Swift 3, Swift 4 & <b>Swift 5</b>.<br/>Great for <b>development & release</b> with support for Console, File & cloud platforms.<br/>Log <b>during release</b> to the conveniently built-in SwiftyBeaver Platform, the <b>dedicated Mac App</b> & <b>Elasticsearch</b>!<br/><br/><a href="http://docs.swiftybeaver.com">Docs</a> | <a href="https://swiftybeaver.com">Website</a> | <a href="https://twitter.com/SwiftyBeaver">Twitter</a> | <a href="#privacy">Privacy</a> | <a href="https://github.com/SwiftyBeaver/SwiftyBeaver/blob/master/LICENSE">License</a><br/></p>

<p align="center"><a href="https://swift.org" target="_blank"><img src="https://img.shields.io/badge/Language-Swift%203,%204%20&%205-orange.svg" alt="Language Swift 2, 3, 4 & 5"></a> <a href="https://circleci.com/gh/SwiftyBeaver/SwiftyBeaver" target="_blank"><img src="https://circleci.com/gh/SwiftyBeaver/SwiftyBeaver/tree/master.svg?style=shield" alt="CircleCI"/></a><br/><p>

----

<br/>

### During Development: Colored Logging to Xcode Console

<img src="https://cloud.githubusercontent.com/assets/564725/18608323/ac065a98-7ce6-11e6-8e1b-2a062d54a1d5.png" width="608">

[Learn more](http://docs.swiftybeaver.com/article/9-log-to-xcode-console) about colored logging to Xcode 8 Console with Swift 3, 4 & 5. For Swift 2.3 [use this Gist](https://gist.github.com/skreutzberger/7c396573796473ed1be2c6d15cafed34). **No need to hack Xcode 8 anymore** to get color. You can even customize the log level word (ATTENTION instead of ERROR maybe?), the general amount of displayed data and if you want to use the 💜s or replace them with something else 😉

<br/>

### During Development: Colored Logging to File

<img src="https://cloud.githubusercontent.com/assets/564725/18608325/b7ecd4c2-7ce6-11e6-829b-7f8f9fe6ef2f.png" width="738">

[Learn more](http://docs.swiftybeaver.com/article/10-log-to-file) about logging to file which is great for Terminal.app fans or to store logs on disk.

<br/>


### On Release: Encrypted Logging to SwiftyBeaver Platform

<img src="https://cloud.githubusercontent.com/assets/564725/14281408/38d6a6ba-fb39-11e5-9584-34e3679bb1c5.jpg" width="700">

[Learn more](http://docs.swiftybeaver.com/article/11-log-to-swiftybeaver-platform) about logging to the SwiftyBeaver Platform **during release!**

<br/>


### Browse, Search & Filter via Mac App

![swiftybeaver-demo1](https://cloud.githubusercontent.com/assets/564725/14846071/218c0646-0c62-11e6-92cb-e6e963b68724.gif)

Conveniently access your logs during development & release with our [free Mac App](https://swiftybeaver.com).

<br/>


### On Release: Enterprise-ready Logging to Your Elasticsearch & Kibana (on-premise)

<img src="https://user-images.githubusercontent.com/564725/34486363-dc501aec-efcf-11e7-92b2-1163cca9e7aa.jpg" width="700">

[Learn more](http://docs.swiftybeaver.com/article/34-enterprise-quick-start-via-docker) about **legally compliant**, end-to-end encrypted logging to Elasticsearch with **SwiftyBeaver Enterprise**. Install via Docker or manual, fully-featured free trial included!

<br/>

### Google Cloud & More

You can fully customize your log format, turn it into JSON, or create your own destinations. For example our [Google Cloud Destination](https://github.com/SwiftyBeaver/SwiftyBeaver/blob/master/Sources/GoogleCloudDestination.swift) is just another customized logging format which adds the powerful functionality of automatic server-side Swift logging when hosted on Google Cloud Platform.

<br/>

----

<br/>
<br/>

## Installation

- For **Swift 4 & 5** install the latest SwiftyBeaver version
- For **Swift 3** install SwiftyBeaver 1.8.4
- For **Swift 2** install SwiftyBeaver 0.7.0

<br/>

### Carthage

You can use [Carthage](https://github.com/Carthage/Carthage) to install SwiftyBeaver by adding that to your Cartfile:

Swift 4 & 5:
``` Swift
github "SwiftyBeaver/SwiftyBeaver"
```


Swift 3:
``` Swift
github "SwiftyBeaver/SwiftyBeaver" ~> 1.8.4
```

Swift 2:
``` Swift
github "SwiftyBeaver/SwiftyBeaver" ~> 0.7
```

<br/>

### Swift Package Manager

For [Swift Package Manager](https://swift.org/package-manager/) add the following package to your Package.swift file. Just Swift 4 & 5 are supported:

``` Swift
.package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "1.9.0")),
```

<br/>

### CocoaPods

To use [CocoaPods](https://cocoapods.org) just add this to your Podfile:

Swift 4 & 5:
``` Swift
pod 'SwiftyBeaver'
```

Swift 3:
``` Ruby
target 'MyProject' do
  use_frameworks!

  # Pods for MyProject
  pod 'SwiftyBeaver', '~> 1.8.4'
end
```

Swift 2:
``` Ruby
target 'MyProject' do
  use_frameworks!

  # Pods for MyProject
  pod 'SwiftyBeaver', '~> 0.7'
end

post_install do |installer|
  installer.pods_project.build_configurations.each do |config|
    # Configure Pod targets for Xcode 8 with Swift 2.3
    config.build_settings['SWIFT_VERSION'] = '2.3'
  end
end
```

<br/>
<br/>

## Usage

Add that near the top of your `AppDelegate.swift` to be able to use SwiftyBeaver in your whole project.

``` Swift
import SwiftyBeaver
let log = SwiftyBeaver.self

```

At the the beginning of your `AppDelegate:didFinishLaunchingWithOptions()` add the SwiftyBeaver log destinations (console, file, etc.), optionally adjust the [log format](http://docs.swiftybeaver.com//article/20-custom-format) and then you can already do the following log level calls globally:

``` Swift
// add log destinations. at least one is needed!
let console = ConsoleDestination()  // log to Xcode Console
let file = FileDestination()  // log to default swiftybeaver.log file
let cloud = SBPlatformDestination(appID: "foo", appSecret: "bar", encryptionKey: "123") // to cloud

// use custom format and set console output to short time, log level & message
console.format = "$DHH:mm:ss$d $L $M"
// or use this for JSON output: console.format = "$J"

// add the destinations to SwiftyBeaver
log.addDestination(console)
log.addDestination(file)
log.addDestination(cloud)

// Now let’s log!
log.verbose("not so important")  // prio 1, VERBOSE in silver
log.debug("something to debug")  // prio 2, DEBUG in green
log.info("a nice information")   // prio 3, INFO in blue
log.warning("oh no, that won’t be good")  // prio 4, WARNING in yellow
log.error("ouch, an error did occur!")  // prio 5, ERROR in red

// log anything!
log.verbose(123)
log.info(-123.45678)
log.warning(Date())
log.error(["I", "like", "logs!"])
log.error(["name": "Mr Beaver", "address": "7 Beaver Lodge"])

// optionally add context to a log message
console.format = "$L: $M $X"
log.debug("age", 123)  // "DEBUG: age 123"
log.info("my data", context: [1, "a", 2]) // "INFO: my data [1, \"a\", 2]"

```

<br/>
<br/>

## Server-side Swift

We ❤️ server-side Swift 4 & 5 and SwiftyBeaver supports it **out-of-the-box**! Try for yourself and run SwiftyBeaver inside a Ubuntu Docker container. Just install Docker and then go to your the project folder on macOS or Ubuntu and type:

```shell
# create docker image, build SwiftyBeaver and run unit tests
swift build --clean && docker build --rm -t swiftybeaver .

# optionally log into container to run Swift CLI and do more stuff
docker run --rm -it --privileged=true -v $PWD:/app swiftybeaver
```

Best: for the popular server-side Swift web framework [Vapor](https://github.com/vapor/vapor) you can use **[our Vapor logging provider](https://github.com/SwiftyBeaver/SwiftyBeaver-Vapor)** which makes server logging awesome again 🙌

<br/>
<br/>

## Documentation

**Getting Started:**

- [Features](http://docs.swiftybeaver.com/article/7-introduction)
- [Installation](http://docs.swiftybeaver.com/article/5-installation)
- [Basic Setup](http://docs.swiftybeaver.com/article/6-basic-setup)

**Logging Destinations:**

- [Colored Logging to Xcode Console](http://docs.swiftybeaver.com/article/9-log-to-xcode-console)
- [Colored Logging to File](http://docs.swiftybeaver.com/article/10-log-to-file)
- [Encrypted Logging & Analytics to SwiftyBeaver Platform](http://docs.swiftybeaver.com/article/11-log-to-swiftybeaver-platform)
- [Encrypted Logging & Analytics to Elasticsearch & Kibana](http://docs.swiftybeaver.com/article/34-enterprise-quick-start-via-docker)


**Advanced Topics:**

- [Custom Format & Context](http://docs.swiftybeaver.com/article/20-custom-format)
- [Filters](http://docs.swiftybeaver.com/article/21-filters)

**Stay Informed:**

- [Official Website](https://swiftybeaver.com))
- [On Twitter](https://twitter.com/SwiftyBeaver)

<br/>
<br/>

## Privacy

**SwiftyBeaver is not collecting any data without you as a developer knowing about it**. That's why it is **open-source** and developed in a simple way to be easy to inspect and check what it is actually doing under the hood.

The only sending to servers is done if you use the `SBPlatformDestination`. That destination is meant for production logging and on default it sends your logs plus additional device information **end-to-end encrypted** to our cloud service. Our cloud service **can not decrypt the data**.

Instead, you install our Mac App and that Mac App downloads the encrypted logs from the cloud and decrypts and shows them to you. Additionally, the Mac App stores all data that it downloads in a local SQLite database file on your computer so that you actually "physically" own your data.

The business model of the SwiftyBeaver cloud service is to provide the most secure logging solution in the market. On purpose we do not provide a web UI for you because it would require us to store your encryption key on our servers.

**Only you can see the logging and device data** which is sent from your users' devices. Our servers just see encrypted data and do not know your decryption key.

SwiftyBeaver is **fully GDPR compliant** due to its focus on encryption and transparency in what data is collected and also meets **Apple’s latest requirements** on the privacy of 3rd party frameworks.

Our Enterprise offering is an even more secure solution where you are not using anymore our cloud service and Mac App but you send your end-to-end encrypted logs directly to your own servers and you store them in your Elasticsearch cluster. The **Enterprise offering is used by health tech** and governmental institutions which require the highest level of privacy and security.

<br/>
<br/>

## End-to-End Encryption

SwiftyBeaver is using symmetric AES256CBC encryption in the `SBPlatformDestination` destination. No other officially supported destination uses encryption. 

The encryption used in the `SBPlatformDestination` destination is end-to-end. The open-source SwiftyBeaver logging framework symmetrically encrypts all logging data on your client's device inside your app (iPhone, iPad, ...) before it is sent to the SwiftyBeaver Crypto Cloud. The decryption is done on your Mac which has the SwiftyBeaver Mac App installed. All logging data stays encrypted in the SwiftyBeaver Crypto Cloud due to the lack of the password.

You are using the encryption at your own risk. SwiftyBeaver’s authors and contributors do not take over any guarantee about the absence of potential security or cryptopgraphy issues, weaknesses, etc.; please also read the LICENSE file for details. Also if you are interested in cryptography in general, please have a look at the file AES256CBC.swift to learn more about the cryptographical implementation.
<br/>
<br/>

## License

SwiftyBeaver Framework is released under the [MIT License](https://github.com/SwiftyBeaver/SwiftyBeaver/blob/master/LICENSE).
