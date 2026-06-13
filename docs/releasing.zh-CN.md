# 发布 Glidex

[English](releasing.md) | [简体中文](releasing.zh-CN.md)

## 本地验证

```bash
swift build
swift test
GLIDEX_VERSION=0.1.0 GLIDEX_BUILD_NUMBER=1 ./scripts/build-app.sh
GLIDEX_VERSION=0.1.0 GLIDEX_BUILD_NUMBER=1 ./scripts/build-dmg.sh
codesign --verify --deep --strict --verbose=2 dist/Glidex.app
```

运行打包后的应用，并在创建 tag 前手动验证 Navigate、Direct Touch、pinch、长按拖动、录制、Replay Last 和 Replay Recording。

## 签名与公证

`scripts/build-app.sh` 默认只应用 ad-hoc 签名。公开发布的二进制文件应使用 Developer ID Application 证书、Hardened Runtime 和 Apple notarization。

仓库不会保存证书名称、钥匙串 profile、Apple ID 或公证凭据。请在私有发布环境中配置这些内容，对最终应用进行签名，生成 DMG，使用 `notarytool` 提交，并在发布前附加已接受的 ticket。

只有以下命令对完全相同的产物通过后，才应将其描述为已公证：

```bash
codesign --verify --deep --strict --verbose=2 Glidex.app
spctl --assess --type execute --verbose=4 Glidex.app
xcrun stapler validate Glidex.app
```

## 源码发布

1. 将 `CHANGELOG.md` 中的 `Unreleased` 替换为发布日期。
2. 确认 README 兼容性说明与实际测试的 macOS 和 Xcode 版本一致。
3. 提交发布元数据。
4. 为 commit 创建 `vMAJOR.MINOR.PATCH` tag。
5. 发布源码归档，并且只附加已经通过签名和公证检查的二进制文件。
