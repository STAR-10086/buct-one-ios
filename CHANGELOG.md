# 更新日志

## v0.1.0 (2026-11-25)

### M0 · 工程骨架与无签 IPA 双包 CI 闭环
- 锁定 `iOS 26.0+` 与 `Swift 6.0`，采用 `XcodeGen`（`project.yml`）+ 本地 `Packages/BuctCore` 五层 SwiftPM 架构，编译器级强制单向依赖隔离。
- 移植 `BuctTlsDelegate`（系统信任库 + GlobalSign/ZeroSSL 校方双链 4 证书兜底）、全套加密套件（AES-ECB/CBC/CFB-128、RSA-PKCS1、HMAC-SHA256、AES-GCM、CBOR）与 Wengine WebVPN URL 编解码。
- 实现遵循数据层四条铁律的 `DomainSliceStore`、防 `-34018` 报错的无 AccessGroup `KeychainVault` 以及动态 App Group/沙盒容器解析器。
- 搭建 iOS 26 原生 Liquid Glass 五栏底栏（`课表 · 成绩 · 工作台 · 作业 · 我的`）、`GlassEffectContainer` 2D 自由坐标工作台与编辑态、自托管 Umami 零 PII 匿名统计开关及首个 `WidgetKit` 今日课表小组件骨架。
- 配置 GitHub Actions `macos-26` 全云端门禁与构建工作流，支持每次构建自动产出标准版与小组件版双无签名 `.ipa` 及 SideStore/AltStore 源清单 `apps.json`。
