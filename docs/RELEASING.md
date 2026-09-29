# 发布到 GitHub

## 发布前

1. 确定版权署名与许可证，将正式许可放入仓库根目录 `LICENSE` 并更新 README。
2. 在 `native/Info.plist` 更新版本和构建号，补充 `CHANGELOG.md`。
3. 运行 `bash native/test.sh`，并手动检查透明模式点击穿透、文字输入、C 清空、⌘Z 恢复、X 退出。
4. 运行 `bash native/package.sh`，检查包内文件与校验和。

## 新建仓库

推荐仓库名：`simpleboard-macos`；描述可用「轻量 macOS 白板与桌面批注工具，玻璃工具栏、红色画笔与等宽文字」。

将 `SimpleBoard-v版本-source.zip` 解压到一个新目录，再将其中的文件上传至新建的 GitHub 仓库。不要上传外层 ZIP 代替源码，也不要上传旧工作目录的 `.git`、缓存、日志或本机配置。

确认仓库内容与许可证后，可创建与版本一致的标签（例如 `v1.4.0`），并在 Releases 中附上 `SimpleBoard-v版本-macOS-arm64.zip` 和对应的 `SHA256SUMS`。发布正文请明确：Apple Silicon、macOS 13+、仅临时签名、未经 Apple 公证、内容退出后不保存。

本项目脚本仅生成本地文件，不会创建远程仓库、推送代码或发布 Release。

## 签名与公证

当前脚本使用 ad-hoc 签名。若后续采用 Developer ID 签名和 Apple 公证，应通过维护者自己的账户和安全凭证环境完成；不要将证书、私钥、令牌或密码放入源码仓库。
