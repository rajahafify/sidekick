import { describe, expect, it } from 'vitest';
import {
  buildPrompt,
  buildScoutPrompt,
  pairId,
  parseLlmExchange,
  parseScout,
  templateExchange,
  templatePick,
  templateScout,
  type Card,
} from '../src/sidekick';

const alex: Card = {
  uid: 'a1',
  displayName: 'Alex Rivera',
  headline: 'Founder, B2B payments',
  lookingFor: ['Funding', 'Engineering help'],
  offering: ['Go-to-market'],
  about: 'Building payments infrastructure for SMEs',
};
const sam: Card = {
  uid: 'b2',
  displayName: 'Sam Lee',
  headline: 'Angel investor',
  lookingFor: ['go-to-market'],
  offering: ['funding', 'Mentorship'],
  about: 'Invests in payments and fintech',
};
const kim: Card = { uid: 'c3', displayName: 'Kim', headline: 'Illustrator', lookingFor: ['Customers'], offering: [], about: '' };

describe('pairId', () => {
  it('is the same whichever side asks', () => {
    expect(pairId('ev', 'a1', 'b2')).toBe(pairId('ev', 'b2', 'a1'));
  });
});

describe('templatePick / templateScout', () => {
  it('scores a two-way fit above an unrelated person, case-insensitively', () => {
    const s = templatePick(alex, sam);
    expect(s.reason).toContain('Two-way fit');
    expect(s.score).toBeGreaterThan(templatePick(alex, kim).score);
    expect(templateScout(alex, [kim, sam, alex]).picks.map((p) => p.uid)).toEqual(['b2', 'c3']);
  });
  it('handles empty cards', () => {
    const blank = { ...kim, uid: 'z', headline: '', lookingFor: [], offering: [] };
    expect(templatePick(blank, blank).reason).toBe('Kim is here too.');
  });
});

describe('scout prompt and parsing', () => {
  it('only includes first names and public fields, never uids', () => {
    const { user } = buildScoutPrompt(alex, [sam, kim]);
    expect(user).toContain('"Sam"');
    expect(user).not.toContain('Lee');
    expect(user).not.toContain('b2');
  });
  it('maps ids back to people, fills in anyone skipped, and sorts by score', () => {
    const raw = JSON.stringify({ picks: [{ id: 'p1', score: 20, reason: 'Meh' }, { id: 'p0', score: 90, reason: 'Investor in payments' }, { id: 'p9', score: 99, reason: 'ghost' }] });
    const s = parseScout(raw, alex, [sam, kim]);
    expect(s?.source).toBe('llm');
    expect(s?.picks.map((p) => [p.uid, p.score])).toEqual([['b2', 90], ['c3', 20]]);
    const partial = parseScout(JSON.stringify({ picks: [{ id: 'p0', score: 80, reason: 'Good' }] }), alex, [sam, kim]);
    expect(partial?.picks.map((p) => p.uid)).toEqual(['b2', 'c3']);
  });
  it('rejects junk', () => {
    expect(parseScout('sure!', alex, [sam])).toBeNull();
    expect(parseScout(JSON.stringify({ picks: [] }), alex, [sam])).toBeNull();
  });
});

describe('templateExchange', () => {
  it('is identical for both people and uses what each can offer', () => {
    expect(templateExchange(alex, sam)).toEqual(templateExchange(sam, alex));
    const ex = templateExchange(alex, sam);
    expect(ex.reason).toContain('funding');
    expect(ex.source).toBe('template');
  });
});

describe('buildPrompt', () => {
  it('only includes first names and public fields', () => {
    const { user } = buildPrompt(alex, sam);
    expect(user).toContain('"Alex"');
    expect(user).not.toContain('Rivera');
    expect(user).not.toContain('a1');
  });
});

describe('parseLlmExchange', () => {
  const good = {
    turns: [
      { speaker: 'A', text: 'Hi!' },
      { speaker: 'B', text: 'Hello!' },
    ],
    reason: 'Sam invests in payments.',
    opener: 'What do you look for at seed?',
  };
  it('accepts valid JSON and maps speakers to uids', () => {
    const ex = parseLlmExchange(JSON.stringify(good), sam, alex);
    expect(ex?.turns.map((t) => t.speaker)).toEqual(['a1', 'b2']);
    expect(ex?.source).toBe('llm');
  });
  it('strips code fences', () => {
    expect(parseLlmExchange('```json\n' + JSON.stringify(good) + '\n```', alex, sam)).not.toBeNull();
  });
  it('rejects junk and wrong shapes', () => {
    expect(parseLlmExchange('sure! here you go', alex, sam)).toBeNull();
    expect(parseLlmExchange(JSON.stringify({ ...good, opener: '' }), alex, sam)).toBeNull();
  });
});

describe('lenient parsing of free-model replies', () => {
  const me = { uid: 'me', displayName: 'Me', headline: '', lookingFor: ['Funding'], offering: [], about: '' };
  const b = { uid: 'b', displayName: 'Ben', headline: '', lookingFor: [], offering: ['Funding'], about: '' };
  it('reads a scout wrapped in prose, with string scores and long reasons', async () => {
    const { parseScout } = await import('../src/sidekick');
    const raw = `Here is my ranking:\n{"picks":[{"id":"P0","score":"85","reason":"${'x'.repeat(300)}"}]}\nHope that helps!`;
    const scout = parseScout(raw, me, [b]);
    expect(scout?.source).toBe('llm');
    expect(scout?.picks[0]).toMatchObject({ uid: 'b', score: 85 });
    expect(scout!.picks[0].reason.length).toBeLessThanOrEqual(240);
  });
  it('reads an exchange with "Person A" speakers and too many turns', async () => {
    const { parseLlmExchange } = await import('../src/sidekick');
    const turns = Array.from({ length: 8 }, (_, i) => ({ speaker: i % 2 ? 'Person B' : 'a', text: `turn ${i}` }));
    const ex = parseLlmExchange('```json\n' + JSON.stringify({ turns, reason: 'Fit.', opener: '"Hi?"' }) + '\n```', me, b);
    expect(ex?.turns).toHaveLength(6);
    expect(ex?.opener).toBe('Hi?');
  });
});
