import { z } from 'zod';

/** The public attendee-card fields. This is all the sidekick ever sees about a person. */
export type Card = {
  uid: string;
  displayName: string;
  headline: string;
  lookingFor: string[];
  offering: string[];
  about: string;
};

/** The sidekick's verdict on one person, for the person it works for. */
export type ScoutPick = { uid: string; score: number; reason: string };

export type Scout = { picks: ScoutPick[]; source: 'llm' | 'template' };

export type Exchange = {
  turns: { speaker: string; text: string }[];
  reason: string;
  opener: string;
  source: 'llm' | 'template';
};

/** Stable id for a pair of people at an event, the same whichever side asks. */
export function pairId(eventId: string, a: string, b: string): string {
  const [x, y] = [a, b].sort();
  return `${eventId}_${x}_${y}`;
}

/** Puts the two cards in a fixed order so both people see the same exchange. */
export function orderPair(one: Card, two: Card): [Card, Card] {
  return one.uid < two.uid ? [one, two] : [two, one];
}

const norm = (s: string) => s.trim().toLowerCase();

/** Tags in `wants` that `has` offers, case-insensitive, in the order of `wants`. */
export function overlap(wants: string[], has: string[]): string[] {
  const set = new Set(has.map(norm));
  return wants.filter((w) => set.has(norm(w)));
}

const STOP = new Set(
  'about after also and are but can for from have into just like more our out that the their them they this was what when with work working your'.split(
    ' ',
  ),
);
function words(c: Card): Set<string> {
  return new Set(
    `${c.headline} ${c.about}`
      .toLowerCase()
      .split(/[^a-z0-9+#]+/)
      .filter((w) => w.length > 3 && !STOP.has(w)),
  );
}

export const firstName = (c: { displayName: string }) => c.displayName.trim().split(/\s+/)[0] || 'They';

/**
 * Deterministic relevance of `them` to `me`, 0 to 100, with a one-line reason.
 * Used when no LLM is configured, when it fails, and for people who joined after the last scout.
 */
export function templatePick(me: Card, them: Card): ScoutPick {
  const theyHelpMe = overlap(me.lookingFor, them.offering);
  const iHelpThem = overlap(them.lookingFor, me.offering);
  const mine = words(me);
  const sharedWords = [...words(them)].filter((w) => mine.has(w));
  const sameGoals = overlap(me.lookingFor, them.lookingFor);
  const score = Math.min(
    100,
    10 + theyHelpMe.length * 30 + iHelpThem.length * 20 + sharedWords.length * 8 + sameGoals.length * 5,
  );
  const name = firstName(them);
  let reason: string;
  if (theyHelpMe.length && iHelpThem.length)
    reason = `Two-way fit: ${name} offers ${theyHelpMe[0].toLowerCase()} and is looking for ${iHelpThem[0].toLowerCase()}.`;
  else if (theyHelpMe.length) reason = `${name} offers ${theyHelpMe.join(', ').toLowerCase()}, which you're looking for.`;
  else if (iHelpThem.length) reason = `${name} is looking for ${iHelpThem.join(', ').toLowerCase()}, which you offer.`;
  else if (sharedWords.length) reason = `You both mention ${sharedWords.slice(0, 2).join(' and ')}.`;
  else if (sameGoals.length) reason = `You're both looking for ${sameGoals[0].toLowerCase()}. Compare notes.`;
  else reason = them.headline ? `${them.headline}.` : `${name} is here too.`;
  return { uid: them.uid, score, reason };
}

export function templateScout(me: Card, others: Card[]): Scout {
  return {
    source: 'template',
    picks: others
      .filter((o) => o.uid !== me.uid)
      .map((o) => templatePick(me, o))
      .sort((a, b) => b.score - a.score),
  };
}

const describe = (c: Card) =>
  JSON.stringify({
    name: firstName(c),
    headline: c.headline,
    lookingFor: c.lookingFor,
    offering: c.offering,
    about: c.about,
  });

/** Most people we send to the model in one scouting call. */
export const SCOUT_MAX = 80;

export function buildScoutPrompt(me: Card, others: Card[]): { system: string; user: string } {
  const list = others
    .slice(0, SCOUT_MAX)
    .map((c, i) => `p${i}: ${describe(c)}`)
    .join('\n');
  return {
    system: [
      'You are a networking sidekick at a professional event, working for one person.',
      'Your person wants to stay focused on the talks, so you scout the room for them:',
      'decide how worth meeting each attendee is for your person, considering what each side is looking for and can offer.',
      'Two-way fit beats one-way fit. Be honest: most people are not a strong match.',
      'Use only the facts given. Do not invent jobs, companies or details.',
      'Reply with JSON only, no prose and no code fences, matching:',
      '{"picks":[{"id":"p0","score":0-100,"reason":string}]}',
      'Include every attendee once. reason is under 20 words, addressed to your person ("you"), and names the concrete reason to meet.',
    ].join(' '),
    user: `My person: ${describe(me)}\n\nAttendees:\n${list}`,
  };
}

// Free models drift from the format: numbers as strings, long reasons, extra turns.
// Be lenient about shape and trim to size instead of throwing the whole answer away.
const text = (max: number) =>
  z.string().trim().min(1).transform((v) => (v.length > max ? `${v.slice(0, max - 1).trimEnd()}…` : v));

const scoutSchema = z.object({
  picks: z.array(
    z.object({
      id: z.coerce.string(),
      score: z.coerce.number().transform((n) => Math.min(100, Math.max(0, n))),
      reason: text(240),
    }),
  ),
});

/** The JSON object in a model reply, even with code fences or prose around it. */
export function parseJson(raw: string): unknown {
  const cleaned = raw
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```$/, '')
    .trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    // Fall back to the outermost {...} in the reply.
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) return undefined;
    try {
      return JSON.parse(cleaned.slice(start, end + 1));
    } catch {
      return undefined;
    }
  }
}

/** Parses the model's ranking. Returns null if it doesn't fit, so the caller falls back. */
export function parseScout(raw: string, me: Card, others: Card[]): Scout | null {
  const parsed = scoutSchema.safeParse(parseJson(raw));
  if (!parsed.success) return null;
  const sent = others.slice(0, SCOUT_MAX);
  const seen = new Set<string>();
  const picks: ScoutPick[] = [];
  for (const p of parsed.data.picks) {
    const id = p.id.trim().toLowerCase();
    const card = /^p?\d+$/.test(id) ? sent[Number(id.replace(/^p/, ''))] : undefined;
    if (!card || seen.has(card.uid)) continue;
    seen.add(card.uid);
    picks.push({ uid: card.uid, score: Math.round(p.score), reason: p.reason });
  }
  if (!picks.length && sent.length) return null;
  // Anyone the model skipped, or beyond SCOUT_MAX, gets the template verdict.
  for (const c of others) if (!seen.has(c.uid) && c.uid !== me.uid) picks.push(templatePick(me, c));
  return { source: 'llm', picks: picks.sort((a, b) => b.score - a.score) };
}

/** Deterministic fallback for the matched pair's exchange and opener. */
export function templateExchange(one: Card, two: Card): Exchange {
  const [a, b] = orderPair(one, two);
  const an = firstName(a);
  const bn = firstName(b);
  const aGets = overlap(a.lookingFor, b.offering);
  const bGets = overlap(b.lookingFor, a.offering);
  const reason = aGets.length || bGets.length
    ? [
        aGets.length ? `${bn} can help ${an} with ${aGets[0].toLowerCase()}` : '',
        bGets.length ? `${an} can help ${bn} with ${bGets[0].toLowerCase()}` : '',
      ]
        .filter(Boolean)
        .join(', and ') + '.'
    : `${an} and ${bn} both wanted to connect.`;
  const opener = aGets.length
    ? `What are you looking for in ${aGets[0].toLowerCase()} right now?`
    : bGets.length
      ? `What are you looking for in ${bGets[0].toLowerCase()} right now?`
      : b.about || a.about
        ? "What are you working on at the moment?"
        : 'What brought you to this event?';
  const intro = (c: Card) => `${firstName(c)}${c.headline ? `, ${c.headline}` : ''}`;
  return {
    source: 'template',
    reason,
    opener,
    turns: [
      { speaker: a.uid, text: `I'm with ${intro(a)}.${a.lookingFor.length ? ` Looking for ${a.lookingFor.join(', ').toLowerCase()}.` : ''}` },
      { speaker: b.uid, text: `I'm with ${intro(b)}.${b.offering.length ? ` Can offer ${b.offering.join(', ').toLowerCase()}.` : ''}` },
      { speaker: a.uid, text: aGets.length ? `That's a fit for ${an}.` : `${an} would value the conversation.` },
      { speaker: b.uid, text: `Then let's swap contacts. Try: "${opener}"` },
    ],
  };
}

const exchangeSchema = z.object({
  turns: z
    .array(
      z.object({
        speaker: z
          .string()
          .trim()
          .transform((v) => v.toUpperCase().replace(/^PERSON\s*/, ''))
          .pipe(z.enum(['A', 'B'])),
        text: text(300),
      }),
    )
    .min(2)
    .transform((turns) => turns.slice(0, 6)),
  reason: text(240),
  opener: text(200).transform((v) => v.replace(/^["“]|["”]$/g, '')),
});

export function buildPrompt(one: Card, two: Card): { system: string; user: string } {
  const [a, b] = orderPair(one, two);
  return {
    system: [
      'You are two networking sidekicks at a professional event, each representing one person.',
      'Both people chose to connect. Have a short, sharp exchange that shows why they should talk,',
      'focusing on what each is looking for and can offer, then suggest one opening question for when they meet or message.',
      'Professional and warm. Never flirty, never salesy.',
      'Use only the facts given. Do not invent jobs, companies or personal details.',
      'Reply with JSON only, no prose and no code fences, matching:',
      '{"turns":[{"speaker":"A"|"B","text":string}], "reason": string, "opener": string}',
      'Use 4 turns alternating A, B, A, B. Each turn under 30 words. reason under 25 words. opener under 20 words.',
    ].join(' '),
    user: `Person A: ${describe(a)}\nPerson B: ${describe(b)}`,
  };
}

/** Parses and validates the model's reply. Returns null if it doesn't fit, so the caller falls back. */
export function parseLlmExchange(raw: string, one: Card, two: Card): Exchange | null {
  const [a, b] = orderPair(one, two);
  const parsed = exchangeSchema.safeParse(parseJson(raw));
  if (!parsed.success) return null;
  return {
    source: 'llm',
    reason: parsed.data.reason,
    opener: parsed.data.opener,
    turns: parsed.data.turns.map((t) => ({ speaker: t.speaker === 'A' ? a.uid : b.uid, text: t.text })),
  };
}
