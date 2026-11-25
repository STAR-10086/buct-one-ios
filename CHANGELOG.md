# 更新日志

## v0.2.0 (2026-11-25)

首个功能完备的 iOS 26 原生液态玻璃里程碑版本（完成 M0–M3 全部 13 个工作台模块）。

### 校内全域与选课（M3）
- **校园一卡通（`ecard.buct.edu.cn`）**：独立 Keychain 保险箱（`.card`）+ RSA-PKCS1/AES-ECB 请求信封 + AES-CBC 零填充解密，校外自动走 WebVPN，支持余额隐藏、近 7 天/本月/近 30 天分页流水与 5 类消费洞察。
- **第二课堂（`scs.buct.edu.cn`）**：WebVPN + CAS 换取 JWT `App-Token`，支持多学期五育进度条、分类评价细则与校园活动列表。
- **实践教学（`sjcx.buct.edu.cn`）**：直连 CAS + `HmacSHA256`（`Xtsign`）& RSA-PKCS1（`Cnonce`）逐请求签名，支持实验报告、实验课表与成绩、创新讲座报名/取消/写心得及创新学分统计。
- **体测与体育（`tygl.buct.edu.cn`）**：phpCAS 自动协议升级，支持多年度体测成绩、阳光长跑、体育课成绩与理论考试，内置 **2014 国家学生体质健康标准** 离线实时算分模拟器。
- **选课中心（`jwglxt`）**：原生接入正方 `N253512` 选课 Index/Display/PartDisplay/教学班 `do_jxb_id` 与已选课程查询，支持分类与余量筛选、手动确认选退课及持久化志愿队列。

### 在线教学、资讯与校园生活（M2）
- **北化在线（THEOL）与「作业」Tab**：原生接入 `course.buct.edu.cn`（`/meol` Cookie 作用域、GBK 自动解码、Tomcat 课程上下文），两阶段同步待交作业/测验 DDL、本地自定义待办、课件附件 `QuickLook` 预览，并内置非持久化 `WKWebView` Cookie 注入免登浏览器。
- **教务消息 & i北化**：教务个人提醒与公告、4 栏校内资讯正文阅读、图书馆在借清单与到期本地提醒。
- **校园邮箱 / 宿舍电费 / 校园网网费**：原生 SSO 接入网易企业邮 `/js6/s` JSON RPC；内置三校区离线宿舍目录与 `ele.buct.one` 签名网关双表查询；`tree.buct.edu.cn`（含 `http-8800` WebVPN 端口重写）深澜流量与账单查询。

### 教务学业闭环、工作台与自签基础设施（M0 + M1）
- **认证与网络底座**：全原生 `sidportal` 登录（密码/验证码/短信 2FA/Face ID 软件通行密钥）、`w.buct.edu.cn` 3s 直连探测自动降级 WebVPN、单飞静默续期与校方双链 TLS 校验。
- **本研教务闭环**：周课表左右滑动选周（对齐安卓版 12 节起止时间轴与课程名/教师/教室展示）、成绩单与 4.33 GPA、Swift Charts 趋势图、目标 GPA 试算、树状培养方案（去重与环路保护）、考试倒计时、空闲教室、官方校历自动校准与演示模式。
- **iOS 26 原生 Liquid Glass 与双包自签**：5-Tab 液态玻璃导航、4 列自由栅格工作台拖拽重排、`BuctCore` 五层 + 12 子域隔离门禁、ad-hoc 预签 + 零 extra-field 纯 `ZIP_STORED` 双包构建（完美兼容 SideStore / AltStore / LiveContainer）。
