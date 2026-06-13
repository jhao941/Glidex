# 安全性与兼容性

[English](SECURITY.md) | [简体中文](SECURITY.zh-CN.md)

Glidex 会动态加载未公开的 Apple framework，并使用辅助功能 API 识别 Simulator 显示区域。这些接口可能在 macOS 或 Xcode 更新后发生变化，且 Apple 不会提前通知。

Glidex 不需要网络访问，也不会上传手势录制。录制文件以 JSON 格式保存在本地：

```text
~/Library/Application Support/Glidex/Recordings/
```

请将导入的录制文件视为不受信任的输入。Glidex 会在回放前验证格式、坐标、时间、触点拓扑和生命周期。

请将安全问题私下发送至 `hao_941@icloud.com`。报告中请包含 Glidex commit、macOS 版本、Xcode 版本和最小复现步骤；请勿附带私人应用数据或无关系统日志。
