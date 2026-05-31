# Release Guide

This project publishes the Windows desktop app as an MSI bundle by default.
The MSI path avoids the NSIS bootstrap download and is the stable release lane.
Release work must follow `docs/DEVELOPMENT_STANDARD.md`.

## Prerequisites

- Node.js and npm
- Rust stable toolchain with the MSVC target
- Python 3.12 or newer
- `uv`
- Kimi CLI installed with `uv tool install kimi-cli`
- `rg` for the high-confidence secret scan
- `src-tauri/sidecar/kimi-sidecar-x86_64-pc-windows-msvc.exe`

Build the sidecar with:

```powershell
npm run sidecar:build
```

## Preflight

Run all release gates without producing an installer:

```powershell
npm run release:preflight
```

The preflight checks:

- sidecar rebuild and sidecar manifest validation
- frontend production build
- Rust compile check
- Rust clippy lint gate
- Python sidecar compile check
- Python sidecar tests
- npm audit for high or critical advisories
- high-confidence secret patterns
- git release traceability

The installed MSI starts the Tauri executable directly, so release readiness
must not depend on `start.bat`. The app checks the bundled sidecar runtime
through `kimi-sidecar __desktop-runtime-info`, then checks user `config.toml`,
credential sources, and the optional external `kimi` login helper before
session APIs are loaded.

## Build MSI

```powershell
npm run release:msi
```

The script writes the MSI plus:

- `SHA256SUMS.txt`
- `release-manifest.json`

Both files are placed next to the MSI under:

```text
src-tauri/target/release/bundle/msi/
```

Before building, the release script clears previous MSI metadata in that folder.
It then accepts only a fresh MSI that matches the current `package.json` version,
so a failed build cannot accidentally publish an older installer.

The MSI build also validates uninstall support in the generated WiX manifest:
the WiX `upgradeCode` must be pinned, Windows Apps uninstall metadata must be
present, and the Start Menu must contain `Uninstall Kimi Code` pointing to
`msiexec /x [ProductCode]`.

## Uninstall

The packaged app can be removed through either normal Windows entry point:

- Windows Settings > Apps > Installed apps > Kimi Code > Uninstall
- Start Menu > Kimi Code > Uninstall Kimi Code

For command-line uninstall while the original MSI is available:

```powershell
msiexec.exe /x ".\Kimi Code_<version>_x64_en-US.msi"
```

Uninstall removes installed app files and shortcuts. It intentionally preserves
`~\.kimi`, including `config.toml` and credentials, because those files belong
to the shared Kimi CLI runtime and should survive upgrades or reinstall attempts.

## GitHub Release

The repository includes `.github/workflows/release.yml` for the public Windows
release lane. It builds the MSI on `windows-latest`, uploads the workflow
artifact, and publishes these files to a GitHub Release:

- `*.msi`
- `SHA256SUMS.txt`
- `release-manifest.json`
- `kimi-code-desktop.release.json`

The workflow installs the Kimi CLI runtime with `uv tool install kimi-cli`
before running `npm run release:msi`, matching the path that
`scripts/build-sidecar.ps1` discovers on a clean Windows runner.

Publish by pushing a version tag:

```powershell
npm run version:set 0.1.0
git add package.json package-lock.json src-tauri/Cargo.toml src-tauri/tauri.conf.json
git commit -m "Release v0.1.0"
git tag v0.1.0
git push origin master --tags
```

You can also run the `Release` workflow manually from GitHub Actions. Provide a
tag such as `v0.1.0`, or leave it blank to use `v<package.json version>`.

## NSIS Installer

NSIS can still be built explicitly:

```powershell
npm run tauri:build:nsis
```

This path may download NSIS from the Tauri binary release mirror. Use it only
when the build machine has the dependency cached or network access is stable.

## Windows Code Signing

Unsigned Windows builds may trigger SmartScreen or publisher warnings. To sign
artifacts after an MSI build, install the Windows SDK and provide either a PFX
certificate or a certificate thumbprint:

```powershell
$env:WINDOWS_CERT_PATH = "C:\path\to\certificate.pfx"
$env:WINDOWS_CERT_PASSWORD = "pfx-password"
npm run release:msi -- -Sign
```

Or sign with a certificate installed in the Windows certificate store:

```powershell
$env:WINDOWS_CERT_SHA1 = "CERTIFICATE_THUMBPRINT"
npm run release:msi -- -Sign
```

Optional:

```powershell
$env:SIGNTOOL_EXE = "C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe"
$env:WINDOWS_TIMESTAMP_URL = "http://timestamp.digicert.com"
```

## Versioning

Keep these values in sync before a public release:

- `package.json` version
- `package-lock.json` version
- `src-tauri/tauri.conf.json` version
- `src-tauri/Cargo.toml` version

Check or set them with:

```powershell
npm run version:sync
npm run version:set 0.1.0
```

The release manifest records the git commit when the project is inside a git
repository. Create a tag for public releases:

```powershell
git tag v<version>
```
