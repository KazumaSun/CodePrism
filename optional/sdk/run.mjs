#!/usr/bin/env node
/**
 * Optional Cursor SDK runner. Install deps in optional/sdk before use:
 *   cd optional/sdk && npm install
 */
import { parseArgs } from "node:util";

const { values } = parseArgs({
  options: {
    workspace: { type: "string" },
    model: { type: "string", default: "composer-2.5" },
    prompt: { type: "string" },
  },
});

const workspace = values.workspace;
const model = values.model;
const prompt = values.prompt;

if (!workspace || !prompt) {
  console.error("Usage: run.mjs --workspace <path> --prompt <text> [--model <name>]");
  process.exit(1);
}

let Agent;
try {
  ({ Agent } = await import("@cursor/sdk"));
} catch (e) {
  console.error("Failed to load @cursor/sdk. Run npm install in optional/sdk.");
  console.error(e);
  process.exit(1);
}

const agent = await Agent.create({ workspace, model });
const run = await agent.prompt(prompt);
for await (const msg of run.messages()) {
  if (msg.type === "text") process.stdout.write(msg.text ?? "");
}
