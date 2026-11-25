# 开发约定（iOS）

## 构建与环境

- **本机（Windows）不跑 Xcode 构建**。所有构建与测试均走 GitHub Actions `macos-26`。
- 查看构建状态：`gh run list -R STAR-10086/buct-one-ios --limit 5` / `gh run view <id> --log-failed -R STAR-10086/buct-one-ios`。
- 本机执行 `git push` 与 `gh` 命令需挂载代理：`$env:HTTPS_PROXY="http://127.0.0.1:7897"; $env:HTTP_PROXY="http://127.0.0.1:7897"`。
- `.xcodeproj` 由 `XcodeGen`（`project.yml`）在 CI 中现场生成，**禁止提交 `.xcodeproj` / `.xcworkspace`**。
- 系统基线锁定 **`iOS 26.0+`**、**Swift 6.0**（`SWIFT_STRICT_CONCURRENCY: complete`），UI 全部使用 iOS 26 原生 Liquid Glass API。
- 工作台与长列表卡片禁止用外层 `GlassEffectContainer` 包裹（避免 iOS 26 邻近玻璃粘连），多条目列表必须使用 `LazyVStack`。
- `build-ipa.yml` 必须先 `plutil -convert xml1`、由内而外 `codesign --force --sign -` 注入 ad-hoc 签名与 entitlements，再以零 extra-field 纯 ZIP32 `ZIP_STORED` 打包并通过 `SideSign` 解析校验。

## 编译器级分层铁律

业务逻辑位于本地 Swift Package `Packages/BuctCore`，由 SwiftPM Target 依赖关系在编译期强制隔离：

```text
BuctModel   → 零第三方依赖，仅 import Foundation
BuctStore   → 仅依赖 BuctModel（禁止 import BuctNetwork / BuctSources / BuctSync / SwiftUI / UIKit）
BuctNetwork → 仅依赖 BuctModel + Apple 系统安全/网络框架
BuctSources → 依赖 BuctModel + BuctNetwork + SwiftSoup（Academic/Portal/JwNotice/Theol 等子域互不依赖；禁止 import BuctStore / BuctSync / SwiftUI / UIKit）
BuctSync    → 依赖 BuctModel + BuctNetwork + BuctStore + BuctSources（禁止 import SwiftUI / UIKit）
App / WidgetExtension → 仅允许依赖 BuctModel / BuctStore / BuctSync，禁止 import BuctSources / BuctNetwork
```

## 数据层四条铁律

1. **失败永不产生新 `data`**：失败路径仅更新 `refreshState`（有旧数据转为 `.failedFallback`，无旧数据保持 `.never`）与 `lastError`，旧 `data` 原样保留。
2. **`never` ≠ `emptyConfirmed`**：从未同步过严禁显示「没有数据」。
3. **`parserVersion` 只增不减**：调整解析逻辑必须递增版本号。
4. **`capturedAt` 单调不减**：抵御系统时钟回拨（`max(previous.provenance.capturedAt, now)`）。

## 安全与自签红线

- **TLS 校验**：所有网络请求必须走 `BuctTlsDelegate`（系统信任库 + 校方 4 张内置证书双链兜底）；禁止在 `BuctTlsDelegate.swift` 之外出现 `URLCredential(trust:`，禁止配置 `NSAllowsArbitraryLoads`。
- **Keychain 隔离**：严禁显式传入 `kSecAttrAccessGroup`（否则免费自签与 LiveContainer 报 `-34018`）；统一使用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` 排除 iCloud 云备份与设备迁移。
- **双包无签 IPA 策略**：
  - 标准无扩展版 `BuctOne`（`com.buct.one`）：零特殊 Entitlements、无 `.appex` 插件，100% 兼容 LiveContainer / SideStore / AltStore / Sideloadly / Feather / ESign。
  - 完整小组件版 `BuctOneFull`（`com.buct.one.full`）：内嵌 `BuctOneWidgets.appex` + `group.com.buct.one.full` App Group；代码读取容器必须走 `AppContainerResolver` 动态探测，失败自动退回主 App 沙盒。
- **敏感内存与隐私**：内存凭据 `Data` 用后立即 `resetBytes` 清零；零第三方商业统计 SDK，匿名统计仅限自托管 Umami（`https://stats.buct.one`）随机 `UUIDv4` 且受设置实时开关控制。

## 提交规范

- 使用 `<type>: <一行中文说明>` 格式的 commit message（常用前缀：`feat:`、`fix:`、`docs:`、`ci:`、`refactor:`、`chore:`）。
- 发版打 `v*` 标签前，必须同步更新 `Config/Version.xcconfig`（`MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`）与 `CHANGELOG.md`。
