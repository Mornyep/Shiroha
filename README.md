# 白羽 Shiroha

本地优先的原生 macOS 视觉小说游戏库与 CrossOver 启动器。用大封面浏览收藏，为每款游戏保存容器、入口和启动参数，并查看本地依赖分析、游玩书签与手动攻略。

A native macOS visual novel library and launcher for your existing CrossOver installation, with local diagnostics, bookmarks, and manually curated guides.

当前版本 **0.14.0（已公开预发布）**。原名 VNLauncher，英文短名 Shiroha；已完成显示层改名，已集成用户批准的 Q 版同人图标，已获用户本次发布批准；素材不纳入 MIT，角色权利仍归各自权利人。下载与完整说明见 [v0.14.0 Release](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0)。标签与源码附件保留本次审核时的文件快照，部分准备文档使用发布前措辞；实际发布状态以 Release 为准。

## 已有功能

- SwiftUI/AppKit 原生界面、浅色大封面 Cover Flow、搜索、收藏与自定义收藏集。
- 导入 EXE 或目录，选择入口与 CrossOver 容器；发现 Steam 清单及外部库，保存每款游戏配置、启动状态与日志。
- Steam、Bangumi、VNDB 资料查询与用户确认关联；手动资料保护及本地缓存。
- 多个命名书签、手动进度、用户编排的攻略节点与前置条件；攻略默认折叠。
- 有界本地 PE/DLL 检查；可选 AI 解释脱敏摘要，发送前预览确认。
- 备份逐文件校验、恢复到独立目录；VC++ 副本安装有实现，但真实安装与回滚尚未验收。

启动请求成功或包装器退出码为 0，不代表游戏启动成功或兼容。

## 运行要求

源码部署目标为 macOS 14.0 起；现有 ZIP **仅含 arm64 / Apple Silicon**，不是 Universal Binary。Intel、macOS 14/15 真机未验证，部署目标不等于已在这些系统验收。开发验证环境为 macOS 27.2、Xcode 27.0 / Swift 6.4；CrossOver 历史验证版本为 26.3，不代表最低支持版本。

运行 Windows 游戏须自行安装并合法使用 CrossOver、准备游戏及对应容器。应用不包含 CrossOver、Wine、Windows 组件或游戏。AI 为可选功能；未配置时本地资料和启动链路仍可使用。Codex CLI 或 API 的账户与费用由相应服务决定。

## 安装与首次打开

从 [v0.14.0 Release](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0) 下载对应 CPU 的 ZIP，对照随包 SHA-256，再解压并将「白羽 Shiroha.app」移到「应用程序」或个人 Applications 目录。升级旧 VNLauncher 时先退出旧应用、保留旧副本，再放入新应用；两者共用资料位置，不要同时编辑同一游戏库。本地新候选包为 `Shiroha-0.14.0-arm64.zip`；旧 `app/build/VNLauncher.zip` 保留回滚，不应上传。

现有包为 ad-hoc 签名，无 Developer ID 和公证。若 macOS 提示开发者无法验证，先核实来源与完整性；确认可信后，可在尝试打开后进入「系统设置 → 隐私与安全 → 仍要打开」为该应用单独确认。若提示损坏或恶意软件，停止运行并核对发布者与文件。无需关闭 Gatekeeper、SIP 或批量清除 quarantine。详见 [Apple 官方说明](https://support.apple.com/en-us/102445)。

首次使用：导入游戏 → 选择对应容器和入口 → 检查参数 → 启动 → 查看实际游戏画面及日志。重要资料先备份；组件修复应使用明确选择的专用容器或副本。

## 卸载与本地资料

退出启动器，将应用移到废纸篓即可卸载程序；这不会自动结束仍运行的游戏。默认资料位于 `~/Library/Application Support/VNLauncher`，移除应用不会删除它，也不会删除游戏、CrossOver 容器或存档。需要清理资料时，先导出并验证备份，再人工检查该目录；不要将游戏目录当作启动器缓存删除。API 密钥使用 Keychain 服务 `local.VNLauncher.advisor`；卸载应用不等于删除 Keychain 条目。

## 从源码构建

以下命令从包含 `app/` 的源码根目录执行。需要完整 Xcode 及 Swift 6 工具链；项目没有第三方 Swift Package 依赖。实际通过的工具链为 Xcode 27.0 / Swift 6.4，未承诺旧 SDK 可编译当前 UI API。

```sh
export DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer"
bash app/scripts/build.sh
bash app/scripts/test.sh
```

请将示例路径替换为本机实际 Xcode 路径。构建输出 `app/build/Shiroha.zip`，脚本在分发副本上清理调试信息和构建机工具链搜索路径，生成图标并做 ad-hoc 签名，不负责 Developer ID 或公证；公开分发前须完成核对表。测试默认使用临时缓存；不设置 `VN_PUBLIC_SOURCE_SMOKE=1` 时不执行可选真实资料 API 测试。

## 当前限制

自动章名映射、完整《魔法使之夜》攻略、真实存读档闭环尚未完成；攻略图需人工编排。真实组件安装/回滚、外部 Steam 磁盘全链路、Intel/旧 macOS、远端 CI 和公证未验证。备份不是原子快照，备份前应停止游戏写入。启动器关闭后，游戏可能继续写日志，周期容量管理不会在后台继续运行。

本地资料默认保存在本机。联网资料、AI 摘要与组件下载分别有对应交互；无广告、遥测、账号后端或默认云同步。用户自行放在云同步目录内的文件仍受该目录同步设置影响。

## 后续路线图（规划中，尚未实现）

优先探索 **GalBridge 视觉小说兼容路线**：结合 Windows 兼容层与适用的引擎后端，研究游戏/引擎识别、后端接入与可复核的匹配规则。推荐应依据明确的检测结果和逐游戏验证记录；证据不足时说明不确定性，由用户选择，不宣称优于 CrossOver 或兼容全部游戏。

接下来计划建立缺失组件、插件与运行条件诊断，以及逐游戏兼容性记录。检测与安装分开：安装前展示目标容器、来源、变更、影响和恢复方案，经单独确认后执行，不自动修改现有游戏环境。GPTK 仅作为未来可选路径，具体可用性、授权和系统条件另行验证。

自动存档/章节映射、真实存读档联动仍属研究方向，需要按游戏验证，当前书签与攻略不具备这些自动能力。更远期保留基于 Godot 的原生重建方向；这需要合法素材与相应权利，并非现有游戏可自动迁移的承诺。

上述内容是方向性规划，不代表已交付功能、固定期限、众筹回报或付费承诺。当前版本的 MIT 权利不会因后续新功能的授权方式变化而被撤回。

## 许可与素材

当前 **0.14.0 的原创源码、文档及编译软件采用标准 MIT License**，署名为 `Copyright (c) 2026 VNLauncher contributors`。允许依 MIT 使用、修改、再分发和商业利用；完整条款与精确文件边界见 [LICENSE](LICENSE)、[许可范围](LICENSE-SCOPE.md) 和 [发布文件清单](RELEASE-FILES.json)。

本次已经授出的 MIT 权利持续有效，不因后续众筹、付费或新版本政策被追溯限制。未来新创作且尚未发布的功能可以采用另行明确的条款；不会取消当前 MIT 代码和文档的既有权利。

角色图标以及第三方内容明确排除于 MIT。图标为 AI 生成的同人插画，角色权利归各自权利人；无官方关联或背书，公开使用范围须独立核对，见 app/Artwork/NOTICE.md。当前包不包含官方游戏封面、CG、存档或个人资料缓存。

外部依赖及资料条款见 [依赖与归属](DEPENDENCIES.md)。

更多内容见 [更新记录](CHANGELOG.md)、[发布说明草稿](RELEASE-NOTES.md) 和 [名称兼容性](NAMING.md)。
