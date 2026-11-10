#Requires -Version 5.1
<#
.SYNOPSIS
    在本地复现 GitHub Excavator 工作流：检测上游新版本、更新清单、逐个提交并推送。

.DESCRIPTION
    对应 .github/workflows/excavator.yml（ScoopInstaller/GithubActions v3 的 Excavator）。
    工作流在 windows-latest 上做的事，本脚本用本地 Scoop 等价完成：

      1. 同步 origin/<Branch>，保证从最新提交开始；
      2. 运行 Scoop 的 checkver -Update，按 autoupdate 改写 bucket/ 下的清单；
      3. 每个变更的清单单独提交，提交信息为 "<app>: Update to version <version>"；
      4. 推送前再次 rebase，然后 push 到 origin/<Branch>。

    与工作流的差异：
      * 不使用 hub：本地直接用 git 完成 add/commit/push，不需要 `scoop install hub`；
      * 工作流里"预置 hub 到 Scoop 缓存"那一步是为绕开 Actions 上 hub release 的 504，
        本地无需执行，脚本也不做；
      * 工作流固定 SKIP_UPDATED=1，脚本等价地传 -SkipUpdated。

    前置条件：本机已安装 Scoop（checkver 来自 Scoop 自身），当前分支干净且等于 -Branch，
    建议配置 GitHub token（`scoop config gh_token <token>` 或设置 GH_TOKEN/GITHUB_TOKEN），
    否则 GitHub API 匿名限额 60 次/小时，容易中途 403。

.PARAMETER App
    只检查指定清单名（支持 * 通配），默认 * 即全部。

.PARAMETER Remote
    远端名，默认 origin。

.PARAMETER Branch
    推送目标分支，默认 master。当前分支必须与之一致。

.PARAMETER CommitMessageFormat
    提交信息模板，<app> 与 <version> 会被替换。默认与 Excavator 一致。

.PARAMETER NoPush
    只更新并本地提交，不推送；用于预览脚本会产生哪些提交。

.PARAMETER ThrowError
    透传给 checkver：单个清单检测失败时抛异常终止，而不是继续并汇总。

.EXAMPLE
    .\scripts\excavator-local.ps1 -NoPush
    本地更新并逐个提交，不推送。

.EXAMPLE
    .\scripts\excavator-local.ps1
    更新、提交并推送，等价于一次 Excavator 运行。

.EXAMPLE
    .\scripts\excavator-local.ps1 -App magpie
    只检查并更新 magpie。
#>
[CmdletBinding()]
param(
    [string] $App = '*',
    [string] $Remote = 'origin',
    [string] $Branch = 'master',
    [string] $CommitMessageFormat = '<app>: Update to version <version>',
    [switch] $NoPush,
    [switch] $ThrowError
)

$ErrorActionPreference = 'Stop'
try {
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
} catch {
    # 老版本控制台不支持时忽略，不影响功能
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$bucketDir = Join-Path $repoRoot 'bucket'

function Write-Step([string] $Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string[]] $GitArgs,
        [switch] $AllowFail
    )
    Write-Verbose ("git " + ($GitArgs -join ' '))
    $output = & git @GitArgs 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFail) {
        throw "git $($GitArgs -join ' ') 失败（退出码 $code）：`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ Code = $code; Output = @($output) }
}

# ---------- 前置检查 ----------

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw "找不到仓库根目录的 .git：$repoRoot"
}
if (-not (Test-Path -LiteralPath $bucketDir -PathType Container)) {
    throw "找不到清单目录：$bucketDir"
}

Push-Location $repoRoot
$failedApps = New-Object System.Collections.Generic.List[string]
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw '未找到 git，请先安装 Git for Windows'
    }

    # checkver 来自 Scoop 自身，需要 SCOOP_HOME；SCOOP 用于定位 scoop config（token 等配置）
    if (-not $env:SCOOP_HOME) {
        $env:SCOOP_HOME = (Convert-Path (scoop prefix scoop))
    }
    $checkverPath = Join-Path $env:SCOOP_HOME 'bin\checkver.ps1'
    if (-not (Test-Path -LiteralPath $checkverPath)) {
        throw "未找到 Scoop 的 checkver.ps1：$checkverPath（本机是否已安装 Scoop？）"
    }
    if (-not $env:SCOOP) {
        # scoop 安装根目录：<SCOOP_HOME> 形如 <SCOOP>/apps/scoop/current
        $env:SCOOP = Split-Path -Parent (Split-Path -Parent $env:SCOOP_HOME)
    }

    $tokenConfigured = $false
    foreach ($name in 'SCOOP_GH_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $tokenConfigured = $true; break }
    }
    if (-not $tokenConfigured) {
        # scoop config 会把值打印到 stdout，只取变量，不回显
        $configToken = scoop config gh_token 2>$null
        if ($configToken) { $tokenConfigured = $true }
    }
    if (-not $tokenConfigured) {
        Write-Warning '未检测到 GitHub token，匿名 API 限额为每小时 60 次，checkver 可能中途报 403。可执行：scoop config gh_token <token>'
    }

    $currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -ne $Branch) {
        throw "当前分支为 $currentBranch，脚本要求在 $Branch 上执行（可用 -Branch 指定）。"
    }

    $dirty = @(& git status --porcelain --untracked-files=no)
    if ($dirty.Count -gt 0) {
        throw "工作区存在未提交的改动，请先处理后再运行：`n$($dirty -join [Environment]::NewLine)"
    }

    # ---------- 同步远端 ----------

    Write-Step "同步 $Remote/$Branch"
    Invoke-Git @('fetch', $Remote, $Branch) | Out-Null
    $pull = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
    if ($pull.Code -ne 0) {
        throw "拉取 $Remote/$Branch 失败，请手动处理后重试：`n$($pull.Output -join [Environment]::NewLine)"
    }
    $pull.Output | ForEach-Object { Write-Host $_ }

    # ---------- 检测并更新清单 ----------

    Write-Step "运行 checkver -Update（App=$App）"
    $checkverOutput = & $checkverPath -App $App -Dir $bucketDir -Update -SkipUpdated -ThrowError:$ThrowError 2>&1
    $checkverCode = $LASTEXITCODE
    $checkverOutput | ForEach-Object { Write-Host $_ }

    foreach ($line in $checkverOutput) {
        # checkver 对单个清单失败只打印错误并继续，这里收集起来在末尾汇总为非零退出码
        if ("$line" -match 'rate limit|not valid|无法|无效|错误|error') {
            $failedApps.Add(("$line").Trim())
        }
    }

    # ---------- 逐个提交 ----------

    Write-Step '提交变更的清单'
    $status = @(& git status --porcelain --untracked-files=no -- 'bucket')
    $committed = 0
    $skipped = New-Object System.Collections.Generic.List[string]

    foreach ($line in $status) {
        $relative = $line.Substring(3).Trim()
        if (-not $relative.EndsWith('.json')) { continue }

        $fullPath = Join-Path $repoRoot $relative
        $manifest = $null
        try {
            $manifest = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
        } catch {
            $failedApps.Add("$relative（JSON 解析失败：$($_.Exception.Message)）")
            continue
        }
        if (-not $manifest.PSObject.Properties['version'] -or -not $manifest.version) {
            $failedApps.Add("$relative（缺少 version 字段）")
            continue
        }

        $appName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
        $message = $CommitMessageFormat.Replace('<app>', $appName).Replace('<version>', $manifest.version)

        Invoke-Git @('add', '--', $relative) | Out-Null
        $staged = @(& git diff --cached --name-only -- $relative)
        if ($staged.Count -eq 0) {
            # 只有行尾（LF/CRLF）差异时不会产生暂存内容，与 Excavator 的跳过逻辑一致
            $skipped.Add($appName)
            continue
        }
        $commit = Invoke-Git @('commit', '-m', $message) -AllowFail
        if ($commit.Code -ne 0) {
            $failedApps.Add("$appName（提交失败：$($commit.Output -join ' ')）")
            Invoke-Git @('reset', '--', $relative) -AllowFail | Out-Null
            continue
        }
        $committed++
        Write-Host "已提交：$message" -ForegroundColor Green
    }

    if ($skipped.Count -gt 0) {
        Write-Host "跳过（仅行尾差异）：$($skipped -join ', ')" -ForegroundColor Yellow
    }

    $ahead = 0
    $countResult = Invoke-Git @('rev-list', '--count', "$Remote/$Branch..HEAD") -AllowFail
    if ($countResult.Code -eq 0) {
        $ahead = [int]("$($countResult.Output[0])".Trim())
    }

    # ---------- 推送 ----------

    if ($NoPush) {
        Write-Step '汇总（-NoPush，未推送）'
        Write-Host "新提交：$committed 个，本地领先 $Remote/$Branch $ahead 个提交。"
        if ($ahead -gt 0) {
            & git --no-pager log --oneline "$Remote/$Branch..HEAD" | ForEach-Object { Write-Host "  $_" }
        }
    } elseif ($ahead -eq 0 -and $committed -eq 0) {
        Write-Step '汇总'
        Write-Host '没有检测到需要更新的清单。' -ForegroundColor Green
    } else {
        Write-Step "推送前 rebase $Remote/$Branch"
        $rebase = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
        if ($rebase.Code -ne 0) {
            Invoke-Git @('rebase', '--abort') -AllowFail | Out-Null
            throw "推送前 rebase 失败，已中止 rebase，本地提交保留，请手动处理：`n$($rebase.Output -join [Environment]::NewLine)"
        }
        $rebase.Output | ForEach-Object { Write-Host $_ }

        $toPush = 0
        $countResult = Invoke-Git @('rev-list', '--count', "$Remote/$Branch..HEAD") -AllowFail
        if ($countResult.Code -eq 0) {
            $toPush = [int]("$($countResult.Output[0])".Trim())
        }

        Write-Step "推送 $Remote/$Branch"
        $push = Invoke-Git @('push', $Remote, "HEAD:$Branch") -AllowFail
        if ($push.Code -ne 0) {
            # 远端可能刚被别人（Excavator）推进，同步后再试一次
            Write-Warning "首次推送失败，rebase 后重试：$($push.Output -join ' ')"
            Invoke-Git @('fetch', $Remote, $Branch) | Out-Null
            $retryRebase = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
            if ($retryRebase.Code -ne 0) {
                Invoke-Git @('rebase', '--abort') -AllowFail | Out-Null
                throw "重试前 rebase 失败，本地提交保留：`n$($retryRebase.Output -join [Environment]::NewLine)"
            }
            $push = Invoke-Git @('push', $Remote, "HEAD:$Branch") -AllowFail
            if ($push.Code -ne 0) {
                throw "推送失败：`n$($push.Output -join [Environment]::NewLine)"
            }
        }
        $push.Output | ForEach-Object { Write-Host $_ }
        Write-Host "已推送 $toPush 个提交（本次新增 $committed 个）到 $Remote/$Branch。" -ForegroundColor Green
    }

    # ---------- 退出码 ----------

    if ($failedApps.Count -gt 0) {
        Write-Host ''
        Write-Warning "以下清单检测/提交失败，其余清单不受影响："
        $failedApps | ForEach-Object { Write-Warning "  $_" }
        exit 1
    }
    if ($checkverCode -ne 0 -and $failedApps.Count -eq 0) {
        Write-Warning "checkver 退出码为 $checkverCode"
        exit $checkverCode
    }
    exit 0
} catch {
    Write-Host ''
    Write-Host "错误：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
