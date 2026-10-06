<p align="center">
  <img src="app/Artwork/AppIcon.png" width="128" alt="白羽 Shiroha 图标">
</p>

<h1 align="center">白羽 Shiroha</h1>

<p align="center">在 Mac 上整理和启动你的 Galgame。</p>
<p align="center">A native macOS visual novel manager and CrossOver launcher.</p>

<p align="center">
  <a href="https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0">下载 v0.14.0 预览版</a> ·
  <a href="https://github.com/Mornyep/Shiroha/issues">问题反馈</a> ·
  <a href="CHANGELOG.md">更新记录</a>
</p>

白羽是一个用 SwiftUI 编写的 macOS 视觉小说管理器。把游戏放进书架，补全封面和介绍，选好 CrossOver 容器，下次就可以直接从这里启动。

名字取自《Summer Pockets》中的鸣濑白羽。目前仍在开发中，欢迎试用和反馈。

## 功能

- 📚 **游戏书架** — 大封面浏览、搜索、收藏和自定义收藏集。
- 🎮 **导入与启动** — 导入 EXE 或游戏文件夹，发现 Steam 游戏，为每款游戏保存容器、入口和启动参数。
- 🖼️ **游戏资料** — 查询 Steam、Bangumi、VNDB，选择匹配的条目，也可以自己修改资料和封面。
- 🔖 **游玩记录** — 添加命名书签、手动记录进度，整理攻略节点和前置条件。
- 🔍 **运行诊断** — 检查本地 EXE 与 DLL 依赖，查看启动日志；可选用 AI 帮助解释，发送前可以预览摘要。
- 💾 **存档备份** — 选择存档目录后备份并校验文件，恢复时放到新目录。

游戏库保存在本机。没有广告、遥测或默认云同步；不配置 AI 也能使用游戏库和启动功能。

## 下载与使用

从 [Releases](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0) 下载 `Shiroha-0.14.0-arm64.zip`，解压后把「白羽 Shiroha.app」拖入「应用程序」。同页提供源码和 SHA-256 校验文件。

- **系统**：Apple Silicon Mac，macOS 14 或更新版本。当前仅提供 arm64 包，Intel 暂未支持；macOS 14/15 的实际运行尚未验证。
- **运行游戏**：需要自行安装 CrossOver，并准备游戏和对应容器。白羽不附带游戏、CrossOver 或 Windows 组件。

打开白羽后，导入游戏，选择对应容器和启动入口，再点击启动。游戏能否正常运行取决于它与 CrossOver 的兼容情况。

> 当前版本尚未经过 Apple 公证，使用 ad-hoc 签名。确认下载来源可信后，如遇开发者验证提示，可在尝试打开后前往「系统设置 → 隐私与安全 → 仍要打开」。不需要关闭系统安全保护。若提示恶意软件或文件损坏，请停止运行并核对下载文件。参见 [Apple 的说明](https://support.apple.com/en-us/102445)。

<details>
<summary>从旧版升级 / 卸载</summary>

白羽原名 VNLauncher，沿用原来的本地资料目录。升级前退出旧版、保留备份，不要同时运行两个版本编辑同一游戏库。

退出应用后，将它移到废纸篓即可卸载。游戏、CrossOver 容器和存档不会随之删除，正在运行的游戏也不会自动退出。

游戏库保留在 `~/Library/Application Support/VNLauncher`。如果要一并清理，请先备份再手动处理该目录。已保存的 API 密钥仍在钥匙串中，服务名为 `local.VNLauncher.advisor`。

</details>

## 目前的不足

- 书签和攻略需要手动整理，还不能自动识别游戏章节或同步存读档。
- 真实游戏的声音、视频、输入和存读档没有完成全面测试，不能保证每款游戏都能正常运行。
- 组件安装与回滚、外部 Steam 库的完整流程还需要实测。
- 备份前请先停止游戏写入；目前不支持对运行中的游戏做原子快照。

## 接下来想做

- [ ] **GalBridge**：识别游戏和引擎，探索适合视觉小说的兼容层与引擎后端。
- [ ] 完善缺失组件诊断，在用户确认后提供安装帮助。
- [ ] 整理逐游戏的兼容性记录，让后端选择有实测依据。
- [ ] 研究存档与章节识别，减少手动记录进度的操作。

GPTK 作为可选方向继续评估；基于 Godot 的原生重建是更远期的探索。以上功能都还没有包含在当前版本中。

## 技术栈

- Swift 6
- SwiftUI / AppKit
- Swift Package Manager（无第三方 Swift Package 依赖）

## 本地构建

需要完整 Xcode。目前通过构建和测试的工具链为 Xcode 27.0 / Swift 6.4，运行环境为 macOS 27.2。

```sh
git clone https://github.com/Mornyep/Shiroha.git
cd Shiroha

# 将路径替换为本机的 Xcode 路径
export DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
bash app/scripts/build.sh
bash app/scripts/test.sh
```

构建结果位于 `app/build/Shiroha.zip`。脚本会生成图标并完成 ad-hoc 签名，不包含 Developer ID 签名或公证。

欢迎提交 Issue 或 Pull Request。报告启动问题时，请附上 macOS、CrossOver 版本和复现步骤；分享日志前记得移除个人路径、账户信息和密钥。

## 感谢

- [Bangumi](https://bangumi.tv/) 和 [VNDB](https://vndb.org/) 提供的作品资料。
- [Steam](https://store.steampowered.com/) 的游戏资料。
- [CrossOver](https://www.codeweavers.com/crossover) 提供的 Windows 兼容环境。

## 许可

源码与文档采用 [MIT License](LICENSE)。详细范围及第三方归属见 [LICENSE-SCOPE.md](LICENSE-SCOPE.md) 和 [DEPENDENCIES.md](DEPENDENCIES.md)。

图标是 AI 生成的鸣濑白羽同人插画，不属于 MIT 授权范围。角色权利归各自权利人，本项目与官方无关联。详见 [图标说明](app/Artwork/NOTICE.md)。
