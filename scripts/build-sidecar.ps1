param(
    [string]$KimiCliHome,
    [switch]$InstallDeps
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$adapterRoot = Join-Path $projectRoot "sidecar-adapter"
$sidecarDir = Join-Path (Join-Path $projectRoot "src-tauri") "sidecar"
$distDir = Join-Path $adapterRoot "dist"
$buildDir = Join-Path $adapterRoot "build"
$entryScript = Join-Path $adapterRoot "pyinstaller-entrypoint.py"
$targetExe = Join-Path $sidecarDir "kimi-sidecar-x86_64-pc-windows-msvc.exe"
$manifestPath = Join-Path $sidecarDir "kimi-sidecar.manifest.json"

function Invoke-Native {
    param(
        [string]$Command,
        [string[]]$Arguments = @()
    )

    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $commandText = (@($Command) + $Arguments) -join " "
        throw "Command failed with exit code $exitCode`: $commandText"
    }
}

function Invoke-NativeOutput {
    param(
        [string]$Command,
        [string[]]$Arguments = @()
    )

    $output = & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $commandText = (@($Command) + $Arguments) -join " "
        throw "Command failed with exit code $exitCode`: $commandText"
    }
    return $output
}

function Invoke-SidecarRuntimeInfo {
    param([string]$SidecarPath)

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process `
            -FilePath $SidecarPath `
            -ArgumentList @("__desktop-runtime-info") `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutFile `
            -RedirectStandardError $stderrFile

        $stdout = ""
        if (Test-Path $stdoutFile) {
            $stdout = Get-Content -LiteralPath $stdoutFile -Raw
        }

        $stderr = ""
        if (Test-Path $stderrFile) {
            $stderr = Get-Content -LiteralPath $stderrFile -Raw
        }

        if ($process.ExitCode -ne 0) {
            throw "Sidecar runtime-info command failed with exit code $($process.ExitCode): $($stderr.Trim())"
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) {
            throw "Sidecar runtime-info command produced no stdout. Stderr: $($stderr.Trim())"
        }

        $info = $stdout | ConvertFrom-Json
        if (-not $info.available) {
            throw "Sidecar runtime-info reported unavailable runtime: $stdout"
        }
        if ([string]::IsNullOrWhiteSpace([string]$info.kimiCliVersion)) {
            throw "Sidecar runtime-info did not report kimiCliVersion: $stdout"
        }

        return $info
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Get-GitValue {
    param([string[]]$GitArgs)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        return $null
    }

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $value = & git @GitArgs 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($exitCode -eq 0 -and $value) {
        return ($value -join "`n").Trim()
    }
    return $null
}

# ---------------------------------------------------------------------------
# 1. Discover Kimi CLI installation
# ---------------------------------------------------------------------------
$kimiCliHome = $null

if ($KimiCliHome) {
    $kimiCliHome = $KimiCliHome
    Write-Host "Using Kimi CLI home from -KimiCliHome parameter: $kimiCliHome"
}
elseif ($env:KIMI_CLI_HOME) {
    $kimiCliHome = $env:KIMI_CLI_HOME
    Write-Host "Using Kimi CLI home from KIMI_CLI_HOME environment variable: $kimiCliHome"
}
elseif (Test-Path (Join-Path $env:USERPROFILE ".kimi")) {
    $candidate = Join-Path $env:USERPROFILE ".kimi"
    if ((Test-Path (Join-Path $candidate "Lib\site-packages\kimi_cli")) -or
        (Test-Path (Join-Path $candidate "Scripts\python.exe"))) {
        $kimiCliHome = $candidate
        Write-Host "Using Kimi CLI home from ~\.kimi: $kimiCliHome"
    }
}

if (-not $kimiCliHome) {
    $uvToolPath = Join-Path $env:APPDATA "uv\tools\kimi-cli"
    if (Test-Path $uvToolPath) {
        $kimiCliHome = $uvToolPath
        Write-Host "Using Kimi CLI home from uv tools: $kimiCliHome"
    }
}

if (-not $kimiCliHome) {
    $kimiCmd = Get-Command kimi -ErrorAction SilentlyContinue
    if ($kimiCmd) {
        # Assume uv tool convention
        $uvToolPath = Join-Path $env:APPDATA "uv\tools\kimi-cli"
        if (Test-Path $uvToolPath) {
            $kimiCliHome = $uvToolPath
            Write-Host "Using Kimi CLI home derived from 'kimi' command (uv tool): $kimiCliHome"
        }
    }
}

if (-not $kimiCliHome) {
    throw @"
Could not locate the Kimi CLI installation.

Tried the following (in order):
  1. -KimiCliHome parameter
  2. `$env:KIMI_CLI_HOME`
  3. $env:USERPROFILE\.kimi
  4. $env:APPDATA\uv\tools\kimi-cli
  5. 'kimi' command on PATH (uv tool convention)

Please install Kimi CLI or pass -KimiCliHome explicitly.
"@
}

# ---------------------------------------------------------------------------
# 2. Validate Kimi CLI package is importable
# ---------------------------------------------------------------------------
$pythonExe = Join-Path $kimiCliHome "Scripts\python.exe"
if (!(Test-Path $pythonExe)) {
    throw "Found Kimi CLI environment at $kimiCliHome but could not find python.exe at $pythonExe"
}

Write-Host "Validating kimi_cli package import..."
$kimiCliSitePackages = Invoke-NativeOutput $pythonExe @("-c", "import kimi_cli, pathlib; print(pathlib.Path(kimi_cli.__file__).parent.parent)")

if (-not $kimiCliSitePackages) {
    throw "Found Kimi CLI environment at $kimiCliHome but could not import kimi_cli package. Make sure the environment contains the full kimi_cli Python package."
}

$kimiCliSitePackages = $kimiCliSitePackages.Trim()
Write-Host "kimi_cli package located at: $kimiCliSitePackages"

# ---------------------------------------------------------------------------
# 3. Cleanup old build artifacts
# ---------------------------------------------------------------------------
if (Test-Path $buildDir) {
    Remove-Item $buildDir -Recurse -Force
    Write-Host "Cleaned up old build directory: $buildDir"
}
if (Test-Path $distDir) {
    Remove-Item $distDir -Recurse -Force
    Write-Host "Cleaned up old dist directory: $distDir"
}
$specFile = Join-Path $adapterRoot "kimi-sidecar.spec"
if (Test-Path $specFile) {
    Remove-Item $specFile -Force
    Write-Host "Cleaned up old spec file: $specFile"
}

if (!(Test-Path $sidecarDir)) {
    New-Item -ItemType Directory -Path $sidecarDir -Force | Out-Null
}

Push-Location $adapterRoot
try {
    # -----------------------------------------------------------------------
    # 4. Sync dependencies
    # -----------------------------------------------------------------------
    Write-Host "Installing sidecar adapter dependencies..."
    Invoke-Native "uv" @("sync", "--dev")

    # -----------------------------------------------------------------------
    # 5. Inject kimi_cli into adapter .venv via .pth file
    # -----------------------------------------------------------------------
    $venvSitePackages = Get-ChildItem -Path (Join-Path $adapterRoot ".venv\Lib") -Filter "site-packages" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $venvSitePackages) {
        throw "Could not find .venv\Lib\site-packages inside $adapterRoot. Did 'uv sync' succeed?"
    }
    $pthFile = Join-Path $venvSitePackages.FullName "kimi_cli.pth"
    "import site; site.addsitedir(r'$kimiCliSitePackages')" | Set-Content -Encoding UTF8 $pthFile
    Write-Host "Injected kimi_cli path into .venv via: $pthFile"

    # -----------------------------------------------------------------------
    # 6. Generate PyInstaller entrypoint
    # -----------------------------------------------------------------------
    @"
from kimi_desktop_sidecar.__main__ import main

if __name__ == "__main__":
    raise SystemExit(main())
"@ | Set-Content -Encoding UTF8 $entryScript

    # -----------------------------------------------------------------------
    # 7. Build with PyInstaller
    # -----------------------------------------------------------------------
    Write-Host "Building desktop sidecar adapter..."
    try {
        Invoke-Native "uv" @(
            "run",
            "pyinstaller",
            "--onefile",
            "--noconsole",
            "--name", "kimi-sidecar",
            "--distpath", $distDir,
            "--workpath", $buildDir,
            "--collect-data", "kimi_cli",
            "--collect-submodules", "kimi_cli.tools",
            "--collect-submodules", "kimi_cli.subagents",
            "--collect-submodules", "kimi_cli.background",
            "--noconfirm",
            $entryScript
        )
    }
    finally {
        if (Test-Path $entryScript) {
            Remove-Item $entryScript -Force
        }
        if (Test-Path $specFile) {
            Remove-Item $specFile -Force
        }
    }

    $sourceExe = Join-Path $distDir "kimi-sidecar.exe"
    if (!(Test-Path $sourceExe)) {
        throw "Could not find built executable: $sourceExe"
    }

    Copy-Item $sourceExe $targetExe -Force
    $targetItem = Get-Item $targetExe
    $hash = Get-FileHash -Algorithm SHA256 $targetExe
    $kimiCliVersion = Invoke-NativeOutput $pythonExe @("-c", "import importlib.metadata; print(importlib.metadata.version('kimi-cli'))")
    $runtimeInfo = Invoke-SidecarRuntimeInfo $targetExe
    $sourceKimiCliVersion = ($kimiCliVersion -join "`n").Trim()
    if ($runtimeInfo.kimiCliVersion -ne $sourceKimiCliVersion) {
        throw "Built sidecar reports kimi-cli $($runtimeInfo.kimiCliVersion), but source environment reports $sourceKimiCliVersion."
    }
    Write-Host "Runtime info command validated: kimi-cli $sourceKimiCliVersion"

    $manifest = [ordered]@{
        schema = 1
        createdAt = (Get-Date).ToUniversalTime().ToString("o")
        command = "npm run sidecar:build"
        target = $targetItem.FullName
        bytes = $targetItem.Length
        sha256 = $hash.Hash
        kimiCliHome = $kimiCliHome
        kimiCliSitePackages = $kimiCliSitePackages
        kimiCliVersion = $sourceKimiCliVersion
        runtimeInfoCommand = "__desktop-runtime-info"
        git = [ordered]@{
            commit = Get-GitValue @("rev-parse", "HEAD")
            shortCommit = Get-GitValue @("rev-parse", "--short", "HEAD")
            dirty = [bool](Get-GitValue @("status", "--short"))
        }
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8

    Write-Host "Sidecar copied to: $targetExe"
    Write-Host "Sidecar manifest written to: $manifestPath"
}
finally {
    Pop-Location
}
