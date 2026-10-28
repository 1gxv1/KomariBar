# 通过 SSH 隧道连接自己的 Komari

本指南适用于已有 Komari Dashboard 与 Agent 的部署，且面板与 SSH 服务位于同一台 VPS。数据由 VPS 上的 Agent 采集、Dashboard 保存；KomariBar 只在 Mac 上读取数据。Mac 关机或隧道断开不影响服务器侧继续采集。

## 1. 确认 VPS 上的回环监听

面板应监听 VPS 的 `127.0.0.1:25774`。官方二进制的启动参数如下；将同样的监听参数用于现有面板的启动方式，不要另起一个重复实例：

```bash
komari server -l127.0.0.1:25774
```

若二进制不在命令搜索路径中，在它所在的目录使用 `./komari`。参数依据见[官方二进制部署说明](https://komari-monitor.github.io/komari-document/install/binary.html)与[服务端参数定义](https://github.com/komari-monitor/komari/blob/1.6.1/cmd/server.go)。

同一台 VPS 上的 Agent 可以向这个回环地址上报。若其他服务器的 Agent 依赖现有面板地址，须先确认它们仍有可达的上报通道，再调整监听地址。沿用现有防火墙、SSH 服务和其他业务服务的设置。

## 2. 在 Mac 建立隧道

先确认 Mac 能以现有账户和密钥正常 SSH 登录 VPS。将下面的 `<yourkey>`、`<user>`、`<host>` 替换为自己的密钥、登录用户与服务器地址后，在 Mac 终端运行：

```bash
ssh -N -T \
  -oExitOnForwardFailure=yes \
  -oServerAliveInterval=30 \
  -oServerAliveCountMax=3 \
  -L127.0.0.1:25774:127.0.0.1:25774 \
  -i <yourkey> <user>@<host>
```

这会把 Mac 的 `127.0.0.1:25774` 经 SSH 转发到 VPS 的 `127.0.0.1:25774`。`-N -T` 仅转发端口，不打开远程终端；转发监听失败时退出，连接无响应时通过保活检测断开。参数依据见 [OpenSSH ssh 手册](https://man.openbsd.org/ssh.1)和[连接配置手册](https://man.openbsd.org/ssh_config.5)。

**使用客户端期间保持此 SSH 进程运行。** 命令成功后没有输出是正常现象；关闭终端或按 `Ctrl-C` 会结束隧道。Mac 休眠或网络切换后，必要时重新运行命令。保活参数不会自动重连，也不能保证 VPS 上的面板正常运行。

## 3. 在 KomariBar 接入

1. 先在 Mac 浏览器打开 `http://127.0.0.1:25774`，确认能看到已有面板。
2. 在 KomariBar 设置中将面板地址填写为 `http://127.0.0.1:25774`。
3. 公开面板可留空 API Key；私有面板按部署要求填写管理员 API Key。Key 保存在这台 Mac 的钥匙串中，不写入项目文件。

普通 Komari API Key 拥有管理员权限；KomariBar 仅调用监控接口，不会缩小 Key 在服务端的权限。Agent Token 用于上报，不能替代管理员 API Key。认证方式见[官方接口说明](https://komari-monitor.github.io/komari-document/dev/api.html)。客户端允许通过回环 HTTP 地址使用 Key；远程地址携带 Key 时必须使用 HTTPS。

## 流量与第一个账期

在每台服务器的流量设置中，确认 Agent 已启用月重置，并填写与 Agent 相同的重置日和时区，再选择套餐的计量方式和额度。客户端设置不会修改 Agent。[官方月重置说明](https://www.komari.wiki/faq/faq)建议重置日对齐服务商计费日；当前适配的 Agent 1.5.11 在其所用时区的零点重置，当月没有指定日期时顺延至次月 1 日，见[日期实现](https://github.com/komari-monitor/komari-agent/blob/1.5.11/utils/utils.go)。

**首次安装 Agent 或在账期中途启用月重置时，第一个账期可能只有部分用量，不能当作完整账期。** 在“数据完整性”中填写 Agent 实际开始统计的时间；未确认或首期不完整时，客户端只显示“本期已记录”，隐藏配额进度和剩余预算。下一次重置进入完整账期后会自动显示预算。重建 Agent 统计文件或重新开始计数后，应更新该时间。

客户端无法补回安装前或采集缺失期间的流量；配额和剩余预算始终以服务商后台为准。

## 连接排查

- VPS 默认 SSH 端口 `22` 若连接超时，隧道也无法建立。先通过服务商的 VNC／控制台恢复现有 SSH 可达性，再建立隧道；KomariBar 无法代替这一步。
- 出现本机端口占用错误时，先确认是否已有隧道在运行。也可仅把 `-L` 中第一个 `25774` 改为未占用的本机端口，并在客户端填写相同端口。
- SSH 保持运行但浏览器打不开面板时，检查 VPS 上现有 Komari 服务是否正在监听 `127.0.0.1:25774`。`ExitOnForwardFailure` 不会验证最终面板服务是否可达。
