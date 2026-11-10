#Requires -Version 5.1
<#
.SYNOPSIS
    Replicate the GitHub Excavator workflow locally: detect new upstream versions,
    update manifests, commit each change and push.

.DESCRIPTION
    Equivalent of .github/workflows/excavator.yml (ScoopInstaller/GithubActions v3
    Excavator). The workflow runs on windows-latest; this script does the same work
    with the locally installed Scoop:

      1. sync origin/<Branch> so we start from the latest commit;
      2. run Scoop's checkver -Update, which rewrites manifests in bucket/ via autoupdate;
      3. commit every changed manifest separately with
         "<app>: Update to version <version>";
      4. rebase once more and push to origin/<Branch>.

    Differences from the workflow:
      * no hub: add/commit/push are done with plain git, so `scoop install hub` is not needed;
      * the workflow's "preinstall hub into the Scoop cache" step only works around
        occasional 504s of hub releases on Actions and is intentionally not replicated;
      * the workflow pins SKIP_UPDATED=1; this script passes -SkipUpdated equivalently.

    This file is intentionally ASCII-only: Windows PowerShell 5.1 reads scripts
    without a BOM as ANSI, so non-ASCII text breaks parsing, and the repository
    tests forbid a UTF-8 BOM. User documentation lives in AGENTS.md (Chinese).

    Prerequisites: Scoop installed, current branch clean and equal to -Branch,
    and preferably a GitHub token (`scoop config gh_token <token>`, or GH_TOKEN /
    GITHUB_TOKEN env vars). Anonymous GitHub API is limited to 60 requests/hour,
    which makes checkver fail with 403 partway through.

.PARAMETER App
    Manifest name to check (supports * wildcard). Default * (all).

.PARAMETER Remote
    Remote name, default origin.

.PARAMETER Branch
    Target branch, default master. The current branch must match.

.PARAMETER CommitMessageFormat
    Commit message template; <app> and <version> are replaced. Default matches Excavator.

.PARAMETER NoPush
    Only update and commit locally, do not push. Useful to preview the commits.

.PARAMETER ThrowError
    Forwarded to checkver: throw on the first manifest failure instead of continuing.

.EXAMPLE
    .\scripts\excavator-local.ps1 -NoPush
    Update and commit locally, without pushing.

.EXAMPLE
    .\scripts\excavator-local.ps1
    Update, commit and push; equivalent to one Excavator run.

.EXAMPLE
    .\scripts\excavator-local.ps1 -App magpie
    Only check and update magpie.
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
    # Older consoles may not allow this; it is cosmetic only.
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
        throw "git $($GitArgs -join ' ') failed (exit code $code):`n$($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ Code = $code; Output = @($output) }
}

# ---------- Preconditions ----------

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    throw "Repository root has no .git: $repoRoot"
}
if (-not (Test-Path -LiteralPath $bucketDir -PathType Container)) {
    throw "Manifest directory not found: $bucketDir"
}

Push-Location $repoRoot
$failedApps = New-Object System.Collections.Generic.List[string]
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git not found; please install Git for Windows'
    }

    # checkver comes from Scoop itself, so SCOOP_HOME is required. SCOOP is needed to
    # locate Scoop's config (e.g. the stored GitHub token).
    if (-not $env:SCOOP_HOME) {
        $env:SCOOP_HOME = (Convert-Path (scoop prefix scoop))
    }
    $checkverPath = Join-Path $env:SCOOP_HOME 'bin\checkver.ps1'
    if (-not (Test-Path -LiteralPath $checkverPath)) {
        throw "Scoop checkver.ps1 not found: $checkverPath (is Scoop installed?)"
    }
    if (-not $env:SCOOP) {
        # SCOOP_HOME looks like <SCOOP>/apps/scoop/current, so go up three levels.
        $env:SCOOP = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $env:SCOOP_HOME))
    }

    $tokenConfigured = $false
    foreach ($name in 'SCOOP_GH_TOKEN', 'GH_TOKEN', 'GITHUB_TOKEN') {
        if ([Environment]::GetEnvironmentVariable($name)) { $tokenConfigured = $true; break }
    }
    if (-not $tokenConfigured) {
        # scoop config prints the value to stdout; capture it without echoing.
        if (scoop config gh_token 2>$null) { $tokenConfigured = $true }
    }
    if (-not $tokenConfigured) {
        Write-Warning 'No GitHub token detected. Anonymous API is limited to 60 requests/hour and checkver may fail with 403. Run: scoop config gh_token <token>'
    }

    $currentBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -ne $Branch) {
        throw "Current branch is $currentBranch but the script requires $Branch (use -Branch to override)."
    }

    $dirty = @(& git status --porcelain --untracked-files=no)
    if ($dirty.Count -gt 0) {
        throw "Working tree has uncommitted changes, please handle them first:`n$($dirty -join [Environment]::NewLine)"
    }

    # ---------- Sync remote ----------

    Write-Step "Syncing $Remote/$Branch"
    Invoke-Git @('fetch', $Remote, $Branch) | Out-Null
    $pull = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
    if ($pull.Code -ne 0) {
        throw "Failed to pull $Remote/$Branch; fix it manually and retry:`n$($pull.Output -join [Environment]::NewLine)"
    }
    $pull.Output | ForEach-Object { Write-Host $_ }

    # ---------- Detect and update manifests ----------

    Write-Step "Running checkver -Update (App=$App)"
    $checkverOutput = & $checkverPath -App $App -Dir $bucketDir -Update -SkipUpdated -ThrowError:$ThrowError 2>&1
    $checkverCode = $LASTEXITCODE
    $checkverOutput | ForEach-Object { Write-Host $_ }

    foreach ($line in $checkverOutput) {
        # checkver only prints per-manifest errors and keeps going; collect them so we
        # can exit non-zero at the end, just like a failed workflow step.
        if ("$line" -match 'rate limit|not valid|not found|failed|error') {
            $failedApps.Add(("$line").Trim())
        }
    }

    # ---------- Commit each manifest ----------

    Write-Step 'Committing changed manifests'
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
            $failedApps.Add("$relative (JSON parse failed: $($_.Exception.Message))")
            continue
        }
        if (-not $manifest.PSObject.Properties['version'] -or -not $manifest.version) {
            $failedApps.Add("$relative (missing version field)")
            continue
        }

        $appName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
        $message = $CommitMessageFormat.Replace('<app>', $appName).Replace('<version>', $manifest.version)

        Invoke-Git @('add', '--', $relative) | Out-Null
        $staged = @(& git diff --cached --name-only -- $relative)
        if ($staged.Count -eq 0) {
            # Line-ending-only changes leave nothing staged; mirror Excavator's skip.
            $skipped.Add($appName)
            continue
        }
        $commit = Invoke-Git @('commit', '-m', $message) -AllowFail
        if ($commit.Code -ne 0) {
            $failedApps.Add("$appName (commit failed: $($commit.Output -join ' '))")
            Invoke-Git @('reset', '--', $relative) -AllowFail | Out-Null
            continue
        }
        $committed++
        Write-Host "Committed: $message" -ForegroundColor Green
    }

    if ($skipped.Count -gt 0) {
        Write-Host "Skipped (line-ending-only changes): $($skipped -join ', ')" -ForegroundColor Yellow
    }

    $ahead = 0
    $countResult = Invoke-Git @('rev-list', '--count', "$Remote/$Branch..HEAD") -AllowFail
    if ($countResult.Code -eq 0) {
        $ahead = [int]("$($countResult.Output[0])".Trim())
    }

    # ---------- Push ----------

    if ($NoPush) {
        Write-Step 'Summary (-NoPush, nothing pushed)'
        Write-Host "New commits: $committed, local is $ahead commit(s) ahead of $Remote/$Branch."
        if ($ahead -gt 0) {
            & git --no-pager log --oneline "$Remote/$Branch..HEAD" | ForEach-Object { Write-Host "  $_" }
        }
    } elseif ($ahead -eq 0 -and $committed -eq 0) {
        Write-Step 'Summary'
        Write-Host 'No manifests need updating.' -ForegroundColor Green
    } else {
        Write-Step "Rebasing onto $Remote/$Branch before push"
        $rebase = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
        if ($rebase.Code -ne 0) {
            Invoke-Git @('rebase', '--abort') -AllowFail | Out-Null
            throw "Pre-push rebase failed; rebase aborted, local commits kept. Fix manually:`n$($rebase.Output -join [Environment]::NewLine)"
        }
        $rebase.Output | ForEach-Object { Write-Host $_ }

        $toPush = 0
        $countResult = Invoke-Git @('rev-list', '--count', "$Remote/$Branch..HEAD") -AllowFail
        if ($countResult.Code -eq 0) {
            $toPush = [int]("$($countResult.Output[0])".Trim())
        }

        Write-Step "Pushing $Remote/$Branch"
        $push = Invoke-Git @('push', $Remote, "HEAD:$Branch") -AllowFail
        if ($push.Code -ne 0) {
            # The remote may have moved (e.g. Excavator); sync and retry once.
            Write-Warning "First push failed, retrying after rebase: $($push.Output -join ' ')"
            Invoke-Git @('fetch', $Remote, $Branch) | Out-Null
            $retryRebase = Invoke-Git @('pull', '--rebase', '--autostash', $Remote, $Branch) -AllowFail
            if ($retryRebase.Code -ne 0) {
                Invoke-Git @('rebase', '--abort') -AllowFail | Out-Null
                throw "Rebase before retry failed; local commits kept:`n$($retryRebase.Output -join [Environment]::NewLine)"
            }
            $push = Invoke-Git @('push', $Remote, "HEAD:$Branch") -AllowFail
            if ($push.Code -ne 0) {
                throw "Push failed:`n$($push.Output -join [Environment]::NewLine)"
            }
        }
        $push.Output | ForEach-Object { Write-Host $_ }
        Write-Host "Pushed $toPush commit(s) ($committed new) to $Remote/$Branch." -ForegroundColor Green
    }

    # ---------- Exit code ----------

    if ($failedApps.Count -gt 0) {
        Write-Host ''
        Write-Warning 'The following manifests failed to check or commit; others were unaffected:'
        $failedApps | ForEach-Object { Write-Warning "  $_" }
        exit 1
    }
    if ($checkverCode -ne 0) {
        Write-Warning "checkver exited with code $checkverCode"
        exit $checkverCode
    }
    exit 0
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
