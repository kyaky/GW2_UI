<#
.SYNOPSIS
    检查上游 GW2_UI 是否有新提交，以及我们的本地补丁集状态。

.DESCRIPTION
    我们跟的是上游的 develop 分支（作者在这里修 12.x 的 secret 问题，比 release 快很多）。
    只读，不改动任何东西。-Update 会打印跟版步骤。

.EXAMPLE
    .\check-upstream.ps1
    .\check-upstream.ps1 -Update
#>
[CmdletBinding()]
param(
    [string]$Upstream = 'Mortalknight/GW2_UI',
    [string]$BaseTag  = 'upstream-develop',
    [string]$Branch   = 'local-fixes',
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $baseSha = (git rev-parse $BaseTag).Substring(0, 7)
    $devSha  = (gh api "repos/$Upstream/commits/develop" -q '.sha') 2>$null
    if (-not $devSha) { throw "无法查询上游 develop" }
    $devSha = $devSha.Substring(0, 7)
    $release = (gh api "repos/$Upstream/releases/latest" -q '.tag_name') 2>$null

    Write-Host ''
    Write-Host "  上游 develop : $devSha" -ForegroundColor Cyan
    Write-Host "  我们的基线   : $baseSha" -ForegroundColor Cyan
    Write-Host "  最新 release : $release  (仅供参考, 我们不跟它)" -ForegroundColor DarkGray

    if ($devSha -eq $baseSha) {
        Write-Host "  状态         : 已是最新" -ForegroundColor Green
    }
    else {
        Write-Host "  状态         : 落后, 有新提交" -ForegroundColor Yellow
        Write-Host ''
        Write-Host "  --- 新提交 ---" -ForegroundColor DarkGray
        $log = gh api "repos/$Upstream/commits?sha=develop&per_page=30" `
                 -q '.[] | "\(.sha[0:7]) \(.commit.author.date[0:10]) \(.commit.message | split("\n")[0])"'
        foreach ($line in $log) {
            if ($line -like "$baseSha*") { break }
            Write-Host "    $line" -ForegroundColor DarkGray
        }
    }

    $commits = @(git log --format='%h %s' "$BaseTag..$Branch")
    $files   = @(git diff --name-only "$BaseTag..$Branch")
    Write-Host ''
    Write-Host "  本地补丁     : $($commits.Count) 个提交, $($files.Count) 个文件" -ForegroundColor Cyan
    foreach ($c in $commits) { Write-Host "                 $c" -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host "  --- 我们改的文件 ---" -ForegroundColor DarkGray
    foreach ($f in $files) { Write-Host "    $f" -ForegroundColor DarkGray }

    if ($Update -and $devSha -ne $baseSha) {
        Write-Host ''
        Write-Host "  --- 跟版步骤 ---" -ForegroundColor Cyan
        Write-Host @"
    git fetch --depth=1 origin develop
    git rebase --onto FETCH_HEAD $BaseTag $Branch
    # 有冲突就逐个解决, 然后 git rebase --continue
    # 冲突常意味着上游自己修好了 —— 那就直接删掉我们对应的补丁
    git tag -f upstream-develop FETCH_HEAD
    .\deploy.ps1 -DryRun
    .\deploy.ps1
    # 上游删除的文件 deploy 不会清理, 手动处理:
    #   git diff --name-status <旧基线>..upstream-develop | grep '^D'
    git push --force-with-lease fork $Branch
"@ -ForegroundColor White
        Write-Host ''
        Write-Host "    跟版后重跑语法校验, 并在游戏里 /reload 验证" -ForegroundColor Yellow
    }
    Write-Host ''
}
finally {
    Pop-Location
}
