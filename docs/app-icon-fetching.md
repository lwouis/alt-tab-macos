# 应用图标获取机制

## 概览

alt-tab-macos 通过 `NSRunningApplication.icon` 获取其他应用的高清图标，并针对 macOS 11+（Big Sur）及 macOS 26（Tahoe）的圆角图标设计进行了裁剪处理。

---

## 数据流

```
NSRunningApplication.icon (NSImage)
    │
    ▼
Application.appIconWithoutPadding(_:)
    │  1. 按 macOS 版本计算圆角 padding
    │  2. 请求高清位图 (cgImage(forProposedRect:))
    │  3. 裁剪 padding 区域
    │  4. CGContext 光栅化到目标尺寸
    │
    ▼
Application.icon: CGImage  ←── 缓存，整个生命周期只获取一次
    │
    └──→ TileView 渲染到 Switcher 界面
```

---

## 触发时机

```swift
// Application.swift
func fetchAppIcon() {
    guard icon == nil else { return }  // 已缓存则跳过
    BackgroundWork.screenshotsQueue.addOperation { [weak self] in
        let r = Application.appIconWithoutPadding(runningApplication.icon)
        DispatchQueue.main.async { self?.icon = r }
    }
}
```

- 在 `Window.init` 中调用，仅当该应用有窗口出现在 Switcher 中时才触发
- 运行在后台队列 `screenshotsQueue`（最大并发 8），不阻塞主线程
- 获取完成后回主线程赋值给 `Application.icon`

---

## 核心逻辑：`appIconWithoutPadding()`

```swift
// Application.swift:52-71
static func appIconWithoutPadding(_ icon: NSImage?) -> CGImage?
```

### 第一步：计算裁剪参数

macOS Big Sur 起，系统在应用图标外围添加了固定透明 padding（用于容纳圆角）。不同版本 padding 不同：

```swift
private static let appIconPadding: CGFloat = {
    if #available(macOS 26.0, *) { return 84 }   // Tahoe
    if #available(macOS 11.0, *) { return 24 }   // Big Sur ~ Sequoia
    return 0                                       // 更早版本，无 padding
}()
```

基于 1024×1024 参考图标定义，按目标显示尺寸等比缩放：

```swift
let finalWidth = max(TilesPanel.maxPossibleAppIconSize.width, ...)
let padding = appIconPadding * (finalWidth / (1024 - appIconPadding * 2))
let sourceWidth = finalWidth + padding * 2
```

### 第二步：从 NSImage 提取 CGImage

```swift
var proposedRect = CGRect(origin: .zero, size: NSSize(width: sourceWidth, height: sourceWidth))
let hints: [NSImageRep.HintKey: NSNumber] = [
    .interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)
]
guard let cgImage = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: hints)
else { return nil }
```

> **为什么只用 `cgImage(forProposedRect:)` 这一个 API？**
>
> 代码注释明确记录了尝试过的其他方案及其问题：
>
> | API | 问题 |
> |---|---|
> | `icon.cgImage(forProposedRect:) > context.draw` | ✅ **唯一稳定工作的方案** |
> | `icon.cgImage(forProposedRect:) > cgImage.draw` | 部分用户返回 nil（无法本地复现） |
> | `icon.draw()` | 部分用户返回 nil（无法本地复现） |
> | `icon.bestRepresentation() > bestRep.draw(in:)` | 部分用户返回 nil（无法本地复现） |
>
> `NSImage` 内部可能持有矢量（PDF）或位图（HEIC/PNG）多种表示，不同 API 对内部格式的处理兼容性不同。`cgImage(forProposedRect:context:hints:)` 由系统负责光栅化，兼容性最好。

### 第三步：裁剪圆角 padding

```swift
let paddingScaled = padding * (CGFloat(cgImage.width) / sourceWidth)
guard let image = cgImage.cropping(to: CGRect(
    x: paddingScaled, y: paddingScaled,
    width: CGFloat(cgImage.width) - paddingScaled * 2,
    height: CGFloat(cgImage.height) - paddingScaled * 2
).integral)
```

将 `padding` 按实际返回图像尺寸等比缩放后，用 `CGImage.cropping(to:)` 裁掉四周透明区域。

### 第四步：高质量光栅化到目标尺寸

```swift
guard let context = CGContext(
    data: nil,
    width: Int(finalWidth), height: Int(finalWidth),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        .union(.byteOrder32Little).rawValue  // ARGB 小端序
) else { return nil }
context.interpolationQuality = .high
context.draw(image, in: CGRect(origin: .zero, size: NSSize(width: finalWidth, height: finalWidth)))
return context.makeImage()
```

| 参数 | 说明 |
|---|---|
| `premultipliedFirst` + `byteOrder32Little` | ARGB 小端序，即内存布局为 B-G-R-A，是 macOS Core Graphics 的标准格式 |
| `interpolationQuality = .high` | 使用高质量双三次插值缩放，避免锯齿 |

---

## 涉及的 macOS 系统接口

### `NSRunningApplication.icon`（AppKit）

```swift
var icon: NSImage? { get }
```

- 返回应用的图标 `NSImage`
- 图标来源：应用 `Info.plist` 中的 `CFBundleIconFile` / `CFBundleIconName`，或 `Assets.xcassets` 中的 AppIcon
- 系统通常提供 **1024×1024** 或 **512×512** 的高清版本（Retina 下）
- `NSImage` 可能同时包含矢量（PDF）和位图（PNG/HEIC）多种表示，通过 `bestRepresentation(for:context:hints:)` 按需选择

### `NSImage.cgImage(forProposedRect:context:hints:)`（AppKit）

```swift
func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?,
             context referenceContext: NSGraphicsContext?,
             hints: [NSImageRep.HintKey: NSNumber]?) -> CGImage?
```

- 将 `NSImage` 光栅化为 `CGImage`
- `proposedDestRect`：输入期望尺寸，输出系统实际选择的尺寸（可能更接近某个预设 rep）
- `hints[.interpolation]`：控制缩放算法，`.high` = 双三次插值
- 这是 `NSImage` → `CGImage` 最可靠的转换方式（见上方对比表）

### `CGImage.cropping(to:)`（Core Graphics）

```swift
func cropping(to rect: CGRect) -> CGImage?
```

- 按指定矩形裁剪，返回新的 `CGImage`
- 坐标系原点在**左下角**（与 AppKit 的左上角相反）
- `.integral` 确保裁剪区域为整数像素，避免边缘模糊

### `CGContext`（Core Graphics）

```swift
CGContext(data:width:height:bitsPerComponent:bytesPerRow:space:bitmapInfo:)
```

- 创建位图上下文，用于将裁剪后的图像重新绘制到目标尺寸
- `CGContext.draw(_:in:)` 负责实际的缩放绘制
- `interpolationQuality` 控制缩放插值质量（`.default` / `.low` / `.medium` / `.high`）
