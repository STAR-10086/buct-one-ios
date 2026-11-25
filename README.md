# BUCT One · 北化一站（iOS 版）

**北京化工大学（BUCT）iOS 26 原生液态玻璃校园工作台（自签分发版）**

面向 iOS 26.0+ 师生的原生 Swift + SwiftUI 校园客户端：基于 iOS 26 原生 Liquid Glass 材质与交互规范重构，全链路无签名 IPA 云端构建，支持 **SideStore / AltStore / LiveContainer / Sideloadly / Feather / ESign** 自签安装。

---

## 双包分发说明

为兼顾不同自签工具的权限限制，CI 每次构建均同时产出两个无签名 `.ipa`：

| 发行包 | Bundle ID | 适用工具 | 特点 |
| :--- | :--- | :--- | :--- |
| **标准版 (`buct-one-ios-*-unsigned.ipa`)** | `com.buct.one` | **LiveContainer / 免费 Apple ID（推荐）** / SideStore / AltStore / Sideloadly / Feather | 不含 `.appex` 扩展与 App Group 权限，仅占 1 个 App ID，兼容所有自签环境 |
| **小组件版 (`buct-one-ios-*-widgets-unsigned.ipa`)** | `com.buct.one.full` | **SideStore / AltStore / 个人付费证书（Feather/ESign）** | 内嵌 `BuctOneWidgets.appex` 桌面小组件，动态探测 App Group 容器并自动兜底沙盒 |

### SideStore / AltStore 源地址

在 SideStore 或 AltStore 中添加软件源即可一键安装与后续无电脑更新：

```text
https://update.buct.one/ios/apps.json
```

---

## 工程架构（M0 骨架）

- **系统基线**：`iOS 26.0+` / `Swift 6.0` / `XcodeGen`（`project.yml`）
- **核心内核（`Packages/BuctCore`）**：
  - `BuctModel`：零依赖领域模型与 `DomainSlice` / `Provenance` 溯源状态
  - `BuctNetwork`：校方双链 TLS 信任验证（`BuctTlsDelegate`）、全套加密套件（AES-ECB / AES-CBC / AES-128-CFB-128 / RSA-PKCS1 / HMAC-SHA256 / AES-GCM）、Wengine WebVPN 域名编解码、RFC 8949 CBOR 编码器
  - `BuctStore`：遵循数据层四条铁律的原子 JSON 落盘、动态 App Group/沙盒容器解析、排除云备份的 Keychain Vault
  - `BuctSources`：HTML/API 解析层（集成 `SwiftSoup`）
  - `BuctSync`：单飞同步调度与自托管 Umami 零 PII 匿名统计
- **UI 层（`App/` & `WidgetExtension/`）**：原生 iOS 26 `TabView` 五栏液态玻璃导航（`.tabBarMinimizeBehavior(.onScrollDown)`）、`GlassEffectContainer` 2D 自由坐标工作台骨架、设置与自签环境诊断、WidgetKit 桌面小组件。

---

## 开源协议

本项目遵循 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源协议发布。
