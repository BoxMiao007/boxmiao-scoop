# scoop-boxmiao 开发规范

## 仓库说明

本仓库是一个 [Scoop](https://scoop.sh) 软件仓库（Bucket），包含 Windows 应用的安装清单。

## 应用清单规范

### 新增应用

在 `bucket/` 目录下创建 `<应用名>.json`，格式参考既有清单或 `bucket/app-name.json.template`。

### 必需字段

- `version` — 上游最新版本号
- `description` — 应用说明
- `homepage` — 应用官网
- `license` — 开源协议
- `url` / `hash` — 下载地址及 SHA256
- `checkver` — 自动检测版本（优先使用 `github` 方式）
- `autoupdate` — 自动更新 URL 模板

### 安装包

先看下载物是不是已经能运行的程序。zip、7z、便携 exe 直接用。是安装包时，清单必须装出可运行程序；应用目录里只剩安装包，视为清单错误。

用 `7z l` 看安装包类型，再选下面一种。`url` 和 `autoupdate` 用同一套处理。上游有多个架构时，`architecture` 逐个写上。

**NSIS / electron-builder**（内含 `$PLUGINSDIR\app-64.7z` 或 `app-arm64.7z`）：

1. `url` 加 `#/dl.7z`，让 Scoop 先解开 NSIS 外壳。
2. `installer.script` 把内层程序解到 `$dir`，再删掉安装器残留：

```powershell
Get-Item -Path "$dir\`$PLUGINSDIR\app*.7z" | Expand-7zipArchive -DestinationPath "$dir"
Remove-Item -Path "$dir\`$*", "$dir\Uninstall*" -Recurse -Force
```

3. `shortcuts`（以及有命令行入口时的 `bin`）指向解出的主程序，不指向安装包。
4. 有 `resources/app-update.yml` 时，`post_install` 注释掉其中的 `url`，避免应用内更新装到 Scoop 目录之外。文件不存在则跳过：

```powershell
$yaml = "$dir\resources\app-update.yml"
if (Test-Path $yaml) {
    $content = Get-Content -Path $yaml | ForEach-Object {
        if ($_.StartsWith('url')) { "$($_.Replace('url', '# url')) # Disabled by Scoop" } else { $_ }
    }
    Set-Content $yaml -Value $content -Encoding ascii
}
```

**必须注册进系统才能用**（输入法、驱动、系统服务）：不解包。`installer.args` 用静默参数（常见 `/S`），`uninstaller.script` 调用安装目录里的卸载程序并等待结束。不要把这类程序留在 Scoop 应用目录里冒充已安装。

## 提交规范

### 分支

在 master 分支上直接提交。

### 提交信息

```
类型: 中文描述
```

类型：feat / fix / refactor / docs / chore / test / ci

### 提交前检查

- `git status --short` 确认只有目标文件变更
- 必要时运行 `.github/workflows/ci.yml` 中的测试

## README 规范

- `README.md` 的「可用应用」按应用类型分组展示，每组一个 `###` 小节加表格。组顺序固定为：AI 编程、开发工具、浏览器、美术与资产；组内应用按名称排序（不区分大小写）。
- 新增应用优先归入现有分组；确无合适的分组时，再按其类型新增分组。
- 应用名称链接到对应官方网站，便于用户直达项目主页。

## 自动更新

本仓库通过 Excavator（GitHub Actions）自动检查上游新版本，`checkver` 和 `autoupdate` 字段需配置正确。

工作流配置为每小时检查一次（`.github/workflows/excavator.yml`，`cron: '20 * * * *'`），但公共仓库的 `schedule` 是尽力而为调度：实测本账户被合并到约每天 4 次，且与同账户其他仓库的触发时间点对齐。这是 GitHub 侧的账户级限流，改 cron 无效，不要为此反复调整频率。需要立即检查时用 `workflow_dispatch` 手动触发：`gh workflow run excavator.yml`。

### 本地复现

`scripts/excavator-local.ps1` 在本地复现上述 Excavator：同步 `origin/master` → 运行 `checkver -Update` → 逐个提交 `<app>: Update to version <version>` → 推送。全程用 git，不需要 `hub`。

```pwsh
.\scripts\excavator-local.ps1 -NoPush        # 只更新并本地提交，先确认会产生哪些提交
.\scripts\excavator-local.ps1                # 更新、提交并推送，等价于一次 Excavator 运行
.\scripts\excavator-local.ps1 -App magpie    # 只处理指定清单

.\excavator-local.bat                        # 同上，bat 包装：优先 pwsh，其次 powershell
.\excavator-local.bat -NoPush -App magpie    # bat 会原样转发参数
```

bat 包装运行结束后会等待按回车键关闭窗口（方便双击运行查看结果）；自动化调用可先 `set EXCAVATOR_NO_PAUSE=1` 跳过等待。

脚本要求当前在 `master` 且工作区干净。建议先配置 `scoop config gh_token`，否则 GitHub API 匿名限额每小时 60 次，容易中途 403。脚本正文保持 ASCII：Windows PowerShell 5.1 会把无 BOM 的 UTF-8 中文脚本按 ANSI 解析而报语法错误，仓库测试又禁止 BOM，所以中文说明只放在本文件。
