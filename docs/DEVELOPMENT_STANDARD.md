# Development Standard

This document is the project standard for everyday development, sub-agent work,
builds, release validation, and handoff. When another document or agent
disagrees with this file, update the other document to match this one.

## Operating Mode

The project stays in active development mode by default.

Daily launch:

```powershell
npm run desktop
```

Batch launch:

```bat
start.bat
```

Both paths start the Tauri dev app. They must not silently prefer an old release
executable.

Release launch is explicit:

```bat
start.bat release
```

Release mode may launch only a verified executable produced by:

```powershell
npm run desktop:release
```

## Canonical Commands

Use these names in docs, issues, handoffs, and agent prompts:

```powershell
npm run desktop          # daily development
npm run desktop:dev      # explicit Tauri dev
npm run desktop:release  # local runnable release exe
npm run release:preflight
npm run release:msi      # MSI installer and metadata
npm run sidecar:build
npm run version:sync
npm run version:set <version>
```

Compatibility aliases may remain in `package.json`, but they are not the
preferred language for normal work:

```powershell
npm run tauri:dev
npm run tauri:build
```

Do not document raw Tauri or Cargo commands as release paths unless the document
is explicitly describing internals.

## Release Rules

Never use this command as a runnable desktop release path:

```powershell
cargo build --release --manifest-path src-tauri/Cargo.toml
```

It can compile Rust without running the Tauri frontend asset pipeline. The
typical symptom is:

```text
asset not found: index.html
```

`npm run desktop:release` must:

- stop running desktop and sidecar processes before build;
- check desktop shell version alignment;
- run the Tauri no-bundle build path;
- produce `src-tauri\target\release\kimi-code-desktop.exe`;
- write `src-tauri\target\release\kimi-code-desktop.release.json`.

`start.bat release` must validate that release manifest before launch. A bare
`.exe` file is not enough proof.

`npm run release:msi` is the public MSI path. It must:

- check desktop shell version alignment even when preflight is skipped;
- clear previous MSI metadata before bundling;
- build through the internal raw Tauri MSI command;
- accept only a fresh MSI matching the current package version;
- verify the release exe is fresh;
- validate MSI uninstall support, including the pinned WiX `upgradeCode`,
  Windows Apps uninstall metadata, and the Start Menu `Uninstall Kimi Code`
  shortcut;
- write checksums and `release-manifest.json`;
- refresh the local release manifest after MSI patching.

MSI startup must not depend on `start.bat`. The installed app entrypoint is the
Tauri executable, so runtime readiness checks must also live inside the desktop
app. On startup, the app must check the bundled sidecar/runtime, `config.toml`,
credential sources, and the optional external `kimi` login helper before loading
sessions.

MSI uninstall must remove installed app files and shortcuts but must not remove
`~\.kimi` by default. That directory is owned by the Kimi CLI runtime and may
contain reusable config or credentials.

## Sidecar Rules

The source sidecar binary is:

```text
src-tauri\sidecar\kimi-sidecar-x86_64-pc-windows-msvc.exe
```

Build it with:

```powershell
npm run sidecar:build
```

The sidecar build must fail fast on failed native commands and write:

```text
src-tauri\sidecar\kimi-sidecar.manifest.json
```

Release validation must not rely only on "the sidecar exe exists." It must
verify the sidecar manifest and hash.

The packaged sidecar must expose `__desktop-runtime-info` so the installed app
can verify that the bundled `kimi_cli` package is importable and report its
runtime version without relying on PATH.

`npm run sidecar:build` must execute that hidden runtime-info command against
the built exe and fail if it cannot parse usable JSON from stdout.

## Version Rules

The desktop shell version must match in all four files:

```text
package.json
package-lock.json
src-tauri/Cargo.toml
src-tauri/tauri.conf.json
```

Check:

```powershell
npm run version:sync
```

Set:

```powershell
npm run version:set <version>
```

The runtime Kimi CLI version is separate from the desktop shell version. UI that
shows the CLI version must probe the installed CLI/runtime, not reuse the shell
version.

## Verification Standard

For normal development changes:

```powershell
npm test
npm run build
cargo check --manifest-path src-tauri/Cargo.toml
```

For release, packaging, sidecar, version, or launch-script changes:

```powershell
npm run release:preflight
```

For MSI-specific changes:

```powershell
npm run release:msi
```

If a command cannot be run, record that explicitly in the final handoff with the
reason and the residual risk.

## Sub-Agent Standard

Use sub-agents for independent work that can be checked in parallel. Keep write
ownership separate:

```text
Frontend agent: src/
Rust agent: src-tauri/src/
Sidecar agent: sidecar-adapter/
Release/docs agent: package.json, scripts/*.ps1, docs/, start.bat
```

Sub-agents must:

- inspect current worktree state before making claims;
- avoid reverting unrelated edits;
- report exact file paths and line numbers for findings;
- keep command names aligned with this standard;
- verify their assigned scope or clearly state what remains unverified.

## Documentation Standard

Public docs should point to this file for the authoritative workflow. Keep these
files aligned:

```text
README.md
AGENTS.md
docs/RELEASE.md
```

When changing launch, build, release, sidecar, or version behavior, update the
docs in the same change.
