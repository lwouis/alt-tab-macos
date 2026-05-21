# 窗口状态层

## 模块职责

窗口状态层是 AltTab 的核心数据引擎，负责 macOS 系统上所有窗口和应用的发现、建模、过滤、排序和聚焦。它构建在 macOS 三大窗口 API 之上——Accessibility (AX) 框架、私有 SkyLight (CGS) 框架、以及 ScreenCaptureKit——并将这些底层 API 的原始信息统一为 `Window` / `Application` 对象图，供上层 UI 直接消费。

该层的设计围绕两个核心原则：
1. **防御性冗余**：不依赖任何单一 API 通道，通过 AX + CGS + CG 三路交叉验证确保窗口列表的完整性。
2. **最小主线程占用**：所有阻塞式 IPC 调用（AX 查询、CGS 查询、截图捕获）均通过 `AXCallScheduler` 或 `BackgroundWork` 队列调度到后台线程，主线程仅做结果合并。

---

## 核心组件

### Window（窗口模型）

**文件**：`src/switcher/state/Window.swift`

`Window` 是整个应用的核心数据单元，代表一个被发现的窗口（或无窗口应用的占位符）。每个窗口实例持有三类信息：

- **身份标识**：`cgWindowId: CGWindowID?`（系统级窗口 ID）、`id: String`（内部标识，格式为 `"wid-\(wid)"` 或 `"pid-\(pid)"`）、`axUiElement: AXUIElement?`（AX 引用）
- **状态属性**：`isFullscreen`、`isMinimized`、`isHidden`（委托给 `application.isHidden`）、`isTabbed`、`isOnAllSpaces`、`isInvisible`（ghost 窗口标记）
- **空间信息**：`spaceIds: [CGSSpaceID]`、`spaceIndexes: [SpaceIndex]`、`screenId: ScreenUuid?`、`position: CGPoint?`、`size: CGSize?`
- **排序信息**：`lastFocusOrder`（基于窗口 z-order 的聚焦顺序）、`creationOrder`（基于全局递增计数器的创建顺序）

**双构造器设计**：
- `init(_ axUiElement: Application, _ wid: ...)` — 正常窗口构造，绑定 AXUIElement，订阅 AX 通知，初始化 space 信息
- `init(_ application: Application)` — 无窗口应用占位构造（`cgWindowId == nil`，`id = "pid-\(pid)"`）

**AX 观察者生命周期管理**：
`observeEvents()` 通过 `AXObserverCreate` 创建观察者，订阅六种通知（`kAXUIElementDestroyedNotification`、`kAXTitleChangedNotification`、`kAXWindowMiniaturizedNotification`、`kAXWindowDeminiaturizedNotification`、`kAXWindowResizedNotification`、`kAXWindowMovedNotification`），将 `AXObserverGetRunLoopSource` 添加到 `BackgroundWork.accessibilityEventsThread.runLoop`。对应的 `releaseAxObserver()` 在窗口移除时显式 `CFRunLoopRemoveSource` 并置 nil，防止长期运行会话中虚拟内存膨胀（issue #5612）。

**Ghost 窗口检测**：
`recomputeIsInvisible()` 使用本地信号判断：`spaceIds.isEmpty && !isTabbed && !isMinimized && !isHidden`。这捕获了 Joplin/Sprig 等 Electron 窗口在创建时即不可见的情况（CGS 已完全丢失其 WID）。对 alpha=0 的窗口（如 Outlook 提醒），需要 `Applications.refreshIsInvisible()` 的批量 CGS 交叉验证来捕获。

**Space 更新**：
`updateSpacesAndScreen(_ windowToSpacesMap:)` 支持两种模式：
- 传入预构建的 `windowToSpacesMap`（批量优化路径，由 `Spaces.buildWindowToSpacesMap()` 生成）
- 逐窗口调用 `cgWindowId.spaces()`（单窗口路径，内部调用 `CGSCopySpacesForWindows`）

对于 tabbed 窗口，当其 `spaceIds` 为空时，使用 `TabGroup.activeTabSibling(of:)` 的 space 信息作为回退。

### Application（应用模型）

**文件**：`src/switcher/state/Application.swift`

`Application` 继承自 `NSObject`，封装一个 `NSRunningApplication` 及其 AX 交互上下文。

核心属性：
- `runningApplication: NSRunningApplication` — 系统运行应用引用
- `axUiElement: AXUIElement?` — 应用的 AX 根元素（`AXUIElementCreateApplication(pid)`）
- `axObserver: AXObserver?` — AX 事件观察者
- `isReallyFinishedLaunching: Bool` — 区分 `NSRunningApplication.isFinishedLaunching` 与实际可订阅状态
- `focusedWindow: Window?` — 该应用当前聚焦的窗口引用
- `icon: CGImage?` — 裁剪 padding 后的应用图标
- `dockLabel: String?` — Dock 徽章标签

**应用图标处理**（`appIconWithoutPadding`）：
针对 macOS 11 Big Sur 的圆角图标引入的 padding，以及 macOS 26 Tahoe 进一步增大的 padding，使用 `appIconPadding` 静态常量计算裁剪区域。通过 `icon.cgImage(forProposedRect:)` 获取像素，`CGImage.cropping(to:)` 裁剪，最终 `CGContext.draw` 缩放到目标尺寸。

**生命周期管理**：
- `observeEventsIfEligible()` — 仅当 `activationPolicy != .prohibited` 且 `!isReallyFinishedLaunching` 时订阅
- KVO 观察者监听 `isFinishedLaunching` 和 `activationPolicy` 变化
- `isReallyFinishedLaunching` 在首次 AX 订阅成功后设为 true，触发 `manuallyUpdateWindows` 检查

### Windows（窗口集合管理）

**文件**：`src/switcher/state/Windows.swift`

`Windows` 是纯静态类，管理窗口的全局列表和所有过滤/排序逻辑。

**核心数据结构**：
- `static var list = [Window]()` — 有序窗口数组，是整个应用的数据主轴
- `private(set) static var byWindowId = [CGWindowID: Window]()` — `CGWindowID → Window` 哈希表，O(1) 查找
- `lastFocusOrder` — 每个窗口维护的 z-order 相对排序值，0 表示最近聚焦

**窗口发现与去重**（`findOrCreate`）：
```swift
static func findOrCreate(_ windowAxUiElement, _ wid, _ app, _ level, ...) -> (Window?, Bool)
```
查找顺序：先 `byWindowId[wid]` O(1) 哈希查找，再 `list.first { $0.isEqualRobust(...) }` 兜底。`isEqualRobust` 同时比较 AXUIElement 引用和 CGWindowID，应对窗口被系统回收后 WID 变为 `-1` 的情况。

**排序系统**（`sort()`）：
支持五种排序模式（由 `Preferences.windowOrder` 控制）：
- `.recentlyFocused` — 按 `lastFocusOrder` 升序（默认）
- `.recentlyCreated` — 按 `creationOrder` 降序
- `.alphabetical` — 按应用名 + 窗口标题字典序
- `.space` — 按 Space 索引排序，"所有 Space" 窗口优先

搜索激活时，先按 `Search.matches` 布尔值分区，再按 `Search.relevance` 分数排序，同分则按 `lastFocusOrder` 兜底。

**`lastFocusOrder` 维护**：
`updateLastFocusOrder` 实现增量更新：仅调整 `oldFocusOrder` 以下的窗口顺序，新聚焦窗口置 0，其余递增。`sortByLevel()` 则从 `Spaces.windowsInSpaces` 的 z-order 完全重建。

**窗口过滤**（`refreshIfWindowShouldBeShownToTheUser`）：
综合判断条件包括：`isInvisible`、异常规则（`exceptions` 基于 bundleIdentifier 前缀匹配）、应用活跃状态、隐藏窗口/全屏窗口/最小化窗口/无窗口应用的显示策略、Space 过滤、屏幕过滤、标签分组。所有偏好值通过 `WindowFilters.snapshot()` 一次性快照，避免 N 窗口 x M 偏好的重复计算。

### Applications（应用集合管理）

**文件**：`src/switcher/state/Applications.swift`

`Applications` 管理应用的全局列表和窗口发现调度。

**窗口发现流程**：
1. `initialDiscovery()` → `addInitialRunningApplications()` 遍历 `NSWorkspace.shared.runningApplications`
2. 每个应用通过 `Application.init` → `observeEventsIfEligible()` → `observeEvents()` 订阅 AX 通知
3. 首次订阅成功后触发 `manuallyUpdateWindows`，通过 `axUiElement.allWindows(pid)` 双通道获取窗口
4. `manuallyRefreshAllWindows()` 在面板显示时定期执行：`removeZombieWindows` → `addMissingWindows` → `reviewExistingWindows` → `refreshIsInvisible`

**Zombie 窗口回收**（`removeZombieWindows`）：
使用 `CGWindowListCreateDescriptionFromArray` 批量验证 WID 是否仍存活。在后台线程执行 IPC，主线程回收差异。

**Ghost 窗口批量检测**（`refreshIsInvisible`）：
获取两个 CGS 窗口集合（含/不含不可见窗口），对每个窗口应用多信号消歧逻辑（详见"窗口发现策略"章节）。

**Dock 徽章刷新**（`refreshBadgesAsync`）：
通过 AX 查询 Dock 应用的 `kAXChildrenAttribute`，找到 `kAXListRole` 下的 `kAXApplicationDockItemSubrole` 元素，读取 `kAXStatusLabelAttribute`。

### Spaces（Desktop Spaces 管理）

**文件**：`src/switcher/state/Spaces.swift`

`Spaces` 封装了 macOS 虚拟桌面（Space）的全部管理逻辑，完全基于私有 SkyLight API。

**核心数据结构**：
- `idsAndIndexes: [(CGSSpaceID, SpaceIndex)]` — 所有 Space 的有序列表
- `visibleSpaces: [CGSSpaceID]` — 当前可见的 Space（每屏幕一个）
- `screenSpacesMap: [ScreenUuid: [CGSSpaceID]]` — 屏幕到 Space 的映射
- `currentSpaceId: CGSSpaceID` / `currentSpaceIndex: SpaceIndex` — 主屏幕当前 Space

**Space 刷新**（`refreshAllIdsAndIndexes`）：
调用 `CGSCopyManagedDisplaySpaces(CGS_CONNECTION)` 返回的嵌套字典结构，解析每屏幕的 Space 列表。注意：当"显示器具有单独的 Space"未勾选时，多屏幕只报告一个 Space 条目，且 `Display Identifier` 为 `"Main"`。

**当前 Space 检测**（`updateCurrentSpace`）：
通过 `CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, mainScreenUuid)` 获取主屏幕当前 Space ID，然后在 `idsAndIndexes` 中查找对应索引。

### Screens（屏幕管理）

**文件**：`src/switcher/state/Screens.swift`

`Screens` 管理多屏幕配置，维护 `ScreenUuid → NSScreen` 映射。

- `all: [ScreenUuid: NSScreen]` — 屏幕注册表
- `preferred: NSScreen` — AltTab 面板应显示的目标屏幕（根据偏好设置：鼠标所在屏幕 / 活跃屏幕 / 菜单栏所在屏幕）
- `cachedUuid()` — 通过 `CGDisplayCreateUUIDFromDisplayID` 获取屏幕 UUID，结果缓存在 `uuidCache` 避免重复 IPC
- `withActiveMenubar()` — 通过 `CGSCopyActiveMenuBarDisplayIdentifier` 找到有活跃菜单栏的屏幕

### TabGroup（标签窗口组）

**文件**：`src/switcher/state/TabGroup.swift`

`TabGroup` 处理 macOS 原生窗口标签（OS-level tabs）的检测和状态管理。

**标签检测**：
通过 AX 的 `kAXChildrenAttribute` 查找 `AXTabGroup` 角色的子元素，再遍历其 `kAXChildrenAttribute` 获取 `AXTabButton` 子角色的标签按钮。每个标签按钮的 `kAXTitleAttribute` 对应窗口标题。实现位于 `AXUIElement.tabGroupInfo()`。

**标签状态管理**（`updateState`）：
- 通过标题匹配将 AX 发现的标签标题映射回 `Window` 对象
- 设置 `isTabbed = true` 和 `tabbedSiblingWids` 数组
- 将活跃标签的 `spaceIds`/`spaceIndexes`/`isOnAllSpaces` 传播到非活跃标签
- 清理不再属于任何标签组的窗口的 `tabbedSiblingWids`

**限制**：由于 `_AXUIElementGetWindow` 对标签按钮返回的是父窗口 WID 而非各个标签的独立 WID，标签匹配依赖标题比较，可能因标题重复产生误匹配。

### WindowThumbnails（窗口缩略图）

**文件**：`src/switcher/state/WindowThumbnails.swift`

`WindowThumbnails` 是截图调度的入口，负责将截图请求分发到对应的捕获后端。

**双路径截图**：
```swift
if #available(macOS 14.0, *), ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
    WindowCaptureScreenshots.oneTimeScreenshots(...)
} else {
    WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(...)
}
```
- **ScreenCaptureKit 路径**（macOS 14+，跳过 macOS 15）：使用 `SCScreenshotManager.captureSampleBuffer`，通过 `SCShareableContent.getExcludingDesktopWindows` 获取 `SCWindow` 列表
- **私有 API 路径**（macOS 10.13+ 或 macOS 15 回退）：使用 `CGSHWCaptureWindowList` 直接截图

**预览面板**（`previewSelectedIfNeeded`）：
当选中窗口变化时，通过 `PreviewPanel.show` 在 AltTab 面板旁显示窗口预览。

### ApplicationDiscriminator（应用过滤规则）

**文件**：`src/switcher/state/ApplicationDiscriminator.swift`

`isActualApplication` 过滤非应用进程：
1. **XPC 过滤**：通过 `GetProcessForPID` + `GetProcessInformation` 获取 `ProcessInfoRec.processType`，过滤 `"XPC!"` 类型
2. **Zombie 过滤**：调用 `pid_t.isZombie()` 检测僵尸进程
3. **白名单例外**：`com.apple.Passwords`（XPC 但需显示）、Android 模拟器（通过 KERN_PROCARGS 匹配 `qemu-system` 路径）

### WindowDiscriminator（窗口过滤规则）

**文件**：`src/switcher/state/WindowDiscriminator.swift`

`isActualWindow` 实施多层过滤：
1. **基础过滤**：`wid == 0` 拒绝、size 为 nil 拒绝、尺寸 < 100x50 拒绝
2. **Subrole 检查**：接受 `kAXStandardWindowSubrole` 和 `kAXDialogSubrole`
3. **应用特例**：约 20 个应用的硬编码规则（Books 的 `AXUnknown`、IINA 的浮动窗口、Steam 的 `AXUnknown`、Firefox 全屏视频、CrossOver/Wine 窗口、scrcpy 常驻置顶窗口等）
4. **附加过滤**：JetBrains 无标题面板、Fusion360 无标题侧面板、ColorSlurp 非 `AXStandardWindowSubrole` 等

---

## 技术要点

### 双通道混合窗口发现策略

`AXUIElement.allWindows(_ pid:)` 组合两个互补通道：

**通道 A — AX kAXWindowsAttribute**：
```swift
private func windows() throws -> [AXUIElement]
```
通过 `AXUIElementCopyMultipleAttributeValues(appElement, [kAXWindowsAttribute], ...)` 获取。返回当前 Space 上的窗口，**不返回其他 Space 的窗口**。

**通道 B — 暴力枚举 _AXUIElementCreateWithRemoteToken**：
```swift
private static func windowsByBruteForce(_ pid: pid_t) -> [AXUIElement]
```
构造 20 字节的 `remoteToken` 结构：
- Byte 0-3：`pid_t`（进程 ID）
- Byte 4-7：`Int32(0)`
- Byte 8-11：`0x636f636f`（常量 magic number）
- Byte 12-19：`AXUIElementID`（`UInt64`，从 0 递增）

对 `AXUIElementID` 从 0 到 999 逐个构造 `AXUIElement`，通过 `_AXUIElementCreateWithRemoteToken(data)` 验证其 subrole 是否为 `kAXStandardWindowSubrole` 或 `kAXDialogSubrole`。设置 100ms 超时上限。

**通道 C — CGWindowListCopyWindowInfo 交叉验证**：
在 `Applications.refreshIsInvisible` 和 `removeZombieWindows` 中使用：
- `Spaces.windowsInSpaces`（内部调用 `CGSCopyWindowsWithOptionsAndTags`）批量获取窗口列表
- `CGWindowListCreateDescriptionFromArray` 验证 WID 是否仍存活

最终合并：`Array(Set(aWindows + bWindows))` 去重后返回。

### 核心数据结构

**Windows.list**：`[Window]` 有序数组
- 排序后的窗口列表，UI 直接索引
- `lastFocusOrder` 是紧凑整数，0 表示最近聚焦
- `creationOrder` 是全局递增计数器 `Window.globalCreationCounter`

**Windows.byWindowId**：`[CGWindowID: Window]` 哈希表
- 提供 O(1) 的 WID 查找，用于截图回调和事件处理的快速定位

**Window.lastFocusOrder**：
`updateLastFocusOrder` 增量更新：聚焦窗口置 0，原 0 号窗口 +1，中间值相应递增。`sortByLevel` 完全重建：从 `Spaces.windowsInSpaces(Spaces.visibleSpaces)` 的 z-order 映射。

### Ghost 窗口检测（多信号消歧）

位于 `Applications.refreshIsInvisible()` 和 `Applications.computeIsInvisible()`。

**信号获取**：通过 `Spaces.windowsInSpaces` 获取两个集合：
- `visibleCgsWindowIds` = `windowsInSpaces(allSpaces, includeInvisible: false)` — 可见窗口
- `allCgsWindowIds` = `windowsInSpaces(allSpaces, includeInvisible: true)` — 全部窗口

**消歧逻辑**（按优先级）：
1. `!allCgsWindowIds.contains(wid)` → **GHOST**（最强信号：CGS 已完全丢失 WID，如 Joplin/Sprig 的 Electron 隐藏窗口）
2. `visibleCgsWindowIds.contains(wid)` → **非 ghost**（当前正在渲染）
3. `isMinimized || isHidden || isTabbed` → **非 ghost**（合法不可见原因）
4. `spaceIds 非空 && 与 visibleSpaces 无交集` → **非 ghost**（其他 Space 的窗口）
5. 否则 → **GHOST**（alpha=0 情况，如 Outlook 提醒）

关键设计：空的 `spaceIds` 不等于"在其他 Space"——它意味着"CGS 不知道这个窗口在哪里"，这本身就是一个 ghost 信号。

### 窗口截图双路径

**ScreenCaptureKit 路径**（`WindowCaptureScreenshots`，macOS 14+）：
- `cachedSCWindows: ConcurrentArray<SCWindow>` — 线程安全的 SCWindow 缓存，使用 `os_unfair_lock` 保护
- `SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false)` 获取可分享内容
- `SCScreenshotManager.captureSampleBuffer(contentFilter:configuration:completionHandler:)` 单次截图
- 结果通过 `CVPixelBuffer` → `IOSurface` 传递给 `LightImageLayer.updateContents`

**私有 API 路径**（`WindowCaptureScreenshotsPrivateApi`，macOS 10.13+）：
- `CGSHWCaptureWindowList(CGS_CONNECTION, &windowId, 1, [.ignoreGlobalClipShape, .bestResolution, .fullSize])` 截图
- 返回 `CGImage`，支持最小化窗口和其他 Space 的窗口截图
- 跳过 macOS 15 以规避 ScreenCaptureKit bug（issue #5190）

**IOSurface 内存管理**：
- `CALayerContents` 枚举封装两种格式：`.cgImage(CGImage?)` 和 `.pixelBuffer(CVPixelBuffer?)`
- `LightImageLayer` 将 `CVPixelBuffer` 通过 `CVPixelBufferGetIOSurface` 转为 `IOSurface`，赋值给 `CALayer.contents`
- `releaseImage()` 置 `contents = nil` 释放 IOSurface 引用
- `Windows.removeWindows` 中主动释放被移除窗口的 TileView 和 PreviewPanel 的 IOSurface 引用

**`cachedSCWindows` 缓存**：
- 窗口移除时，在 `Windows.removeWindows` 中清理对应 SCWindow 缓存条目
- 使用 `ConcurrentArray`（基于 `os_unfair_lock`）保证并发安全

---

## 窗口发现策略

### 初始发现

`Applications.initialDiscovery()` → `addInitialRunningApplications()` 遍历所有已运行应用。每个应用通过 `ApplicationDiscriminator.isActualApplication` 过滤后创建 `Application` 实例。

### 持续同步

**AX 事件驱动**：
`Application` 订阅六种 AX 通知（`kAXApplicationActivatedNotification`、`kAXMainWindowChangedNotification`、`kAXFocusedWindowChangedNotification`、`kAXWindowCreatedNotification`、`kAXApplicationHiddenNotification`、`kAXApplicationShownNotification`），`Window` 订阅六种窗口级通知。

**手动补偿**（`manuallyRefreshAllWindows`）：
1. `removeZombieWindows()` — 使用 `CGWindowListCreateDescriptionFromArray` 批量验证 WID 存活性
2. `addMissingWindows()` — 对每个应用调用 `manuallyUpdateWindows`，通过 `allWindows(pid)` 双通道枚举
3. `reviewExistingWindows()` — 刷新已知窗口的 AX 属性
4. `refreshIsInvisible()` — 批量 ghost 窗口检测

**应用特例处理**：
- `com.apple.universalcontrol` 加入黑名单（订阅必然失败）
- `com.apple.dock` 特殊处理（订阅 Dock 事件用于徽章）
- Bear.app 等延迟创建窗口的应用：`manuallyUpdateWindows` 在 `isActive && .regular` 时重试直到超时

---

## Space 管理

### 私有 SkyLight API

Space 管理完全依赖以下私有 API（通过 `@_silgen_name` 声明）：

- `CGSCopyManagedDisplaySpaces(CGS_CONNECTION)` — 获取所有显示器的 Space 布局
- `CGSManagedDisplayGetCurrentSpace(CGS_CONNECTION, displayUuid)` — 获取指定显示器的当前 Space
- `CGSCopyWindowsWithOptionsAndTags(CGS_CONNECTION, owner, spaces, options, setTags, clearTags)` — 获取指定 Space 中的窗口 ID 列表
- `CGSCopySpacesForWindows(CGS_CONNECTION, mask, wids)` — 获取指定窗口所属的 Space

### O(M) Space 查询优化

关键优化在 `Spaces.buildWindowToSpacesMap()`：

```swift
static func buildWindowToSpacesMap() -> [CGWindowID: [CGSSpaceID]] {
    var map = [CGWindowID: [CGSSpaceID]]()
    for (spaceId, _) in idsAndIndexes {      // M = Space 数量
        for wid in windowsInSpaces([spaceId]) {
            map[wid, default: []].append(spaceId)
        }
    }
    return map
}
```

将 N 次逐窗口的 `CGSCopySpacesForWindows` 调用替换为 M 次逐 Space 的 `CGSCopyWindowsWithOptionsAndTags` 调用。由于 M（Space 数，通常 1-10）远小于 N（窗口数，可能数十到数百），这是一个显著的性能优化。

**批量 vs 单窗口决策**（`Windows.shouldBatchSpaceUpdates`）：
```swift
static func shouldBatchSpaceUpdates() -> Bool {
    let trackedWindowCount = list.reduce(0) { $0 + ($1.cgWindowId == nil ? 0 : 1) }
    return trackedWindowCount > Spaces.idsAndIndexes.count
}
```
当窗口数 > Space 数时才使用批量路径，否则逐窗口调用 `cgWindowId.spaces()`。

### Tabbed Window 空间回退

Inactive tab 窗口在 `CGSCopySpacesForWindows` 中返回空 space 列表。`Window.updateSpaces` 通过 `TabGroup.activeTabSibling(of:)` 获取活跃标签的 space 信息作为回退：

```swift
if spaceIds.isEmpty, let activeTab = TabGroup.activeTabSibling(of: self) {
    spaceIds = activeTab.spaceIds
}
```

---

## 窗口聚焦

### 三级回退策略

`Window.focus()` 根据窗口类型选择不同路径：

**路径 1 — AltTab 自身窗口**：
```swift
App.shared.activate(ignoringOtherApps: true)
altTabWindow.makeKeyAndOrderFront(nil)
```

**路径 2 — 无窗口应用或仅显示应用模式**：
```swift
// 优先通过 bundleURL 启动，回退到 runningApplication.activate
NSWorkspace.shared.launchApplication(at: bundleUrl, configuration: [:])
// 或
application.runningApplication.activate(options: .activateAllWindows)
```

**路径 3 — 普通窗口（三级回退）**：
1. **`_SLPSSetFrontProcessWithOptions`**：获取 `ProcessSerialNumber`（通过 `GetProcessForPID`），以 `SLPSMode.userGenerated` 模式将进程带到前台
2. **`makeKeyWindow`（`SLPSPostEventRecordTo` 事件注入）**：构造 0xf8 字节的事件记录，内含目标 WID 和 0xff 填充的魔法字节，通过 `SLPSPostEventRecordTo` 发送到目标进程。先发送 type=0x01 事件，再发送 type=0x02 事件
3. **`AX kAXRaiseAction`**：通过 `axUiElement.focusWindow()` → `performAction(kAXRaiseAction)` 作为最终回退

事件注入的核心实现（移植自 Hammerspoon）：
```swift
private func makeKeyWindow(_ psn: inout ProcessSerialNumber) {
    var bytes = [UInt8](repeating: 0, count: 0xf8)
    bytes[0x04] = 0xf8           // 结构体大小
    bytes[0x3a] = 0x10           // 事件类型标记
    memcpy(&bytes[0x3c], &cgWindowId, MemoryLayout<UInt32>.size)  // 目标 WID
    memset(&bytes[0x20], 0xff, 0x10)  // 魔法填充
    bytes[0x08] = 0x01           // 事件 1
    SLPSPostEventRecordTo(&psn, &bytes)
    bytes[0x08] = 0x02           // 事件 2
    SLPSPostEventRecordTo(&psn, &bytes)
}
```

---

## 性能与优化

### AX 调用调度

`AXCallScheduler.shared` 提供带 key 去重、PID 感知超时、自动重试的 AX 调用调度。全局超时从默认 6 秒缩短到 1 秒（`AXUIElementSetMessagingTimeout`），避免无响应应用阻塞线程。

### 多层节流

| 层级 | 节流器 | 延迟 | 用途 |
|------|--------|------|------|
| 0 | `manualRefreshThrottler` | 1000ms | 面板显示时的全局手动刷新 |
| 1 | `AXCallScheduler` | — | AX IPC 并发控制和重试 |
| 2 | `appListUpdateThrottler` / `windowListUpdateThrottler` | 200ms | 主线程列表变更 |
| 3 | `captureThrottler` | 200ms | 每窗口截图捕获 |

### 批量 Space 查询

`Spaces.buildWindowToSpacesMap()` 将 O(N) 次窗口查询优化为 O(M) 次 Space 查询（M << N），在 `Windows.updatesBeforeShowing()` 中一次性构建映射表，传递给所有窗口的 `updateSpacesAndScreen`。

### 偏好值快照

`WindowFilters.snapshot()` 将所有每快捷键偏好值在循环外一次性计算，避免 N 窗口 x M 偏好的重复 `macroPref` 调用。

### AXObserver 泄漏防护

`Window.releaseAxObserver()` 和 `Application.releaseAxObserver()` 在移除时显式 `CFRunLoopRemoveSource` 并置 nil，修复长期运行会话中每个窗口/应用泄漏一个 RunLoopSource 导致的 399 GB 虚拟内存增长（issue #5612）。

### 截图缓存与清理

- `cachedSCWindows` 缓存 SCWindow 列表避免重复 `SCShareableContent.getExcludingDesktopWindows` 调用
- 窗口移除时清理缓存条目和 `TileView` 的 IOSurface 引用
- `ActiveWindowCaptures` 使用 `OSAtomicIncrement32`/`OSAtomicDecrement32` 无锁计数活跃截图操作

### 并发安全

- `ConcurrentArray<T>` 基于 `os_unfair_lock` 提供轻量级线程安全数组
- 所有 AX 调度在 `BackgroundWork.accessibilityCommandsQueue` 执行
- 截图在 `BackgroundWork.screenshotsQueue`（并发队列，`maxConcurrentOperationCount = 8`）执行
- 主线程仅做结果合并和 UI 更新

---

## 文件清单

| 文件 | 核心类/结构 | 职责 |
|------|------------|------|
| `src/switcher/state/Window.swift` | `Window` | 窗口模型：AXUIElement 集成、AX 事件订阅、窗口操作（关闭/最小化/全屏/聚焦）、Space 更新、缩略图刷新 |
| `src/switcher/state/Application.swift` | `Application` | 应用模型：AX 订阅生命周期、图标处理、无窗口应用占位、KVO 观察者 |
| `src/switcher/state/Windows.swift` | `Windows`, `WindowFilters`, `WindowActivityType` | 窗口集合：发现/去重/过滤/排序、选择管理、lastFocusOrder 维护 |
| `src/switcher/state/Applications.swift` | `Applications` | 应用集合：初始发现、Zombie/Ghost 检测、多层节流、Dock 徽章 |
| `src/switcher/state/Spaces.swift` | `Spaces` | Space 管理：SkyLight API 封装、批量窗口-Space 映射 |
| `src/switcher/state/Screens.swift` | `Screens` | 屏幕管理：多显示器 UUID 映射、目标屏幕检测 |
| `src/switcher/state/TabGroup.swift` | `TabGroup` | 标签组：AX AXTabGroup walking、标签状态管理、Space 传播 |
| `src/switcher/state/WindowThumbnails.swift` | `WindowThumbnails` | 截图调度入口：ScreenCaptureKit / 私有 API 双路径选择 |
| `src/switcher/state/ApplicationDiscriminator.swift` | `ApplicationDiscriminator` | 应用过滤：XPC 检测、Zombie 检测、Android 模拟器识别 |
| `src/switcher/state/WindowDiscriminator.swift` | `WindowDiscriminator` | 窗口过滤：尺寸/Subrole/应用特例规则 |
| `src/macos/api-wrappers/SkyLight.framework.swift` | — | SkyLight 私有 API 声明：CGS 连接、Space 查询、窗口截图、进程聚焦 |
| `src/macos/api-wrappers/AXUIElement.swift` | `AXUIElement` 扩展 | AX 封装：双通道窗口发现、暴力枚举、属性批量读取、AXTabGroup 解析 |
| `src/macos/api-wrappers/CGWindowID.swift` | `CGWindowID` 扩展 | 窗口 ID 工具：标题/层级/Space 查询 |
| `src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift` | — | AX 私有 API 声明：`_AXUIElementGetWindow`、`_AXUIElementCreateWithRemoteToken`、`GetProcessForPID` |
| `src/events/WindowCaptureEvents.swift` | `WindowCaptureScreenshots`, `WindowCaptureScreenshotsPrivateApi` | 截图实现：SCScreenshotManager / CGSHWCaptureWindowList |
| `src/kit/LightImageView.swift` | `CALayerContents` | 截图数据封装：CGImage / CVPixelBuffer 双格式 |
| `src/kit/LightImageLayer.swift` | `LightImageLayer` | 轻量 CALayer：IOSurface 渲染、内存释放 |
