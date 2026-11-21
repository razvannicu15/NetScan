# NetScan - build in GitHub Actions and download APK + EXE into dist\
# Called by NetScan.bat. Needs only Git; installs GitHub CLI on first run.
param([string]$AppDir = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Continue'
$Repo = 'razvannicu15/NetScan'

function Fail($msg) {
    Write-Host ''
    Write-Host "  EROARE: $msg" -ForegroundColor Red
    exit 1
}

function Step($msg) {
    Write-Host ''
    Write-Host "  >> $msg" -ForegroundColor Cyan
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------------------------------------------------------- GitHub CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Step 'Instalez GitHub CLI (doar prima data)...'
    winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements
    Refresh-Path
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $p = 'C:\Program Files\GitHub CLI'
        if (Test-Path "$p\gh.exe") { $env:Path += ";$p" }
    }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Fail 'GitHub CLI nu s-a putut instala. Inchide fereastra, deschide din nou NetScan.bat si reincearca.'
    }
}

gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Step 'Conectare la GitHub - se deschide browserul, apasa Authorize (doar prima data)...'
    gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Fail 'Autentificarea la GitHub a esuat.' }
}
gh auth setup-git 2>&1 | Out-Null

# ---------------------------------------------------------------- version
Set-Location $AppDir
Step 'Actualizez codul...'
git pull --ff-only 2>&1 | Out-Host
git fetch --tags --force 2>&1 | Out-Null

$last = git tag --list 'v*' --sort=-v:refname | Select-Object -First 1
if ($last -match '^v(\d+)\.(\d+)\.(\d+)$') {
    $new = "v$($Matches[1]).$($Matches[2]).$([int]$Matches[3] + 1)"
} else {
    $new = 'v1.0.0'
}

Step "Pornesc build-ul in cloud pentru $new ..."
git push origin HEAD 2>&1 | Out-Host
git tag $new
git push origin $new 2>&1 | Out-Host
if ($LASTEXITCODE -ne 0) { git tag -d $new | Out-Null; Fail 'Nu am putut trimite tag-ul pe GitHub.' }

# ---------------------------------------------------------------- wait
$runId = $null
for ($i = 0; $i -lt 30 -and -not $runId; $i++) {
    Start-Sleep -Seconds 4
    $json = gh run list -R $Repo --workflow build.yml --limit 20 --json databaseId,headBranch 2>$null
    if ($json) {
        $run = ($json | ConvertFrom-Json) | Where-Object { $_.headBranch -eq $new } | Select-Object -First 1
        if ($run) { $runId = $run.databaseId }
    }
}
if (-not $runId) { Fail 'Build-ul nu a pornit pe GitHub. Verifica tab-ul Actions.' }

Step 'Compilez APK + EXE pe serverele GitHub (aprox. 8-12 minute)...'
Write-Host "     https://github.com/$Repo/actions/runs/$runId"
gh run watch $runId -R $Repo --exit-status --interval 20
if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '  Ultimele linii din log:' -ForegroundColor Yellow
    gh run view $runId -R $Repo --log-failed 2>$null | Select-Object -Last 40 | Out-Host
    Fail "Build-ul a esuat. Detalii: https://github.com/$Repo/actions/runs/$runId"
}

# ---------------------------------------------------------------- download
Step 'Descarc fisierele...'
$dist = Join-Path $AppDir 'dist'
$tmp = Join-Path $dist '_download'
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force $tmp | Out-Null
gh run download $runId -R $Repo -D $tmp
if ($LASTEXITCODE -ne 0) { Fail 'Descarcarea a esuat.' }

Get-ChildItem $tmp -Recurse -Include *.apk, *.zip | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $dist $_.Name) -Force
}
Remove-Item -Recurse -Force $tmp

$zip = Join-Path $dist 'NetScan-windows.zip'
$winDir = Join-Path $dist 'NetScan-windows'
if (Test-Path $zip) {
    if (Test-Path $winDir) { Remove-Item -Recurse -Force $winDir }
    Expand-Archive $zip -DestinationPath $winDir -Force
}

Write-Host ''
Write-Host "  ======  GATA: NetScan $new  ======" -ForegroundColor Green
Write-Host "  APK : $dist\NetScan-android.apk"
Write-Host "  EXE : $winDir\NetScan.exe"
Start-Process explorer.exe $dist
exit 0
