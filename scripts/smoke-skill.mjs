import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const tempDir = mkdtempSync(join(tmpdir(), "kimi-skill-smoke-"));
const skillDir = join(tempDir, "codex-skill-smoke");

function run(command, args) {
  const result = spawnSync(command, args, {
    encoding: "utf8",
    env: {
      ...process.env,
      PYTHONIOENCODING: "utf-8",
      PYTHONUTF8: "1",
    },
    timeout: 180_000,
    windowsHide: true,
  });
  const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
  if (result.error) {
    throw new Error(`${command} ${args.join(" ")} failed: ${result.error.message}\n${output}`);
  }
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(" ")} exited with ${result.status}\n${output}`);
  }
  return output;
}

try {
  mkdirSync(skillDir, { recursive: true });
  writeFileSync(
    join(skillDir, "SKILL.md"),
    `---
name: codex-skill-smoke
description: Smoke-test skill for release validation.
---

When this skill is invoked, reply with exactly:

codex-skill-smoke-token
`,
    "utf8",
  );

  const output = run("kimi", [
    "--quiet",
    "--skills-dir",
    tempDir,
    "--max-steps-per-turn",
    "2",
    "-p",
    "/skill:codex-skill-smoke\nInvoke the skill and reply only with its required token.",
  ]);

  if (!output.includes("codex-skill-smoke-token")) {
    throw new Error(`Skill smoke token not found.\n${output}`);
  }

  console.log("Skill smoke passed: /skill:codex-skill-smoke reached the model context.");
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}
