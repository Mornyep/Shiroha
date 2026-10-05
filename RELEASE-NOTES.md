# 白羽 Shiroha 0.14.0 · 公开预发布草稿

原名 VNLauncher。原生 macOS 视觉小说收藏库与启动器，复用已有 CrossOver；用大封面浏览作品，并整理书签、手动攻略和本地兼容性分析。

本版增加多个命名书签、手动攻略节点、外部 Steam 库发现、日志管理及 VNDB Steam App ID 查询，改善长标题和详情页阅读，并修复备份复核及编辑冲突。发布准备加入获批准的 Q 版同人图标、显示名「白羽 Shiroha」及分发包路径清理。

- 应用：白羽 Shiroha.app；英文短名 Shiroha；内部标识和资料路径保持 VNLauncher 兼容。
- 版本：0.14.0 / build 14，拟用 tag v0.14.0（未创建）。
- 平台：arm64 / Apple Silicon；部署目标 macOS 14.0+。实际验证 macOS 27.2，Intel 与旧 macOS 实机未验证。
- 外部依赖：自行准备合法 CrossOver、游戏与容器；均不随包提供。AI 可选。
- 签名：ad-hoc，无 Developer ID、公证、远端 CI 或干净机器 Gatekeeper 验收。
- 验证：88 项测试通过，显示改名后源码/测试逐文件未变，复用匹配证据；新包构建、解压严格签名、路径扫描通过。Finder 实际显示新名称、图标、版本及 Apple 芯片类型。此前同代码空库隔离启动 8 秒通过；不声称已验证游戏兼容性。
- 限制：自动章名、完整攻略、真实存读档、真实组件安装/回滚和外部 Steam 盘全链路尚未完成。Dock 图标未做独立验证。

附件候选：Shiroha-0.14.0-arm64.zip、Shiroha-0.14.0-source.zip、Shiroha-SHA256SUMS.txt。计划目标 **Mornyep/Shiroha · public · pre-release**，尚未建立仓库、提交、上传或发布。

当前 0.14.0 原创源码、文档及编译软件采用标准 MIT，保留 VNLauncher contributors 署名。已授出的 MIT 权利持续有效；未来新创作且尚未发布的功能可以另定条款，不追溯限制当前版本。角色图标及第三方内容独立于 MIT，无官方关联或背书。许可、范围与逐文件 SHA-256 随包提供；用户已批准本次公开发布；该批准不构成角色权利人的授权或 MIT 图像再许可。

后续方向（未实现）：优先研究 GalBridge 视觉小说兼容路线、Windows 兼容层与引擎后端接入、基于证据的后端匹配、组件/插件诊断与逐游戏验证。安装始终单独确认；GPTK 为可选研究路径，Godot 原生重建保留为远期选项。自动存档/章节映射仍待研究，不作期限或众筹回报承诺。详见 README 路线图。
