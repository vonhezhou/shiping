# 发布说明

[返回首页](../README.md) · [开发与测试](development.md)

## 首次公开仓库

- 确认根目录 [MIT License](../LICENSE) 与 README 中的许可说明一致，保留版权及许可声明。
- 检查当前文件和即将推送的 Git 历史，确认没有凭据、个人数据、内部地址及不应公开的截图。`.gitignore` 不会移除已提交的历史；若曾泄露凭据，应先撤销凭据再处理历史。
- 确认第三方代码、图标及其他资源的来源与分发条件。依赖的许可声明需随实际分发要求保留。
- 在 GitHub 配置仓库描述与主题，启用 Issues，并按需启用私密漏洞报告和默认分支保护。
- 推送后检查 `Checks` 工作流。工作流通过不代表真实桌面集成或发行签名验收通过。

## 应用版本发布

### 当前 CI 产物：ad hoc 签名测试版

`Checks` 工作流保留分支 push / PR / 手动检查，仅在推送 `v版本号` tag 且检查通过后构建 Release 并发布独立安装包附件。tag 必须对应 `pubspec.yaml` 去掉 `+构建号` 的版本，例如 `0.10.0+10` 对应 `v0.10.0`。

Release 构建通过临时 xcconfig 显式使用 ad hoc 签名，不使用 `tool/integration.xcconfig`。打包前验证应用签名完整性及 `Signature=adhoc`，使用 `hdiutil` 生成 HFS+ / UDZO 压缩 DMG，然后上传名为 `shiping-<tag>-macos-adhoc` 的 Actions artifact，包含 `.dmg` 与 `.dmg.sha256` 校验文件，作为 CI 备份。随后的 `publish-release` 任务校验 SHA-256，并创建该 tag 的 GitHub Release，将 DMG 和校验文件分别上传为附件，设置清晰的安装包与校验文件标签。仅发布任务拥有 `contents: write` 权限；已有 Release 的说明保留，同名附件会被替换。

上传前运行 `python3 tool/test_macos_dmg.py <镜像路径>`：验证镜像完整性、真实只读挂载、安装快捷方式及说明文件，并将应用复制到临时目录验证签名仍有效；结束后卸载镜像并清理临时安装，不修改本机「应用程序」。此包装集成检查不替代应用功能的真实桌面回归。

DMG 根目录包含「拾屏.app」、指向 `/Applications` 的「应用程序」快捷方式和 `BUILD-INFO.txt`。打开 DMG 后将应用拖到该快捷方式即可安装；复制完成后推出镜像，再从「应用程序」启动。包内说明和 Actions 摘要会说明签名状态、实际架构及验收限制。Release 正文提供安装包与校验文件的直接下载链接，说明签名状态、安装步骤，并区分 GitHub 自动生成的源码压缩包。用户应下载 `.dmg`；`Source code (zip)` 和 `Source code (tar.gz)` 不包含可直接安装的应用。下载后可运行 `shasum -a 256 -c shiping-<tag>-macos-adhoc.dmg.sha256` 检查校验值。

此产物没有 Developer ID 签名，未公证，未 stapling，仅供测试，macOS Gatekeeper 可能阻止启动。后续正式发行需补齐下面的签名、公证与验收步骤，不能将当前 artifact 作为已公证发行版。

### 正式发行检查

1. 更新 `pubspec.yaml` 的版本与构建号，并记录该版本的主要变化及已知限制。
2. 在解锁且已授权录屏的 macOS 上执行 `python3 tool/check.py`，保留实际结果；颜色样本回归还需要辅助功能权限。
3. 人工检查多显示器、混合缩放、全屏应用和物理全局快捷键。确认工具完成后返回原应用，主窗口不会自动打开。
4. 运行 `flutter --no-version-check build macos --release --no-pub`。发布构建不得启用 `FRULER_INTEGRATION_TEST`，不得使用 `tool/integration.xcconfig`。
5. 使用发行者自己的 Developer ID 配置签名、公证与 stapling；仓库不提供发行证书，也不把本地构建视为已公证发行版。在另一台机器上验证启动、权限与功能。
6. 使用 Flutter 的许可信息和依赖包所附声明核对第三方许可，随分发产物保留要求的声明。
7. 推送对应版本标签，等待工作流创建 GitHub Release 并上传独立 DMG 与校验文件；核对附件和直接下载链接，补充架构、权限、验收范围及已知问题，仅保留验证过的分发产物。

`build/` 和 `dist/` 是本地产物目录，不提交到源码仓库。真实截图集成测试需恢复剪贴板并清理测试输出，不应将测试截图或录屏一并发布。
