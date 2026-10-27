# KomariBar

Komari 的开源原生 macOS 菜单栏监控客户端，使用中文界面。点开顶部图标，查看多台服务器的资源、网络和流量预算。

**当前为 0.1.0 开发版。** 接口适配以 Komari Dashboard 1.6.1 为基准，提供示例模式；真实实例接入仍需端到端验证。本项目是独立的第三方客户端，与 Komari 官方没有隶属关系。

## 首版范围

- 一个 Komari 面板下的多台服务器，支持切换查看。
- CPU、内存、磁盘、上传下载速度和历史曲线。
- 累计网络流量；确认 Agent 月重置配置后显示本期用量、配额和剩余预算。
- 明确标注的示例模式，可以在没有 Komari 实例时预览界面。
- 面板地址和偏好保存在本机，API Key 存入 macOS 钥匙串。

VPS 上的数据采集和保存由独立部署的 Komari Dashboard 与 Agent 负责，Mac 关机或退出客户端不影响服务器侧继续采集。

## 本地开发

需要 macOS 13 或更新版本，以及 Swift 6.0 或更新版本的构建工具链。安装 Xcode，或安装匹配的 Xcode Command Line Tools；项目使用系统自带的 SwiftUI、Charts 和 Security，不需要额外依赖。

```bash
git clone https://github.com/1gxv1/KomariBar.git
cd KomariBar
swift build
swift test
```

`swift test` 需要包含 XCTest 的完整 Xcode 工具链；只安装 Command Line Tools 的环境可能能构建应用但无法运行测试。GitHub Actions 使用完整 Xcode 环境执行测试。

直接运行示例窗口：

```bash
swift run KomariBar --demo --window
```

`--demo` 使用示例数据，`--window` 打开独立预览窗口，便于开发时观察布局。正常启动时使用菜单栏图标查看面板。

## 打包成 Mac 应用

```bash
./scripts/build-app.sh
open dist/KomariBar.app
```

脚本可以从任意工作目录执行，会生成 `dist/KomariBar.app`、绘制本地图标并做 ad-hoc 签名。产物使用构建机器的架构，尚不是通用二进制，也没有 Developer ID 签名或 Apple 公证。

预览打包后的应用：

```bash
open -n dist/KomariBar.app --args --demo --window
```

GitHub Actions 在推送和 Pull Request 时进行构建、测试、打包，并保存 ZIP 构建产物。

## 接入自己的 Komari

1. 打开设置，填写 Komari 面板地址。推荐使用有效 HTTPS 地址；公开面板也可以使用 HTTP。
2. 公开面板可不填写 API Key。私有面板按当前部署要求填写管理员 API Key，然后连接。
3. 在服务器列表中选择要查看的节点。数据来自 Komari，客户端不会自行部署或修改服务器上的 Agent。
4. 如需本期流量，在所选服务器的流量设置中确认 Agent 已启用月重置，并填写相同的重置日、Agent 时区、计量方式及流量额度。

Komari 普通 API Key 具有管理员权限，**不是只读令牌**。KomariBar 只调用监控接口，但不能缩小 API Key 在服务端的权限。Agent Token 用于采集端上报，不能用来替代客户端所需的认证凭据。[官方接口说明](https://www.komari.wiki/dev/api)

携带 API Key 的远程连接必须使用 HTTPS。HTTP 认证仅允许回环地址，例如本机 SSH 隧道的 `http://127.0.0.1:25774`。应用的网络传输配置允许 HTTP 面板，是否可以附带认证凭据仍由客户端单独校验；HTTPS 连接继续使用系统的证书校验。

已有自托管面板可参考[通过 SSH 隧道连接自己的 Komari](docs/SELF_HOSTING.md)。

## 流量与账单周期

- 未确认 Agent 的月重置配置时，显示“累计流量”，不把它标作本月或本期用量。
- 月重置日和时区必须与 Agent 保持一致；客户端填写设置不会修改服务器配置。
- 按当前 Agent 约定，某月没有指定日期时顺延至次月 1 日，而不是该月最后一天。
- 支持仅上传、仅下载、上传与下载之和、上传与下载取较大值或较小值；应选择套餐实际使用的方式。
- 安装前缺失的历史数据、Agent 停止采集期间的缺口、尚未落盘的数据，都不能由客户端补回。
- 配额进度和剩余预算为估算，最终以服务商后台为准。

Komari 的月重置配置见[官方说明](https://www.komari.wiki/faq/faq)。模块设计和验证范围见[首版设计](docs/ARCHITECTURE.md)。

## 参与开发

欢迎通过 Issue 反馈 Komari 版本、操作系统、问题表现和不含凭据的错误信息。提交前运行 `swift build`、`swift test` 和打包脚本。不要提交服务器地址、真实监控数据、密钥或 API Key。

## 开源许可

[MIT](LICENSE)
