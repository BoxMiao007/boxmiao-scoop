# scoop-boxmiao

[![Tests](https://github.com/BoxMiao007/scoop-boxmiao/actions/workflows/ci.yml/badge.svg)](https://github.com/BoxMiao007/scoop-boxmiao/actions/workflows/ci.yml) [![Excavator](https://github.com/BoxMiao007/scoop-boxmiao/actions/workflows/excavator.yml/badge.svg)](https://github.com/BoxMiao007/scoop-boxmiao/actions/workflows/excavator.yml)

个人维护的 [Scoop](https://scoop.sh) 软件仓库。

## 添加仓库

```pwsh
scoop bucket add boxmiao https://github.com/BoxMiao007/scoop-boxmiao
```

## 安装应用

```pwsh
scoop install boxmiao/<应用名>
```

例如：

```pwsh
scoop install boxmiao/cloakbrowser
```

## 更新应用

```pwsh
# 更新指定应用
scoop update cloakbrowser

# 更新所有应用
scoop update *
```

## 卸载应用

```pwsh
scoop uninstall cloakbrowser
```

## 可用应用

### AI 编程

| 应用 | 说明 |
|------|------|
| [BrimDeck](https://github.com/MoFeng2223/BrimDeck) | Windows 11 灵动岛小组件，常驻屏幕顶部汇总 AI 编程工具的额度与用量，并提供音乐播放控制与系统监控 |
| [DeepSeek Harness](https://www.deepseek.com/harness/) | DeepSeek 开源的 Agent 桌面应用（预览版），基于 Cordis「一切皆插件」架构 |
| [DSH-X](https://yyh-001.github.io/DSH-X/) | DeepSeek Harness 的多开与多版本管理桌面工具，内嵌官方 Web 界面，支持 MCP 与技能扩展 |
| [magpie](https://usemagpie.ai) | 本地 AI 网关，为 Codex、Claude Code 等编码 Agent 统一分配模型与账号，额度用尽自动切换 |
| [NodeCloak](https://nodecloak.com) | 独立浏览器工作空间，为每个副本单独配置代理、语言与隐私选项，并启动 Claude Code、Codex、Gemini 终端 |
| [OpenBot](https://openbot.run/) | 本地优先的持久化 AI 智能体桌面工作台，支持 Codex、Claude Code、Grok 等 Agent 协作、任务队列、文件传输与内置浏览器控制 |
| [OpenCode Desktop](https://opencode.ai) | 开源 AI 编程智能体 OpenCode 的桌面客户端 |
| [Token Monitor](https://github.com/Javis603/token-monitor) | 本地优先的桌面小组件，汇总 40 余个 AI 编程工具的 Token 用量、费用与额度 |
| [ZCode](https://zcode.z.ai) | Z.ai 出品的 AI 编程助手桌面客户端 |
| [zcode-switch](https://github.com/pjpv/zcode-switch) | 在多个 ZCode 账号之间一键切换，自动显示额度 |

### 开发工具

| 应用 | 说明 |
|------|------|
| [NyaTerm](https://nyaterm.app) | 现代远程终端工作区，集成 SSH、Telnet、串口、SFTP、RDP/VNC 会话、隧道与内置 AI 助手 |
| [Pebrel](https://github.com/Kuddev/pebrel) | AI 原生 GPU 加速终端模拟器，集成 SSH、持久会话、分屏与 AI CLI 工作流 |
| [Rscoop](https://github.com/AmarBego/Rscoop) | Scoop 的桌面应用程序。无需进入终端即可搜索、安装、更新和管理 Windows 软件包 |
| [ZedG](https://github.com/wenyinos/ZedG) | Zed 编辑器的简体中文版，AI 自动翻译并重新编译，跟随上游版本更新 |

### 浏览器

| 应用 | 说明 |
|------|------|
| [cloakbrowser](https://github.com/CloakHQ/CloakBrowser) | 隐身 Chromium 浏览器，源码级指纹补丁，通过所有反检测测试 |

### 美术与资产

| 应用 | 说明 |
|------|------|
| [PhotoCraft](https://getartcraft.com/apps/photocraft) | 开源、纯 Rust 重写的 Photoshop 替代品，支持图层、蒙版、调整图层、文字与真实 PSD 文件 |
| [Photon Studio](https://tenzen.studio/photon/) | 免费的全功能 Photoshop 替代品，支持 PSD/PSB、RAW 处理与本地 AI 功能 |
| [Serpent](https://serpent.dolag.work) | 开源数字资产管理软件，面向游戏美术、影视后期与平面/动态图形设计 |

### 系统工具

| 应用 | 说明 |
|------|------|
| [VProxy](https://github.com/mateo-ki/vproxy) | Rust + egui 编写的跨平台代理工作站：采集订阅、解析节点，驱动 Mihomo/sing-box/VP-Core/Xray 等六大内核实测可用性与延迟 |

## 自动更新

本仓库通过 Excavator 自动检查上游新版本并提交更新 PR，无需手动维护。工作流配置为每小时检查一次，实际触发由 GitHub Actions 调度决定（公共仓库的 `schedule` 为尽力而为，实测约每天 4 次），如需立即检查可通过 `workflow_dispatch` 手动触发。

---

<details>
<summary>Bucket 模板原始说明（英文）</summary>

## How do I use this template?

1. Generate your own copy of this repository with the "Use this template"
   button.
2. Allow all GitHub Actions:
   - Navigate to `Settings` - `Actions` - `General` - `Actions permissions`.
   - Select `Allow all actions and reusable workflows`.
   - Then `Save`.
3. Allow writing to the repository from within GitHub Actions:
   - Navigate to `Settings` - `Actions` - `General` - `Workflow permissions`.
   - Select `Read and write permissions`.
   - Then `Save`.
4. Document the bucket in `README.md`.
5. Replace the placeholder repository string in `bin/auto-pr.ps1`.
6. Create new manifests by copying `bucket/app-name.json.template` to
   `bucket/<app-name>.json`.
7. Commit and push changes.
8. If you'd like your bucket to be indexed on `https://scoop.sh`, add the
   topic `scoop-bucket` to your repository.

## How do I install these manifests?

After manifests have been committed and pushed, run the following:

```pwsh
scoop bucket add <bucketname> https://github.com/<username>/<bucketname>
scoop install <bucketname>/<manifestname>
```

## How do I contribute new manifests?

To make a new manifest contribution, please read the [Contributing
Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md)
and [App Manifests](https://github.com/ScoopInstaller/Scoop/wiki/App-Manifests)
wiki page.

</details>
