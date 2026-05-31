import { getKimiCliVersion } from "@/lib/tauri-api";

declare const __KIMI_CLI_VERSION__: string | undefined;
declare const __APP_VERSION__: string | undefined;

export const desktopVersion =
  typeof __APP_VERSION__ !== "undefined" && __APP_VERSION__ ? __APP_VERSION__ : "dev";

export const bundledKimiCliVersion =
  typeof __KIMI_CLI_VERSION__ !== "undefined" && __KIMI_CLI_VERSION__
    ? __KIMI_CLI_VERSION__
    : "dev";

export const kimiCliVersion = bundledKimiCliVersion;

let resolvedKimiCliVersion: string | null = null;
let versionRequest: Promise<string> | null = null;

export function resolveKimiCliVersion(): Promise<string> {
  if (resolvedKimiCliVersion) {
    return Promise.resolve(resolvedKimiCliVersion);
  }

  if (!versionRequest) {
    versionRequest = getKimiCliVersion()
      .then((version) => {
        const trimmed = version.trim();
        resolvedKimiCliVersion = trimmed || bundledKimiCliVersion;
        return resolvedKimiCliVersion;
      })
      .catch(() => {
        resolvedKimiCliVersion = bundledKimiCliVersion;
        return resolvedKimiCliVersion;
      });
  }

  return versionRequest;
}
