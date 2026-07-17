# 发布 Glidex

[English](releasing.md) | [简体中文](releasing.zh-CN.md)

仓库根目录的 `VERSION` 与 `BUILD_NUMBER` 是正式版本来源。发布 tag 必须与
`v<VERSION>` 完全一致。

## 本地验证

```bash
swift test
./scripts/build-app.sh
./scripts/build-dmg.sh
codesign --verify --deep --strict --verbose=2 dist/Glidex.app
```

创建 tag 前，请运行打包后的应用，人工验证焦点切换、Navigate、Direct Touch、
校准恢复、录制库操作、回放、诊断信息和简体中文界面。

## 本地签名并公证

设置 Developer ID Application identity，并提供 notarytool 钥匙串 profile 或
Apple ID 公证凭据：

```bash
export GLIDEX_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)"
export GLIDEX_NOTARY_PROFILE="glidex-notary"
./scripts/release.sh
```

可通过以下命令创建 profile：

```bash
xcrun notarytool store-credentials glidex-notary \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

发布脚本会启用 hardened runtime 签名，提交包含 app 的 ZIP、装订 app、构建
DMG、提交并装订 DMG，然后运行 `codesign`、`spctl`、`stapler` 校验并生成
SHA-256 文件。

## GitHub Actions secrets

推送发布 tag 前，在仓库中配置：

- `DEVELOPER_ID_APPLICATION_CERT_BASE64`：base64 编码的 `.p12` 证书。
- `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`：`.p12` 密码。
- `DEVELOPER_ID_APPLICATION_IDENTITY`：`security find-identity` 显示的完整名称。
- `RELEASE_KEYCHAIN_PASSWORD`：临时钥匙串使用的强密码。
- `APPLE_ID`：Apple Developer 账户邮箱。
- `APPLE_TEAM_ID`：十位开发者团队 ID。
- `APPLE_APP_SPECIFIC_PASSWORD`：用于公证的 App 专用密码。

更新版本、提交并创建对应 tag：

```bash
git tag v0.2.0
git push origin v0.2.0
```

Release workflow 会核对 tag、运行测试、生成已公证产物，并使用仓库范围的
`GITHUB_TOKEN` 发布 DMG 与校验文件。

## 源码发布

1. 将 `CHANGELOG.md` 中的 `Unreleased` 替换为发布日期。
2. 确认 README 兼容性说明与实际测试的 macOS 和 Xcode 版本一致。
3. 更新 `VERSION` 并递增 `BUILD_NUMBER`。
4. 提交发布元数据并创建对应的 `vMAJOR.MINOR.PATCH` tag。
5. 仅发布经过 Release workflow 公证的二进制文件。
