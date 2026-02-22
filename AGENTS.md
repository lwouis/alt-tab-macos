# macOS development
- Don't use xcode directly to develop
- Use pure swift 5.8 code to make the app. No interface builder. No SwiftUI.
- Aim for compact code. Within methods, don't have groups of statements separated with newlines. No inline comments for simple code. Instead, split statements into sub-methods.
- Use guard closes as much as possible to separate the happy-path under them
- Organize source files into folders. Folders should group files that change together, at the same pace (e.g. one feature)
- Favor low latency and responsiveness. Reuse objects, avoid wasting memory or I/O.

# Workflow
- Copy commands from ai/build.sh and run them, to confirm compilation works after you're done with implementing a change
