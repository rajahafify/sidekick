// The sidekick's model. Either Amazon Bedrock, called with the Lambda's own IAM role (no API key),
// or OpenRouter, with its key kept in SSM Parameter Store. Returns null text on any failure, and
// callers fall back to the template.
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

/** Any OpenRouter model, e.g. `openrouter/free` (picks a free model for each request). */
export function openRouterModel(
  modelId: string,
  apiKey: () => Promise<string | null>,
  fetchFn: typeof fetch = fetch,
): Model {
  return async (prompt, opts) => {
    try {
      const key = await apiKey();
      if (!key) return { text: null, error: 'OpenRouter API key not set' };
      const r = await fetchFn('https://openrouter.ai/api/v1/chat/completions', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${key}`,
          'content-type': 'application/json',
          'HTTP-Referer': 'https://sidekick.artifisi.com',
          'X-Title': 'Sidekick',
        },
        body: JSON.stringify({
          model: modelId,
          messages: [
            { role: 'system', content: prompt.system },
            { role: 'user', content: prompt.user },
          ],
          max_tokens: opts.maxTokens,
          temperature: opts.temperature,
          // The free router can pick a thinking model, whose reasoning would eat the token budget
          // and leave no answer. Keep thinking short and out of the reply.
          reasoning: { effort: 'low', exclude: true },
        }),
        signal: AbortSignal.timeout(20_000),
      });
      if (!r.ok) return { text: null, error: `OpenRouter ${r.status}: ${(await r.text()).slice(0, 300)}` };
      const body: any = await r.json();
      const choice = body?.choices?.[0];
      const text = String(choice?.message?.content ?? '').trim();
      if (text) return { text };
      // Say which model answered and why it stopped, so the status check can explain an empty reply.
      const why = [body?.model, choice?.finish_reason && `finish_reason ${choice.finish_reason}`, body?.error?.message]
        .filter(Boolean)
        .join(', ');
      return { text: null, error: why ? `Empty reply (${why})` : 'Empty reply' };
    } catch (e: any) {
      return { text: null, error: `OpenRouter ${e?.name ?? 'error'}: ${String(e?.message ?? e).slice(0, 300)}` };
    }
  };
}

/** Reads a SecureString from SSM once per cold start (and retries after a miss). */
export function ssmSecret(name: string, region: string): () => Promise<string | null> {
  let cached: Promise<string | null> | null = null;
  return () => {
    cached ??= (async () => {
      const { SSMClient, GetParameterCommand } = await import('@aws-sdk/client-ssm');
      const r = await new SSMClient({ region }).send(new GetParameterCommand({ Name: name, WithDecryption: true }));
      return r.Parameter?.Value?.trim() || null;
    })().catch(() => {
      cached = null;
      return null;
    });
    return cached;
  };
}
