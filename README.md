# AlertClashIP

一个原生 macOS 菜单栏应用，用来持续检查 Clash 当前公网出口 IP 是否符合你的预期。

当检测到出口 IP 已变化，或者当前无法查询出口 IP 时，应用会通过系统通知提醒你。它适合放在后台常驻运行，帮你盯住代理出口是否跑偏。

## 主要功能

- 菜单栏常驻显示当前状态
- 定时检查公网出口 IP
- 对比目标 IP，发现异常立即提醒
- 异常持续时按设定间隔重复提醒
- 恢复正常后发送恢复通知
- 支持主备公网 IP 查询服务，降低单点失败概率
- 支持“立即检查”
- 支持“登录时自动启动”
- 支持 Clash External Controller API 快速感知节点变化
- 支持中文界面和中文通知文案
- 设置窗口支持置顶显示
- 手动检查后显示临时结果提示条

## 当前支持的状态

- 正常：当前公网出口 IP 与目标 IP 一致
- IP 不匹配：当前公网出口 IP 与目标 IP 不一致
- 查询失败：当前无法获取公网出口 IP
- 待命：尚未填写目标 IP

## 使用方式

### 运行应用

1. 用 Xcode 打开 [AlertClashIP.xcodeproj](/Users/edy/Coding/alert-clash-ip/AlertClashIP.xcodeproj)
2. 选择共享 scheme `AlertClashIP`
3. 运行 App target
4. 首次启动时允许系统通知
5. 点击菜单栏图标，进入“设置”
6. 填写目标 IP，点击“保存并应用”

### 日常使用

- 点击“立即检查”可以手动触发一次检查
- 如果当前正好有后台检查在运行，手动检查会进入队列
- 菜单栏会显示状态点、状态文案和当前摘要
- 设置页会显示当前状态、上次检查时间和上次提醒时间
- 如果启用了 Clash API，你可以指定一个监控策略组名称，例如 `虎云`
- 菜单栏和设置页只会显示这个监控策略组当前选中的节点
- 如果 Clash API 已连接，设置页会自动拉取策略组列表并提供下拉选择

## Clash API 快速感知

当前版本支持通过 Clash / Mihomo 的 External Controller API 快速感知节点变化。

默认配置为：

```text
控制器地址：http://127.0.0.1:9097
Secret：123456
```

工作方式：

- 应用会每 5 秒轮询一次 Clash API
- 当检测到策略组当前选中的节点发生变化时，会立即触发一次公网出口 IP 复查
- 你可以在设置里填写“监控策略组名称”，应用会只显示这个组对应的当前节点
- 如果找不到对应策略组，界面会明确提示“未找到策略组”

如果 Clash API 无法访问，应用不会停止公网 IP 监控，只会在界面中显示 `Clash API：连接失败`

## 配置项说明

- 目标 IP：你希望 Clash 最终出口应该使用的公网 IP
- 每 X 分钟检查一次：定时轮询频率
- 异常持续时每 X 分钟重复提醒：避免只提醒一次后被忽略
- 登录时自动启动：开机登录后自动启动菜单栏应用
- 监控策略组名称：指定要观察的 Clash 策略组，例如 `虎云`

## 项目结构

- [AlertClashIP.xcodeproj](/Users/edy/Coding/alert-clash-ip/AlertClashIP.xcodeproj)
  标准 Xcode macOS App 工程
- [Sources/AlertClashIPApp](/Users/edy/Coding/alert-clash-ip/Sources/AlertClashIPApp)
  应用源码
- [Tests/AlertClashIPAppTests](/Users/edy/Coding/alert-clash-ip/Tests/AlertClashIPAppTests)
  逻辑测试
- [SupportingFiles](/Users/edy/Coding/alert-clash-ip/SupportingFiles)
  `Info.plist`、资源目录、导出配置等
- [scripts](/Users/edy/Coding/alert-clash-ip/scripts)
  构建、归档、打包脚本
- [Package.swift](/Users/edy/Coding/alert-clash-ip/Package.swift)
  保留的 Swift Package 结构

## 构建与导出

### 生成本机可运行的 Release `.app`

```bash
./scripts/build_release_app.sh
```

输出位置：

```text
dist/AlertClashIP.app
```

### 生成 `.dmg`

在已经生成 `dist/AlertClashIP.app` 后运行：

```bash
./scripts/package_dmg.sh
```

输出位置：

```text
dist/AlertClashIP.dmg
```

### 生成签名后的分发版本

如果你有 Apple Developer 证书：

1. 打开 [ExportOptions-DeveloperID.plist](/Users/edy/Coding/alert-clash-ip/SupportingFiles/ExportOptions-DeveloperID.plist)
2. 把 `YOUR_TEAM_ID` 改成你的 Team ID
3. 在 Xcode 里为 App target 配置签名
4. 运行：

```bash
./scripts/archive_signed_app.sh
```

导出目录：

```text
dist/export
```

## 技术说明

- 使用 Swift + SwiftUI 实现
- 通过 `MenuBarExtra` 构建菜单栏应用
- 通过 `UNUserNotificationCenter` 发送系统通知
- 通过 `URLSession` 查询公网 IP
- 通过 `UserDefaults` 保存设置和运行时快照
- 通过 `SMAppService` 处理登录时自动启动

## 当前限制

- 目前只支持单个目标 IP
- 只验证“最终公网出口 IP”，不直接读取 Clash 节点名
- 不会主动控制 Clash，也不会切换节点
- 还没有历史记录、日志导出和多 IP 白名单

## 已实现的交互优化

- 修复设置按钮无法稳定打开设置窗口的问题
- 修复设置窗口不在最前层的问题
- 修复目标 IP 第二次修改不生效的问题
- 修复“立即检查”在检查中被吞掉的问题
- 修复检测到状态变化后菜单栏标题和状态未刷新的问题
- 增加手动检查后的临时提示条

## 测试

当前包含核心决策逻辑测试：

- 初次异常通知
- 异常升级提醒
- 恢复通知
- 正常状态不提醒
- IPv4 / IPv6 校验

测试文件：
[MonitorDecisionEngineTests.swift](/Users/edy/Coding/alert-clash-ip/Tests/AlertClashIPAppTests/MonitorDecisionEngineTests.swift)

## 建议的后续增强

- 支持多个允许 IP
- 一键“记住当前出口 IP”
- 展示最近一次实际出口 IP
- 失败重试阈值，减少短时网络抖动误报
- 导出检查日志
- 接入 Clash 本地 API 显示当前节点信息
