// The sidekick's model: Claude on Amazon Bedrock, called with the Lambda's own IAM role
// (no API keys anywhere). Returns null on any failure, and callers fall back to the template.
import { BedrockRuntimeClient, ConverseCommand } from '@aws-sdk/client-bedrock-runtime';

export type Prompt = { system: string; user: string };
export type ModelOpts = { maxTokens: number; temperature: number };
export type Model = (prompt: Prompt, opts: ModelOpts) => Promise<{ text: string | null; error?: string }>;

export function bedrockModel(modelId: string, region: string): Model {
  const client = new BedrockRuntimeClient({ region, maxAttempts: 2 });
  return async (prompt, opts) => {
    try {
      const r = await client.send(
        new ConverseCommand({
          modelId,
          system: [{ text: prompt.system }],
          messages: [{ role: 'user', content: [{ text: prompt.user }] }],
          inferenceConfig: { maxTokens: opts.maxTokens, temperature: opts.temperature },
        }),
      );
      const text = (r.output?.message?.content ?? []).map((b) => ('text' in b ? b.text : '')).join('');
      return { text: text.trim() || null, error: text.trim() ? undefined : 'Empty reply' };
    } catch (e: any) {
      return { text: null, error: `Bedrock ${e?.name ?? 'error'}: ${String(e?.message ?? e).slice(0, 300)}` };
    }
  };
}
