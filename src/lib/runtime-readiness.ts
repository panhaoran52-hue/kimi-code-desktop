import type { RuntimeReadiness } from "@/lib/tauri-api";

export type RuntimeReadinessKind = "ready" | "warning" | "blocked";

export function getRuntimeReadinessKind(
	readiness: RuntimeReadiness,
): RuntimeReadinessKind {
	if (readiness.hasBlockingIssues || readiness.issues.length > 0) {
		return "blocked";
	}
	if (readiness.warnings.length > 0) {
		return "warning";
	}
	return "ready";
}

export function shouldPauseForRuntimeReadiness(
	readiness: RuntimeReadiness | null,
	acknowledged: boolean,
): boolean {
	if (!readiness) {
		return !acknowledged;
	}
	if (getRuntimeReadinessKind(readiness) === "ready") {
		return false;
	}
	return !acknowledged;
}
