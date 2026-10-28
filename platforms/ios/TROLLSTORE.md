# TrollStore 安装包与共享钥匙串

## 已确认的打包问题

iOS 17 用户报告：巨魔安装后，在 AI 配置页保存 API Key 返回 OSStatus -34018。
用户实际安装的版本尚未确认。检查官方 1.2.0 (67) 社区 IPA 可确认：

- SHA-256：`b2761a03835dcb7bfc11501f01d54c15aeb3a2643c4dc1f93ed8dc05b9479fe1`。
- 主 App 和键盘扩展均完全未签名；两个 Info.plist 请求的共享钥匙串组均为
  `585J2TL9U6.org.scholay.rimes.ios.shared`。
- [TrollStore 的 signApp 实现](https://github.com/opa334/TrollStore/blob/88424f683b2a08f34a3f88985f790f97d84ce1df/RootHelper/main.m#L630-L648)
  在无权限元数据时给主程序使用 `TROLLTROLL.*` 等默认值，扩展使用空字典，
  不会从 XSIME 的自定义 Info.plist 字段推导共享组。

因此，社区未签名包不能直接当作已配置好共享权限的巨魔包使用。这也会影响
App Group 配置共享。此问题与旧版本 Info.plist 缺少组前缀的错误不同；后者
已经修复，参见 `validation/ios-keychain-20261023/README.md`。

## 生成专用包

在 macOS 使用以下命令；不需要开发者证书，不修改应用的兼容标识：

```bash
python3 scripts/release/create-ios-trollstore-ipa.py \
  XSIME-1.2.0-67-ios-unsigned.ipa \
  XSIME-1.2.0-67-TrollStore.ipa \
  --sha256 b2761a03835dcb7bfc11501f01d54c15aeb3a2643c4dc1f93ed8dc05b9479fe1
```

脚本检查输入摘要、双端身份、版本、共享组、隐私清单与嵌套代码。它先给键盘、
再给主 App 添加 ad-hoc 签名，明确携带各自的 application-identifier 和相同的
App Group、Keychain group，不添加调试或不受沙箱约束的权限。原始资源、版本和
用户数据路径保持不变。打包后重新解包校验签名和权限，生成 SHA-256 与验证记录。
输出明确标记 TrollStore，不覆盖上游社区包，也不用于 App Store 提交。

GitHub Actions 的 `iOS TrollStore packaging` 工作流运行回归测试、下载上述固定
官方 IPA 并产出专用包。它复用原版已经构建的二进制，只修改代码签名，没有重编译产品。

## 真机验收（待用户确认）

1. 使用 TrollStore 对现有应用覆盖安装专用 IPA，保留原有设置和词库。
2. 打开主 App，确认已有设置仍在；保存 AI 配置，关闭页面后再次打开，确认无 -34018。
3. 为键盘启用完全访问，在普通文本框打开键盘，确认方案和 AI 配置可共享。
4. 主动提交一段无敏感内容的 Buffer 文本，确认键盘能读取密钥并调用配置的服务。
5. 退出、重新打开主 App 和键盘后重复检查。无需提供 API Key 或未遮挡的服务地址。

静态签名校验和 CI 通过不能替代 iOS 17 真机上的主 App 保存、扩展读取验收。
