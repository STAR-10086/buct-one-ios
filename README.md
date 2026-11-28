# BUCT One · 北化一站（iOS 版）

**北京化工大学（BUCT）iOS 26 原生液态玻璃校园工作台（自签分发版）**

面向 iOS 26.0+ 师生的原生 Swift + SwiftUI 校园客户端：基于 iOS 26 原生 Liquid Glass 材质与交互规范重构，全链路无签名 IPA 云端构建，支持 **SideStore / AltStore / LiveContainer / Sideloadly / Feather / ESign** 自签安装。

---

## 自签分发说明

因免费自签与常见侧载环境无法稳定运行 WidgetKit 扩展，CI 仅构建单一无扩展无签名 `.ipa`：

| 发行包 | Bundle ID | 适用工具 | 特点 |
| :--- | :--- | :--- | :--- |
| **标准版 (`buct-one-ios-*-unsigned.ipa`)** | `com.buct.one` | **SideStore / AltStore / LiveContainer / Sideloadly / Feather / ESign** | 不含 `.appex` 扩展与 App Group 权限，仅占 1 个 App ID，兼容所有自签环境（~6.5 MB） |

> 💡 IPA 在 CI 中均经过 `codesign --force --sign -` ad-hoc 预签（保留 `LC_CODE_SIGNATURE` 与 Entitlements）、XML `Info.plist` 规范化及零 extra-field 纯 `ZIP_STORED` 打包，并通过 `SideSign` 格式校验。R2（`update.buct.one/ios/apps.json`）仅托管下载源清单，IPA 包体统一由 GitHub Releases 分发。详细自签排障请见 [自签与安装指南](docs/自签与安装指南.md)。

### SideStore / AltStore 源地址

在 SideStore 或 AltStore 中添加软件源即可一键安装与后续无电脑更新：

- **开发预览源（跟随 `main` 实时构建 `dev-latest`）**：
  ```text
  https://github.com/STAR-10086/buct-one-ios/releases/download/dev-latest/apps.json
  ```
- **正式版源（发版后启用）**：
  ```text
  https://update.buct.one/ios/apps.json
  ```

---

## 功能进度与工程架构

详细演进路线与架构说明请查阅：
- [路线规划](docs/规划.md)
- [自签与安装指南](docs/自签与安装指南.md)
- [架构与数据层设计](docs/架构与数据层.md)

### 当前已落地模块（v0.2.0 · M0–M3 全部 13 个模块 ✅）

- **认证与网络底座**：原生 `sidportal` 登录（密码 / 图形验证码 / 短信 2FA / Face ID 软件通行密钥 `BuctSoftwarePasskey`）、`w.buct.edu.cn` 校外 WebVPN 3s 直连探测自动降级、单飞静默续期 `SsoSilentRelogin`、校方双链 TLS 校验（`BuctTlsDelegate`）。
- **本研教务与选课（`jwglxt` & `gmis`）**：周/日课表（左右滑动选周、12 节起止时间轴与教师/教室直显）、成绩单与 4.33 官方 GPA、`Swift Charts` 趋势图与目标 GPA 试算、树状培养方案、双通道考试倒计时、空闲教室、选课中心与志愿队列、i北化官方校历自动校准与本地通知提醒。
- **在线教学与高频生活**：北化在线 THEOL（作业待办、课程资源 `QuickLook` 预览与 `WKWebView` Cookie 注入免登）、教务消息、i北化（4 栏校内资讯 + 图书馆在借）、校园邮箱、宿舍电费（三校区离线目录 + 照明/空调双表）、校园网网费（深澜流量与账单）。
- **校内全域成长**：校园一卡通（独立 Keychain 加密登录 + 5 类消费洞察）、第二课堂（五育进度与活动）、实践教学（实验报告/课表/成绩/创新讲座报名与学分）、体测与体育（多年度体测 + 2014 国标离线算分模拟器）。
- **iOS 26 原生 Liquid Glass UI**：5-Tab 液态玻璃导航（`.tabBarMinimizeBehavior(.onScrollDown)`）、4 列自由坐标工作台拖拽重排、WidgetKit 今日课表桌面小组件。

### 核心目录

- **系统基线**：`iOS 26.0+` / `Swift 6.0` / `XcodeGen`（`project.yml`）
- **核心内核（`Packages/BuctCore`）**：
  - `BuctModel`：零依赖领域模型与 `DomainSlice` / `Provenance` 溯源状态
  - `BuctNetwork`：校方双链 TLS 信任验证（`BuctTlsDelegate`）、加密套件、WebVPN 编解码、RFC 8949 CBOR 编码器与原生 SSO/Passkey 客户端
  - `BuctStore`：遵循数据层四条铁律的原子 JSON 落盘、动态容器解析与无 `kSecAttrAccessGroup` Keychain Vault
  - `BuctSources`：各域独立 HTML/API 解析层（集成 `SwiftSoup`）
  - `BuctSync`：单飞同步调度、静默续期与自托管 Umami 零 PII 匿名统计
- **UI 层（`App/` & `WidgetExtension/`）**：原生 SwiftUI 视图、`QuickLook` 附件预览、本地通知服务与 WidgetKit 小组件扩展。

---

## 开源协议

本项目遵循 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 开源协议发布。
