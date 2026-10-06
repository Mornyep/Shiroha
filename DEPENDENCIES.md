# 依赖、许可与归属

没有第三方 Swift Package 声明，没有随包 vendored 库、Wine、CrossOver、Windows 组件、商业游戏素材或数据库快照。

| 项目 | 用途及是否随包 | 许可/归属边界 |
| --- | --- | --- |
| SwiftUI、AppKit、Foundation、CoreFoundation、CoreGraphics、CoreTransferable、CryptoKit、ImageIO、Security、libSystem/libobjc | macOS 系统框架/库，动态链接，不复制进 app | Apple 系统/SDK 提供；不作为本项目源码重新授权 |
| Swift 标准运行库及 Swift 系统桥接库 | 系统动态链接，不附 runtime 副本 | Swift 开源项目采用 Apache-2.0 with Runtime Library Exception；不等于整个 Apple SDK 都采用此许可。[Swift 官方许可](https://www.swift.org/legal/license.html) |
| Xcode、swift build、codesign、sips、iconutil、install_name_tool、strip、ditto | 本机构建工具，不随包 | 使用本机工具链，不再分发 SDK |
| CrossOver | 用户自行安装的外部运行依赖；未捆绑 | CodeWeavers 的独立商业许可/相关组件条款；不由本项目许可授予。[官方许可说明](https://www.codeweavers.com/store/licensing) |
| Codex CLI（可选） | 调用用户本机已安装 CLI；未捆绑 | 官方 CLI 源码为 Apache-2.0；AI 服务账户、使用权限与费用另按服务条款。[官方 LICENSE](https://github.com/openai/codex/blob/main/LICENSE) |
| Visual C++ v14 Redistributable（可选修复） | 用户确认后从 Microsoft 来源下载/安装到容器副本；不随包 | Microsoft 独立条款；官方下载链接不等于本项目获再分发许可。[官方说明](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170) |
| Steam 与游戏 | 用户合法安装，外部服务/内容；不随包 | Valve、发行商及各内容权利人的条款独立适用；评论、封面、截图不是项目源码许可内容 |
| VNDB | 可选在线资料查询，不附数据库 | API 声明非商业使用免费，数据仍受 Data License 约束。[API 条款](https://api.vndb.org/kana#usage-terms)、[数据许可](https://vndb.org/d17)；图片使用须另行核对相应权利 |
| Bangumi | 可选在线资料查询，不附缓存 | 官方版权页对条目信息标示 CC BY-SA，并区分已有版权内容与用户原创内容；须遵守来源、版权和开发者规则，不能把所有图片视为通用再分发素材。[版权与开发者协议](https://bgm.tv/about/copyright) |
| AppIcon.png / AppIcon.icns | AI 生成的角色同人插画；随应用提供 | 角色与相关权利归各自权利人，无官方关联；不适用源码概括性许可。见 app/Artwork/NOTICE.md 与 [Visual Arts 指引](https://visual-arts.jp/guideline/) |

项目署名为 VNLauncher contributors。外部服务、游戏资料与图标的权利独立于本项目许可；再分发时须遵守各自条款。
