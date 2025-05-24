import { openrouter } from "npm:@openrouter/ai-sdk-provider@0.4.6";
import { openai } from "npm:@ai-sdk/openai@1.3.22";
import { anthropic } from "npm:@ai-sdk/anthropic@1.2.12";
import { createOllama } from "npm:ollama-ai-provider@1.2.0";
import { createProviderRegistry } from "npm:ai@4.3.16";

export const registry = createProviderRegistry({
  openai,
  anthropic,
  ollama: createOllama({
    baseURL: Deno.env.get("OLLAMA_BASE_URL") || "http://127.0.0.1:11434/api",
  }),
  // @ts-expect-error missing non-language model
  openrouter,
});
