param(
    [switch]$SkipSecretScan
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SidecarExe = Join-Path $ProjectRoot "src-tauri\sidecar\kimi-sidecar-x86_64-pc-windows-msvc.exe"
$SidecarManifest = Join-Path $ProjectRoot "src-tauri\sidecar\kimi-sidecar.manifest.json"
$TauriConfig = Join-Path $ProjectRoot "src-tauri\tauri.conf.json"

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "==> $Name"
    & $Action
}

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

function Invoke-SecretScan {
    if ($SkipSecretScan) {
        Write-Host "Secret scan skipped by request."
        return
    }

    $rg = Get-Command rg -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-Warning "ripgrep is not installed; skipping high-confidence secret scan."
        return
    }

    $pattern = "(AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY)"
    $args = @(
        "-n",
        "-i",
        $pattern,
        "-g", "!node_modules",
        "-g", "!dist",
        "-g", "!src-tauri/target",
        "-g", "!src-tauri/gen",
        "-g", "!sidecar-adapter/.venv",
        "-g", "!sidecar-adapter/build",
        "-g", "!sidecar-adapter/dist"
    )

    $output = & rg @args 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "High-confidence secret pattern found. Review the matches before release."
    }
    if ($exitCode -gt 1) {
        $output | ForEach-Object { Write-Host $_ }
        throw "Secret scan failed with exit code $exitCode."
    }

    Write-Host "No high-confidence secrets found."
}

function Test-CargoClippy {
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & cargo clippy --version 2>$null | Out-Null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    return $exitCode -eq 0
}

function Assert-SidecarManifest {
    if (!(Test-Path $SidecarExe)) {
        throw "Missing sidecar executable: $SidecarExe. Run npm run sidecar:build before releasing."
    }
    if (!(Test-Path $SidecarManifest)) {
        throw "Missing sidecar manifest: $SidecarManifest. Run npm run sidecar:build before releasing."
    }

    $manifest = Get-Content $SidecarManifest -Raw | ConvertFrom-Json
    $hash = (Get-FileHash -Algorithm SHA256 $SidecarExe).Hash
    if ($manifest.sha256 -ne $hash) {
        throw "Sidecar manifest hash does not match $SidecarExe. Run npm run sidecar:build."
    }

    $sizeMb = [math]::Round((Get-Item $SidecarExe).Length / 1MB, 2)
    Write-Host "Sidecar found: $SidecarExe ($sizeMb MiB)"
    Write-Host "Sidecar manifest: $SidecarManifest"
}

function Assert-TauriWindowUrls {
    if (!(Test-Path $TauriConfig)) {
        throw "Missing Tauri config: $TauriConfig"
    }

    $config = Get-Content $TauriConfig -Raw | ConvertFrom-Json
    $windows = @($config.app.windows)
    if (-not $windows) {
        Write-Host "No Tauri app windows declared."
        return
    }

    foreach ($window in $windows) {
        $label = if ($window.label) { $window.label } else { "<unnamed>" }
        $url = $window.url

        if ($null -eq $url -or [string]::IsNullOrWhiteSpace([string]$url)) {
            Write-Host "Tauri window '$label' uses the default local entry: index.html"
            continue
        }

        $urlText = ([string]$url).Trim()
        if ($urlText -match "^[A-Za-z][A-Za-z0-9+.-]*://") {
            throw "Invalid Tauri window url for '$label': $urlText. Packaged releases must use 'index.html' or another relative app asset path."
        }
    }

    Write-Host "Tauri window URLs are local asset paths."
}

function Invoke-GitQuiet {
    param([string[]]$GitArgs)

    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & git @GitArgs 2>$null
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Show-GitState {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) {
        Write-Warning "git is not installed; release metadata will not include a commit hash."
        return
    }

    $insideWorkTree = Invoke-GitQuiet -GitArgs @("rev-parse", "--is-inside-work-tree")
    if ($insideWorkTree.ExitCode -ne 0) {
        Write-Warning "This project is not inside a git repository."
        return
    }

    $headCheck = Invoke-GitQuiet -GitArgs @("rev-parse", "--verify", "HEAD")
    if ($headCheck.ExitCode -ne 0) {
        Write-Warning "Git repository has no commits yet."
    } else {
        $head = Invoke-GitQuiet -GitArgs @("rev-parse", "--short", "HEAD")
        if ($head.ExitCode -eq 0 -and $head.Output) {
            Write-Host "Git HEAD: $($head.Output)"
        }
    }

    $gitStatus = Invoke-GitQuiet -GitArgs @("status", "--short")
    $status = @($gitStatus.Output)
    if ($status) {
        Write-Warning "Working tree has uncommitted changes:"
        $status | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
        if ($status.Count -gt 30) {
            Write-Host "  ... $($status.Count - 30) more entries"
        }
    } else {
        Write-Host "Git working tree is clean."
    }
}

Push-Location $ProjectRoot
try {
    Invoke-Step "Building sidecar binary" {
        Invoke-Native "npm" @("run", "sidecar:build")
    }

    Invoke-Step "Checking required sidecar binary" {
        Assert-SidecarManifest
    }

    Invoke-Step "Checking Tauri packaged window entry" {
        Assert-TauriWindowUrls
    }

    Invoke-Step "Frontend unit tests" {
        Invoke-Native "npm" @("run", "test")
    }

    Invoke-Step "Version alignment check" {
        Invoke-Native "node" @("scripts/sync-version.js")
    }

    Invoke-Step "Frontend production build" {
        Invoke-Native "npm" @("run", "build")
    }

    Invoke-Step "Rust check" {
        Invoke-Native "npm" @("run", "rust:check")
    }

    Invoke-Step "Rust clippy lint gate" {
        if (-not (Test-CargoClippy)) {
            throw "cargo-clippy is not installed. Run: rustup component add clippy"
        }
        Invoke-Native "npm" @("run", "rust:clippy")
    }

    Invoke-Step "Tauri no-bundle release build" {
        Invoke-Native "npm" @("run", "desktop:release")
    }

    Invoke-Step "Python sidecar compile check" {
        Push-Location (Join-Path $ProjectRoot "sidecar-adapter")
        try {
            Invoke-Native "python" @("-m", "compileall", "-q", "kimi_desktop_sidecar")
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Python sidecar tests" {
        Push-Location (Join-Path $ProjectRoot "sidecar-adapter")
        try {
            Invoke-Native "uv" @("run", "pytest", "-q")
        } finally {
            Pop-Location
        }
    }

    Invoke-Step "Dependency audit gate" {
        Invoke-Native "npm" @("audit", "--audit-level=high")
    }

    Invoke-Step "High-confidence secret scan" {
        Invoke-SecretScan
    }

    Invoke-Step "Git release traceability" {
        Show-GitState
    }
}
finally {
    Pop-Location
}
