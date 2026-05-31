import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it } from "vitest";
import { useTheme } from "./use-theme";

function ThemeProbe({ id }: { id: string }) {
  const { theme, setTheme } = useTheme();

  return (
    <div>
      <output aria-label={`theme-${id}`}>{theme}</output>
      <button type="button" onClick={() => setTheme("dark")}>
        dark-{id}
      </button>
      <button type="button" onClick={() => setTheme("light")}>
        light-{id}
      </button>
    </div>
  );
}

describe("useTheme", () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.className = "";
    document.documentElement.style.colorScheme = "";
  });

  it("shares theme state across hook users and applies it to the document", async () => {
    const user = userEvent.setup();
    render(
      <>
        <ThemeProbe id="a" />
        <ThemeProbe id="b" />
      </>,
    );

    await user.click(screen.getByRole("button", { name: "dark-a" }));

    await waitFor(() => {
      expect(screen.getByLabelText("theme-a").textContent).toBe("dark");
      expect(screen.getByLabelText("theme-b").textContent).toBe("dark");
      expect(document.documentElement.classList.contains("dark")).toBe(true);
      expect(window.localStorage.getItem("kimi-theme")).toBe("dark");
    });

    await user.click(screen.getByRole("button", { name: "light-b" }));

    await waitFor(() => {
      expect(screen.getByLabelText("theme-a").textContent).toBe("light");
      expect(screen.getByLabelText("theme-b").textContent).toBe("light");
      expect(document.documentElement.classList.contains("dark")).toBe(false);
      expect(window.localStorage.getItem("kimi-theme")).toBe("light");
    });
  });
});
