import { describe, expect, it } from 'vitest';
import { openRouterModel } from '../src/model';

const prompt = { system: 'sys', user: 'hi' };
const opts = { maxTokens: 50, temperature: 0.5 };

describe('openRouterModel', () => {
  it('sends a chat completion and returns the reply', async () => {
    let sent: any;
    const fake = (async (url: string, init: any) => {
      sent = { url, init, body: JSON.parse(init.body) };
      return new Response(JSON.stringify({ choices: [{ message: { content: ' Hello there ' } }] }));
    }) as unknown as typeof fetch;
    const r = await openRouterModel('openrouter/free', async () => 'k', fake)(prompt, opts);
    expect(r).toEqual({ text: 'Hello there', error: undefined });
    expect(sent.url).toBe('https://openrouter.ai/api/v1/chat/completions');
    expect(sent.init.headers.authorization).toBe('Bearer k');
    expect(sent.body.model).toBe('openrouter/free');
    expect(sent.body.messages[0]).toEqual({ role: 'system', content: 'sys' });
  });

  it('falls back (null text) without a key or on an error', async () => {
    const never = (async () => {
      throw new Error('should not call');
    }) as unknown as typeof fetch;
    expect((await openRouterModel('m', async () => null, never)(prompt, opts)).text).toBeNull();
    const limited = (async () => new Response('rate limited', { status: 429 })) as unknown as typeof fetch;
    const r = await openRouterModel('m', async () => 'k', limited)(prompt, opts);
    expect(r.text).toBeNull();
    expect(r.error).toContain('429');
  });
});
