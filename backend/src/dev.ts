// Local dev server: the real API on an in-memory store, no AWS needed.
// Identities come from the x-dev-identity / x-dev-guest headers (the app sends them when built
// with DEV_API). Never deploy this.
//
//   npm run dev            # http://localhost:8787
//   npm run dev -- --seed  # with a demo event full of people
import { createServer } from 'node:http';
import { App } from './app';
import { MemoryStore } from './store';

const store = new MemoryStore();
const app = new App({ store, model: null, places: null, fetch, now: () => Date.now() });
const port = Number(process.env.PORT ?? 8787);

async function seed() {
  const people = [
    ['Aisha Rahman', 'Partner at a seed fund', ['Customers', 'Cofounder'], ['Funding', 'Advice', 'Intros']],
    ['Daniel Tan', 'CTO, logistics startup', ['Design help', 'Hiring'], ['Engineering help', 'Mentorship']],
    ['Mei Lin', 'Product designer', ['A new role', 'Collaborators'], ['Design help', 'Product feedback']],
    ['Arjun Nair', 'Founder, B2B payments', ['Funding', 'Go-to-market'], ['Partnerships', 'Customers']],
    ['Sofia Ibrahim', 'Growth lead', ['Mentorship'], ['Go-to-market', 'Intros']],
  ] as const;
  const now = Date.now();
  const { body } = await app.handle({
    method: 'POST',
    path: '/events',
    identity: { id: 'dev:host', guest: false },
    body: {
      name: 'Founders & Funders KL',
      place: 'Common Ground, Bukit Bintang',
      startsAt: new Date(now - 3600_000).toISOString(),
      endsAt: new Date(now + 3 * 3600_000).toISOString(),
    },
  });
  const id = (body as { id: string }).id;
  for (const [i, [name, headline, lookingFor, offering]] of people.entries()) {
    const who = { id: `dev:seed${i}`, guest: false };
    await app.handle({
      method: 'PUT',
      path: '/me',
      identity: who,
      body: {
        displayName: name,
        headline,
        lookingFor,
        offering,
        about: '',
        contact: { linkedin: `linkedin.com/in/${name.split(' ')[0].toLowerCase()}`, email: '', phone: '' },
      },
    });
    await app.handle({ method: 'POST', path: `/events/${id}/join`, identity: who, body: {} });
  }
  console.log(`Seeded event ${id}`);
  return id;
}

/** Lets a seeded person connect with someone, to try matching: POST /dev/like {eventId, from: 0, to} */
async function devLike(b: any) {
  return app.handle({
    method: 'POST',
    path: `/events/${b.eventId}/swipe`,
    identity: { id: `dev:seed${b.from}`, guest: false },
    body: { to: b.to, like: true },
  });
}

createServer(async (req, res) => {
  const cors = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type, x-dev-identity, x-dev-guest',
    'access-control-allow-methods': 'GET, POST, PUT, DELETE, OPTIONS',
  };
  if (req.method === 'OPTIONS') {
    res.writeHead(204, cors).end();
    return;
  }
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const raw = Buffer.concat(chunks).toString('utf8');
  let body: unknown;
  try {
    body = raw ? JSON.parse(raw) : undefined;
  } catch {
    res.writeHead(400, cors).end('{"error":"Invalid request."}');
    return;
  }
  const path = (req.url ?? '/').split('?')[0];
  const out =
    path === '/dev/like'
      ? await devLike(body)
      : await app.handle({
          method: req.method ?? 'GET',
          path,
          body,
          identity: { id: String(req.headers['x-dev-identity'] || 'dev:anon'), guest: req.headers['x-dev-guest'] === '1' },
        });
  res.writeHead(out.status, { ...cors, 'content-type': 'application/json' }).end(JSON.stringify(out.body));
}).listen(port, async () => {
  console.log(`Sidekick dev API on http://localhost:${port}`);
  if (process.argv.includes('--seed')) await seed();
});
