#Requires -Version 7
<#
.SYNOPSIS
    Publishes TokenSaver.MCP self-contained into build/staging/TokenSaver.MCP, ready for
    src/Installers/TokenSaver.Setup/TokenSaver.Setup.wixproj to package.

.DESCRIPTION
    This is the "build" half of the TokenSaver installer story; the WiX project is the
    "package" half. They're kept separate (rather than having the wixproj shell out to
    dotnet publish itself) because a real PowerShell script gives better error output if
    `dotnet publish` fails than trying to invoke it as an MSBuild pre-step.

.PARAMETER Version
    Version string baked into the installer via -p:MyAppVersion. Defaults to the version
    Nerdbank.GitVersioning computes from version.json + git height (see docs/versioning.md);
    falls back to "1.0.0" if the `nbgv` tool isn't installed or git metadata isn't available
    (e.g. a shallow checkout). Pass -Version explicitly to override either default.

.PARAMETER Configuration
    dotnet build configuration. Defaults to "Release".

.PARAMETER Runtime
    .NET runtime identifier. Defaults to "win-x64".

.PARAMETER Pack
    After publishing, also invoke `dotnet build` on the WiX project to produce
    build/dist/TokenSaver-Setup-<Version>.msi. Requires the WiX .NET tool
    (`dotnet tool install --global wix`) — the wixproj itself only needs the WiX NuGet SDK,
    restored automatically on build.

.EXAMPLE
    .\publish-tokensaver-for-wix.ps1
    .\publish-tokensaver-for-wix.ps1 -Version 1.2.0 -Pack
#>
[CmdletBinding()]
param(
    [string] $Version       = "",
    [string] $Configuration = "Release",
    [string] $Runtime       = "win-x64",
    [switch] $Pack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot   = $PSScriptRoot | Split-Path -Parent
$CsProj     = Join-Path $RepoRoot "src\Host\TokenSaver.MCP\TokenSaver.MCP.csproj"
# Staged on the OS temp drive (NTFS), NOT under the repo: wixnative.exe's cabinet compression
# (legacy Win32 FCI API) cannot read self-contained publish output from a ReFS volume, which is
# what this repo may live on. See the matching comment on PublishDir in
# TokenSaver.Setup.wixproj for how this was diagnosed.
$StageDir   = Join-Path $env:TEMP "TokenSaverWixStage"
$WixProj    = Join-Path $RepoRoot "src\Installers\TokenSaver.Setup\TokenSaver.Setup.wixproj"

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    OK  $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    WARN $msg" -ForegroundColor Yellow }

# ── 1. Prerequisites ───────────────────────────────────────────────────────────

Write-Step "Checking prerequisites"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw ".NET SDK not found. Install it from https://dot.net and re-run."
}
Write-Ok ".NET SDK $(dotnet --version)"

if ([string]::IsNullOrWhiteSpace($Version)) {
    if (Get-Command nbgv -ErrorAction SilentlyContinue) {
        $nbgvVersion = (nbgv get-version --project $RepoRoot --format json 2>$null | ConvertFrom-Json).SimpleVersion
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($nbgvVersion)) {
            $Version = $nbgvVersion
            Write-Ok "Version resolved via nbgv: $Version"
        } else {
            $Version = "1.0.0"
            Write-Warn "nbgv could not resolve a version (shallow clone / no git history?) — falling back to $Version"
        }
    } else {
        $Version = "1.0.0"
        Write-Warn "nbgv CLI not found (install with: dotnet tool install --global nbgv) — falling back to $Version"
    }
}

# ── 2. Publish ─────────────────────────────────────────────────────────────────

Write-Step "Publishing TokenSaver.MCP"

if (Test-Path $StageDir) {
    Remove-Item $StageDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

dotnet publish $CsProj `
    --configuration $Configuration `
    --runtime       $Runtime `
    --self-contained true `
    --output        $StageDir

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed (exit $LASTEXITCODE)"
}

$exePath = Join-Path $StageDir "TokenSaver.MCP.exe"
if (-not (Test-Path $exePath)) {
    throw "Publish succeeded but exe not found at: $exePath"
}

$size = (Get-Item $exePath).Length / 1MB
Write-Ok "TokenSaver.MCP.exe  ($([math]::Round($size, 1)) MB)  -> $StageDir"

# ── 3. Optionally build the installer ──────────────────────────────────────────

if ($Pack) {
    Write-Step "Building installer with WiX"

    if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
        throw "wix CLI not found on PATH. Install it with: dotnet tool install --global wix"
    }

    $distDir = Join-Path $RepoRoot "build\dist"
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null

    dotnet build $WixProj -c $Configuration -p:MyAppVersion=$Version "-p:PublishDir=$StageDir"

    if ($LASTEXITCODE -ne 0) {
        throw "WiX build failed (exit $LASTEXITCODE)"
    }

    $outFile = Join-Path $distDir "TokenSaver-Setup-$Version.msi"
    if (Test-Path $outFile) {
        $outSize = (Get-Item $outFile).Length / 1MB
        Write-Ok "$outFile  ($([math]::Round($outSize, 1)) MB)"
    } else {
        Write-Host "    WARN Expected output not found at $outFile — check build output above." -ForegroundColor Yellow
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "  Staged build : $StageDir"
if ($Pack) {
    Write-Host "  Installer    : build\dist\TokenSaver-Setup-$Version.msi"
} else {
    Write-Host "  Next step    : dotnet build src\Installers\TokenSaver.Setup\TokenSaver.Setup.wixproj -p:MyAppVersion=$Version"
}
Write-Host ""
