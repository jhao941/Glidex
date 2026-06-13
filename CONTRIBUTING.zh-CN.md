# 参与贡献

[English](CONTRIBUTING.md) | [简体中文](CONTRIBUTING.zh-CN.md)

Glidex 使用未公开的 Apple framework 和触控板 API。相比宽泛的兼容性猜测，小而聚焦、具有可复现证据的修改更容易审查。

## 开发环境

要求：

- macOS 14 或更高版本
- Apple Silicon Mac
- 安装了 iOS Simulator runtime 的 Xcode
- 为构建出的捕获应用授予辅助功能权限

运行标准检查：

```bash
swift build
swift test
```

输入相关修改还必须在实际启动的 Simulator 中测试。日志显示消息已发送并不足以证明功能正常，必须确认 Simulator 可见地响应。至少验证单击、拖动、双指导航、缩放和 Direct Touch。

## Pull Request

- 将私有 API 代码限制在 `GlidexCore` 内。
- 保持 begin/update/end/cancel 事务语义完整。
- 不要用延迟、重复发送或设备特定硬编码绕过输入竞态。
- 对映射、生命周期、存储或状态机修改补充纯逻辑测试。
- 说明手动验证使用的 macOS、Xcode、Simulator runtime、设备和应用。

不要提交生成的 `.build`、`.app` 或 `dist` 产物。
