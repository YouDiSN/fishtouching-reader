# macOS Developer ID 签名与公证

当前公开的 macOS 包只有临时签名，没有 Apple 公证，所以 Gatekeeper 可能显示“Apple 无法验证是否包含恶意软件”。完成下列步骤后，使用 Developer ID 签名、Hardened Runtime 和 Apple 公证重新发布。

## 1. 由账号本人完成会员注册

这个私人项目应使用个人 Apple Account 申请 [Apple Developer Program](https://developer.apple.com/programs/enroll/)，无需加入公司团队。Apple 要求账号本人完成双重认证、身份信息核验、协议确认和会员购买；会员费为每年 99 美元或当地币种。个人会员发行的软件会关联个人开发者身份。请不要把 Apple Account 密码、双重认证码、身份证件或付款信息提交到仓库或聊天中。

## 2. 在本机申请 Developer ID Application 证书

会员生效后，按 [Apple 的 CSR 指南](https://developer.apple.com/help/account/certificates/create-a-certificate-signing-request/)在“钥匙串访问 → 证书助理”生成 CSR。进入 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list)，新增 **Developer ID Application** 证书，上传 CSR，下载 `.cer` 并双击安装。CSR 的私钥必须保留在签名用的这台 Mac 的钥匙串中。这个项目不需要 Developer ID Installer 证书。

检查证书及私钥：

```sh
security find-identity -v -p codesigning
```

输出须包含 `Developer ID Application: ... (TEAMID)`。当前机器在 2026-10-09 检查时显示 `0 valid identities found`。

## 3. 只在本机钥匙串保存公证凭据

先在 Apple Account 中创建应用专用密码，然后在终端执行下面的命令。`notarytool` 会安全地提示输入密码；不要把密码写进命令行、脚本或 Git。Team ID 可在 Apple Developer Account 页面查看。

```sh
xcrun notarytool store-credentials fishtouching-reader \
  --apple-id '你的 Apple Account 邮箱' \
  --team-id '你的 TEAMID'
```

此操作在本机钥匙串保存可向 Apple 提交公证的凭据；个人账户的密码和证书私钥不应上传 GitHub Actions。若使用 Apple Developer app 注册，Apple 说明会员可能按订阅自动续费，注册时请核对付款页面。

## 4. 构建、签名、公证并验证

先更新 `scripts/build-app.sh` 中的应用版本号，再运行：

```sh
./scripts/package-notarized-release.sh \
  'Developer ID Application: 你的姓名 (TEAMID)' \
  fishtouching-reader
```

脚本只对构建结果的临时副本签名，启用 Hardened Runtime 和安全时间戳；然后提交公证、装订票据，用 `codesign`、`stapler` 和 `spctl` 验证，最后生成 ZIP 与 SHA-256。只有检查全部通过后才能替换 GitHub Release 包。Apple 的公证是自动恶意软件与签名检查，不是 App Store 人工审核。
