# WenBar — 技术架构文档

## 1. 总体分层架构

WenBar 采用「纯逻辑 Swift Package + 非沙盒主应用 + 沙盒 Finder 扩展」三层分离架构：

1. **`Packages/WenBarCore`（本地 Swift Package）**
   - 不依赖 AppKit / SwiftUI 界面生命周期，承载所有核心算法与可单测逻辑：
     - `Calendar`：`LunarCalendarEngine`（农历、干支生肖、24 节气天文近似算法、传统节日）、`HolidayRepository`（离线 JSON + 在线同步缓存）、`DateCalculator`、`ClockFormatEngine`。
     - `Disk`：`JunkRule`、`DiskSafetyGuard`、`JunkFileCleaner`（非跟随软链递归清理）、`LsofParser`。
     - `Archive`：`ZipEncodingDetector` & `ZipHeaderNormalizer`（ZIP Central Directory 解析与 GBK→UTF-8 头重写）、`SmartExtractPlanner`、`ArchiveCommandBuilder`。
     - `IPC`：`WenBarActionPayload`（URL Scheme / Pasteboard 编解码）。
     - `Settings`：`WenBarSettingsModel`（共享偏好模型）。

2. **`WenBar`（非沙盒主应用，`LSUIElement = YES`）**
   - `StatusBarController`：管理主时钟 `NSStatusItem`、`NSPopover` 及条件显示的独立外接盘 `NSStatusItem`。
   - `GlobalHotkeyManager`：基于 Carbon `RegisterEventHotKey` 的全局热键（免辅助功能权限）。
   - `ActionRouter`：接收 `wenbar://action?...` 请求，调度压缩/解压任务或目录清理。
   - `ClockViewModel` & `CalendarViewModel`：驱动时钟刷新、倒计时/番茄钟、世界时钟及 `EventKit`（macOS 14+ `requestFullAccessToEvents` / `requestFullAccessToReminders`）。
   - `ExternalDriveManager`：监听 `NSWorkspace` 挂载事件，结合 `DiskArbitration` 卸载推出卷，忙碌时调用 `/usr/sbin/lsof` 排查占用。
   - `ArchiveTaskManager`：异步任务队列，调度内嵌 `Resources/bin/7zz` 与系统 `/usr/bin/bsdtar`，解析进度并支持取消、加密弹窗与通知。
   - `UpdateService`：预留 Sparkle 2.x 协议与 `SUFeedURL` 检查入口。

3. **`WenBarFinderSync`（沙盒 Finder Sync Extension）**
   - 继承 `FIFinderSync`，监听 `/` 及外接卷右键菜单事件。
   - 由于沙盒扩展在本地无付费证书（ad-hoc 签名）场景下无法可靠建立 App Group XPC，扩展通过构造 `WenBarActionPayload` 并调用 `NSWorkspace.shared.open("wenbar://...")`（超长路径列表通过命名 `NSPasteboard` 中转）唤醒主 App 执行实际文件操作。

---

## 2. 关键技术细节与安全护栏

### 2.1 ZIP 中文乱码自动修复原理
- Windows 资源管理器或部分压缩软件打包的 ZIP 若未设置 General Purpose Bit Flag 第 11 位（`0x0800`，UTF-8 标识），其文件名通常采用系统代码页（简体中文为 GB18030/GBK，繁体为 Big5）。
- `ZipEncodingDetector` 从文件尾解析 EOCD（`0x06054b50`）和 Central Directory（`0x02014b50`），收集所有条目的原始字节名：
  - 若已有 `0x0800` 标志或全部为合法 UTF-8，直接交由 `7zz` 解压；
  - 若存在非 UTF-8 字节序列，依次尝试 `GB18030`、`Big5`、`Shift-JIS` 解码，命中后由 `ZipHeaderNormalizer` 将 Local File Header 与 Central Directory 中的文件名原地重写为 UTF-8 并置位 `0x0800` 输出到临时目录，再交给 `7zz` 无损解压，从而保留完整目录结构与加密/压缩算法兼容性。

### 2.2 外接卷安全清理守则
- `DiskSafetyGuard` 在执行清理前强制校验：
  1. 挂载点不可为 `/`、`/System/*`、`/Library/*` 或用户主目录；
  2. `volumeIsReadOnlyKey` 必须为 `false`；
  3. 不可为内部不可移除盘（`volumeIsInternalKey == true` 且非外接可弹出卷）；
  4. 检测并拒绝 Time Machine 备份卷（如存在 `Backups.backupdb`、`.com.apple.timemachine.donotpresent` 或 `.backup` 标记）。
- `JunkFileCleaner` 每次访问子目录均检查 `URLResourceKey.isSymbolicLinkKey`，遇到符号链接一律跳过不追踪，杜绝跨卷误删。

### 2.3 构建与签名策略
- **本地开发**：`scripts/setup-deps.sh` 自动准备 `7zz` 并放入 `WenBar/Resources/bin/7zz`，`scripts/build-local.sh` 使用 XcodeGen 生成工程并完成 ad-hoc 签名构建及 `pluginkit` 注册。
- **公开发布**：`scripts/release-dmg.sh` 支持由内向外（先 `7zz`、再 `WenBarFinderSync.appex`、最后 `WenBar.app`）使用 Developer ID 证书与 `--options runtime` 签名，并通过 `xcrun notarytool` 提交公证与 `stapler` 装订，最终封装为 `.dmg` 并生成 Sparkle `appcast.xml` 模板。
