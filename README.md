<p align="center">
  <img src="app/Artwork/AppIcon.png" width="128" alt="白羽 Shiroha 图标">
</p>

<h1 align="center">白羽 Shiroha</h1>

<p align="center">Mac 都买了，Galgame 也得玩吧。</p>
<p align="center">A native macOS visual novel manager and CrossOver launcher.</p>

<p align="center">中文 · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a></p>

日文、英文和韩文是文档语言；应用界面目前仍以中文为主。

[说明与安装](README.md) · [发布说明](RELEASE-NOTES.md) · [下一版预告](UPDATE-PREVIEW.zh-CN.md) · [更新记录](CHANGELOG.md) · [排错与贡献](README.md#help)

<p align="center">
  <a href="https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0">下载 v0.14.0 预览版</a> ·
  <a href="https://github.com/Mornyep/Shiroha/issues">问题反馈</a> ·
  <a href="CHANGELOG.md">更新记录</a>
</p>

话说，想在 Mac 上推个 Gal，怎么先开始找入口、挑容器、翻文件夹了。

所以我做了白羽。把游戏收进书架，封面、资料、启动配置和手动书签放在一起。不然本来想推剧情，结果先在文件夹里推理半天。

现在运行 Windows 游戏主要还是靠 CrossOver。至于兼容性，当然不会因为图标可爱就自己变好，后续会继续做 GalBridge，把适合视觉小说的检测和运行方案慢慢补起来。

名字取自我最喜欢的《Summer Pockets》女主鸣濑白羽。是的，取名这里夹带了一点私货。

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

## 下一版预告

想推的是女主路线，结果先攻略了半晚上文件夹。下一版准备继续把启动这条「共通线」走顺：整理 CrossOver 默认设置、改进 Bangumi / VNDB 条目与评分匹配、打磨「喜欢」联动，再补上 Steam 时长 JSON 导入与本地计时。海报取色设置也会做减法，移除闲置的壁纸与盘面选项，保留已有图片和共用取色能力。

这些还在未公开的候选版本里，界面操作和真实游戏计时仍待验证。Steam 时长指的是 JSON 文件导入，不是自动登录同步。**目前可下载的仍是 v0.14.0 公开预览版**，先不立发布日期 flag。[查看完整预告](UPDATE-PREVIEW.zh-CN.md)。

路线和存档识别也在研究，从受限的 Ren'Py 脚本、原创样例存档与有限路径分析开始。目前不提供商业游戏结局识别、通用存档支持或实时剧情追踪。选项前该存的档，还是要存。

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

<a id="help"></a>

## 排错与参与

先试这几步，别急着重装整个共通线：

1. **找不到 CrossOver 或容器**：在设置里选择已安装的 CrossOver，再刷新容器。确认游戏对应的容器已在 CrossOver 中准备好。
2. **游戏启动失败**：检查选中的 EXE、容器和启动参数；再从同一个 CrossOver 容器直接启动一次。记录两种方式的结果，便于区分游戏兼容性和启动配置问题。
3. **匹配到错误作品**：重新选择 Steam、Bangumi 或 VNDB 条目，也可以手动编辑。不同版本和同名作品容易混淆，反馈时请附作品名与版本。
4. **备份或恢复遇到问题**：先停止游戏写入，保留原存档和备份。恢复到新目录后检查结果，不要直接覆盖唯一一份存档。

[反馈 Issue](https://github.com/Mornyep/Shiroha/issues)时，请写明白羽、macOS、CrossOver 版本、Mac 芯片、游戏版本、复现步骤、预期与实际结果。日志和截图先移除个人路径、账号、密钥和剧情剧透；不要上传游戏本体或整个存档文件夹。

想参与的话，小修正、翻译和兼容性记录都欢迎。较大的功能改动可以先开 Issue 讨论范围。PR 里说明改了什么、怎么检查的、还有什么没验证；代码改动请运行上面的测试，文档改动请检查对应语言的链接。贡献只包含你有权提交的内容，保留现有许可与第三方署名，不要提交游戏资源、私密数据、密钥或本机生成的文件。四语文档方便大家阅读，并不表示提供专门的四语客服。

## 感谢

- [Bangumi](https://bangumi.tv/) 和 [VNDB](https://vndb.org/) 提供的作品资料。
- [Steam](https://store.steampowered.com/) 的游戏资料。
- [CrossOver](https://www.codeweavers.com/crossover) 提供的 Windows 兼容环境。

## 许可

源码与文档采用 [MIT License](LICENSE)。详细范围及第三方归属见 [LICENSE-SCOPE.md](LICENSE-SCOPE.md) 和 [DEPENDENCIES.md](DEPENDENCIES.md)。

图标为鸣濑白羽的非官方同人插画，不属于 MIT 授权范围。角色权利归各自权利人，本项目与官方无关联。详见 [图标说明](app/Artwork/NOTICE.md)。


