# 白羽 Shiroha · 显示改名与兼容性

本轮按用户明确指示完成显示层改名；没有迁移数据或内部标识。

| 项目 | 最终值 | 影响 |
| --- | --- | --- |
| 应用文件名 | 白羽 Shiroha.app | Finder 已实际显示；旧快捷方式可能仍指向旧版，用户需重新指向新应用 |
| CFBundleDisplayName | 白羽 Shiroha | 全称 |
| CFBundleName | Shiroha | 英文短名 |
| bundle identifier | local.VNLauncher | 不变 |
| 可执行文件 / Swift targets | VNLauncher / VNCore / VNInspect | 不变 |
| 资料目录 | ~/Library/Application Support/VNLauncher | 不变；不创建新资料库 |
| Keychain service | local.VNLauncher.advisor | 不变；本轮未读取凭据 |
| 工程目录、日志内部名称、环境变量 | VNLauncher 体系 | 不变 |
| 版本 / build | 0.14.0 / 14 | 未发布版本维持不变 |
| 默认构建输出 | app/build/Shiroha.zip | 本轮通过 VN_BUILD_OUTPUT 写入独立候选路径，旧包保留 |

升级时退出旧应用并保留旧副本，不并行编辑共享库；更换签名身份后仍须另验 Keychain 访问与系统权限。本轮源码无更改，数据加载和密钥服务字符串逐文件核对未变，不声称运行过真实库迁移。

Finder 图标和简介已实际确认名称、图标及版本。Dock 目视验收未做：系统中用户原 VNLauncher 使用同一 bundle ID 正在运行，本轮没有退出用户进程或启动第二个竞争实例。安装版未被替换。

回滚：旧 app/build/VNLauncher.zip 与先前 VNLauncher-0.14.0-arm64.zip 保留；构建脚本改名前副本在 release/rollback/before-display-rename/app/scripts/build.sh。不要将回滚旧包作为新公开附件。
