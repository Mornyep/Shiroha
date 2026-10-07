# 白羽 Shiroha 0.14.0

[中文](RELEASE-NOTES.md) · [English](RELEASE-NOTES.en.md) · [日本語](RELEASE-NOTES.ja.md) · [한국어](RELEASE-NOTES.ko.md)

[说明与安装](README.md) · [发布说明](RELEASE-NOTES.md) · [下一版预告](UPDATE-PREVIEW.zh-CN.md) · [更新记录](CHANGELOG.md) · [排错与贡献](README.md#help)

首个公开预览版。用书架整理 Galgame，通过已有的 CrossOver 启动游戏。

## 这版有什么

- 多个命名书签、手动攻略节点、前置条件和完成状态。
- 外部 Steam 库发现、启动日志管理、VNDB Steam App ID 查询。
- 改善详情页、长标题和不同窗口尺寸下的显示。
- 修复备份校验、书签迁移、过期扫描结果和编辑冲突。
- 应用更名为「白羽 Shiroha」，加入新图标；沿用 VNLauncher 的资料目录。

## 下载

[前往 v0.14.0 发布页](https://github.com/Mornyep/Shiroha/releases/tag/v0.14.0)。

- `Shiroha-0.14.0-arm64.zip`：Apple Silicon 应用包。
- `Shiroha-0.14.0-source.zip`：本版源码快照。
- `Shiroha-SHA256SUMS.txt`：上述两个压缩包的 SHA-256 校验值。

需要 macOS 14 或更新版本，以及自行安装的 CrossOver、游戏和容器。当前仅提供 arm64 包；实际验证环境为 macOS 27.2，Intel 和 macOS 14/15 未实机验证。

应用使用 ad-hoc 签名，尚无 Developer ID 签名和 Apple 公证。首次打开方法见 [README](https://github.com/Mornyep/Shiroha#readme)。

## 已知限制

书签与攻略仍需手动整理，不支持自动章节识别或存读档同步。真实游戏的声音、视频、输入和存读档尚未全面测试；组件安装与回滚、外部 Steam 库完整流程也仍需实测。备份前请停止游戏写入。

本版通过 88 项单元测试、构建及签名校验，这不代表所有游戏都兼容。

## 许可

原创源码、文档与编译软件采用 [MIT License](https://github.com/Mornyep/Shiroha/blob/main/LICENSE)。图标为 AI 生成的鸣濑白羽同人插画，排除于 MIT，角色权利归各自权利人，本项目与官方无关联。详见 [许可范围](https://github.com/Mornyep/Shiroha/blob/main/LICENSE-SCOPE.md) 与 [图标说明](https://github.com/Mornyep/Shiroha/blob/main/app/Artwork/NOTICE.md)。

发布附件与 v0.14.0 标签保留本版快照；main 上的文档会继续更新。`RELEASE-FILES.json` 记录源码附件的文件与哈希，不是 main 的实时清单。

