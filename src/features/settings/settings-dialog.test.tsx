import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { UiLanguageProvider } from "@/lib/i18n";
import { SettingsDialog } from "./settings-dialog";

const mocks = vi.hoisted(() => ({
  getConfigTomlFile: vi.fn(),
  getMcpConfigFile: vi.fn(),
  updateConfigTomlFile: vi.fn(),
  updateMcpConfigFile: vi.fn(),
  refreshGlobalConfig: vi.fn(),
  updateGlobalConfig: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock("@/lib/settings-api", () => ({
  getConfigTomlFile: mocks.getConfigTomlFile,
  getMcpConfigFile: mocks.getMcpConfigFile,
  updateConfigTomlFile: mocks.updateConfigTomlFile,
  updateMcpConfigFile: mocks.updateMcpConfigFile,
}));

vi.mock("@/hooks/useGlobalConfig", () => ({
  useGlobalConfig: () => ({
    config: {
      defaultModel: "kimi",
      defaultThinking: true,
      models: [
        {
          provider: "kimi",
          model: "kimi-k2",
          maxContextSize: 128_000,
          capabilities: new Set(["thinking"]),
          name: "kimi",
          providerType: "kimi",
        },
      ],
    },
    error: null,
    isLoading: false,
    isUpdating: false,
    refresh: mocks.refreshGlobalConfig,
    update: mocks.updateGlobalConfig,
  }),
}));

vi.mock("@/lib/tauri-api", () => ({
  isTauri: () => false,
  openKimiLogin: vi.fn(),
}));

vi.mock("@/lib/version", () => ({
  desktopVersion: "0.1.0",
  resolveKimiCliVersion: vi.fn(() => Promise.resolve("1.45.0")),
}));

vi.mock("sonner", () => ({
  toast: {
    error: mocks.toastError,
    success: mocks.toastSuccess,
  },
}));

const CONFIG_TOML = `default_model = "kimi"
theme = "light"
show_thinking_stream = true
merge_all_available_skills = false

[providers.kimi]
type = "kimi"

[models.kimi]
provider = "kimi"
model = "kimi-k2"
max_context_size = 128000
capabilities = ["thinking"]
`;

function renderSettingsDialog() {
  return render(
    <UiLanguageProvider>
      <SettingsDialog open={true} onOpenChange={vi.fn()} />
    </UiLanguageProvider>,
  );
}

async function openSection(name: string) {
  await screen.findByRole("button", { name });
  await userEvent.click(screen.getByRole("button", { name }));
}

async function chooseOption(comboboxIndex: number, optionName: string) {
  const user = userEvent.setup();
  const comboboxes = screen.getAllByRole("combobox");
  await user.click(comboboxes[comboboxIndex]);
  await user.click(await screen.findByRole("option", { name: optionName }));
}

describe("SettingsDialog", () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.className = "";
    document.documentElement.style.colorScheme = "";
    mocks.getConfigTomlFile.mockReset();
    mocks.getMcpConfigFile.mockReset();
    mocks.updateConfigTomlFile.mockReset();
    mocks.updateMcpConfigFile.mockReset();
    mocks.refreshGlobalConfig.mockReset();
    mocks.updateGlobalConfig.mockReset();
    mocks.toastError.mockReset();
    mocks.toastSuccess.mockReset();

    mocks.getConfigTomlFile.mockResolvedValue({
      content: CONFIG_TOML,
      path: "~/.kimi/config.toml",
    });
    mocks.getMcpConfigFile.mockResolvedValue({
      content: '{\n  "mcpServers": {}\n}\n',
      path: "~/.kimi/mcp.json",
    });
    mocks.updateConfigTomlFile.mockResolvedValue({ success: true });
    mocks.updateMcpConfigFile.mockResolvedValue({ success: true });
    mocks.refreshGlobalConfig.mockResolvedValue(undefined);
  });

  it("keeps language and app theme pending until Save settings", async () => {
    const user = userEvent.setup();
    renderSettingsDialog();

    await openSection("General");

    const saveSettings = screen.getByRole("button", { name: "Save settings" });
    expect(saveSettings.hasAttribute("disabled")).toBe(true);

    await chooseOption(0, "Chinese (Simplified)");
    await chooseOption(1, "Dark");

    expect(saveSettings.hasAttribute("disabled")).toBe(false);
    expect(window.localStorage.getItem("kimi-ui-language")).toBeNull();
    expect(window.localStorage.getItem("kimi-theme")).toBeNull();
    expect(document.documentElement.classList.contains("dark")).toBe(false);

    await user.click(saveSettings);

    await waitFor(() => {
      expect(window.localStorage.getItem("kimi-ui-language")).toBe("zh-CN");
      expect(window.localStorage.getItem("kimi-theme")).toBe("dark");
      expect(document.documentElement.classList.contains("dark")).toBe(true);
      expect(saveSettings.hasAttribute("disabled")).toBe(true);
    });
    expect(mocks.updateConfigTomlFile).not.toHaveBeenCalled();
  });

  it("surfaces MCP dirty state with a footer Save MCP action", async () => {
    const user = userEvent.setup();
    renderSettingsDialog();

    await openSection("MCP");
    const textarea = await screen.findByRole("textbox");
    fireEvent.change(textarea, {
      target: { value: '{"mcpServers":{"local":{"command":"node"}}}' },
    });

    const saveMcpButtons = screen.getAllByRole("button", { name: "Save MCP" });
    expect(saveMcpButtons.some((button) => !button.hasAttribute("disabled"))).toBe(true);

    await user.click(saveMcpButtons.find((button) => !button.hasAttribute("disabled"))!);

    await waitFor(() => {
      expect(mocks.updateMcpConfigFile).toHaveBeenCalledWith(
        '{\n  "mcpServers": {\n    "local": {\n      "command": "node"\n    }\n  }\n}\n',
      );
    });
  });
});
