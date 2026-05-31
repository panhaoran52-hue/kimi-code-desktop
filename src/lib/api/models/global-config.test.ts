import { describe, expect, it } from "vitest";
import {
	GlobalConfigFromJSON,
	GlobalConfigToJSON,
	UpdateGlobalConfigRequestToJSON,
} from "./index";

describe("global config API models", () => {
	it("maps default_plan_mode between API JSON and TypeScript config", () => {
		const config = GlobalConfigFromJSON({
			default_model: "kimi",
			default_thinking: true,
			default_plan_mode: true,
			models: [],
		});

		expect(config.defaultPlanMode).toBe(true);
		expect(GlobalConfigToJSON(config)).toMatchObject({
			default_plan_mode: true,
		});
	});

	it("serializes defaultPlanMode in update requests", () => {
		expect(
			UpdateGlobalConfigRequestToJSON({
				defaultPlanMode: false,
			}),
		).toMatchObject({
			default_plan_mode: false,
		});
	});
});
