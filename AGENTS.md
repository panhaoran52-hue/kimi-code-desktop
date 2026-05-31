# Agent Guide For Kimi Code Desktop

This repository is an independent desktop shell for Kimi Code. It is not the
`kimi-cli` source tree. The desktop app reuses the installed Kimi CLI runtime
through a Python sidecar adapter.

Authoritative development rules are in `docs/DEVELOPMENT_STANDARD.md`. Keep
this file and every handoff aligned with that standard.

## Runtime Chain

```text
React/Tauri frontend
  -> Tauri IPC/events
  -> Rust WireProcessManager in src-tauri/src/sidecar.rs
  -> kimi-sidecar __desktop-worker <session_id>
  -> stdio NDJSON Wire protocol
  -> Kimi CLI Python runtime
```

Native desktop helper calls use:

```text
Tauri command
  -> Rust call_desktop_api()
  -> shared kimi-sidecar __desktop-api-server
```

## Hard Rules

- Keep daily work in development mode by default.
- Use `npm run desktop` or `start.bat` for daily launch.
- Use `npm run desktop:release` for a local runnable release exe.
- Use `npm run release:msi` for a distributable MSI.
- Use `npm run sidecar:build` to build the sidecar source binary.
- Keep MSI startup readiness and uninstall behavior inside the packaged app and
  installer path, not only in `start.bat`.
- Do not recommend `cargo build --release` as a runnable desktop build.
- Do not let an old release exe, old MSI, or old sidecar silently stand in for
  the current source tree.
- Do not move desktop-only helper code into the `kimi_cli` Python package.
- Do not revert unrelated uncommitted work.

## Canonical Commands

```powershell
npm run desktop
npm run desktop:dev
npm run desktop:release
npm run release:preflight
npm run release:msi
npm run sidecar:build
npm run version:sync
```

Compatibility aliases exist:

```powershell
npm run tauri:dev      # delegates to desktop:dev
npm run tauri:build    # delegates to release:msi
```

Prefer the `desktop:*` and `release:*` names in docs and handoffs.

## Files To Know

```text
src/lib/tauri-api.ts
src/hooks/useSessionStream.ts
src/hooks/wireTypes.ts
src-tauri/src/commands.rs
src-tauri/src/sidecar.rs
sidecar-adapter/kimi_desktop_sidecar/
scripts/desktop-release.ps1
scripts/release-preflight.ps1
scripts/release-msi.ps1
scripts/build-sidecar.ps1
docs/DEVELOPMENT_STANDARD.md
docs/RELEASE.md
```

## Verification

For normal code changes:

```powershell
npm test
cargo check --manifest-path src-tauri/Cargo.toml
npm run build
```

For release-related changes:

```powershell
npm run release:preflight
```

For MSI packaging changes:

```powershell
npm run release:msi
```

## Version Contract

Desktop shell version alignment is checked by:

```powershell
npm run version:sync
```

It covers:

```text
package.json
package-lock.json
src-tauri/Cargo.toml
src-tauri/tauri.conf.json
```

The desktop shell version is not the same thing as the runtime Kimi CLI version.
UI that displays the CLI version must use runtime probing of the installed CLI.

## Sub-Agent Boundaries

When using multiple coding agents, split work by ownership:

```text
Frontend agent: src/ and React state/UI behavior
Rust agent: src-tauri/src/ commands, sidecar process orchestration, tray/notify
Sidecar agent: sidecar-adapter/ Python adapter code
Release agent: package scripts, PowerShell release scripts, docs, Tauri config
```

Agents are not alone in this worktree. They must inspect current status, avoid
reverting unrelated edits, and keep command names aligned with the canonical
workflow above.
