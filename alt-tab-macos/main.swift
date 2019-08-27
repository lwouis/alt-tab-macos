import Foundation
import AppKit

autoreleasepool {
    let app = Application.shared
    app.delegate = app as? NSApplicationDelegate
    app.run()
}
