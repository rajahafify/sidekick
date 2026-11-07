import { describe, expect, it } from 'vitest';
import { App, type Deps, type Identity } from '../src/app';
import { placeRoomId } from '../src/geo';
import type { Places } from '../src/places';
import { MemoryStore } from '../src/store';

const NOW = Date.parse('2026-11-20T10:00:00Z');
const alice: Identity = { id: 'ap-southeast-1:alice', guest: false };
const bob: Identity = { id: 'ap-southeast-1:bob', guest: false };
const carol: Identity = { id: 'ap-southeast-1:carol', guest: false };
const guest: Identity = { id: 'ap-southeast-1:guest', guest: true };

const profile = (name: string, extra: object = {}) => ({
  displayName: name,
  headline: `${name} builds things`,
  lookingFor: ['Funding'],
  offering: ['Engineering help'],
  about: '',
  contact: { linkedin: `linkedin.com/in/${name.toLowerCase()}`, email: '', phone: '' },
  ...extra,
});

function setup(over: Partial<Deps> = {}) {
  const store = new MemoryStore();
  const app = new App({ store, model: null, places: null, fetch, now: () => NOW, ...over });
  const call = async (who: Identity, method: string, path: string, body?: unknown) => {
    const r = await app.handle({ method, path, body, identity: who });
    return { status: r.status, body: r.body as any };
  };
  return { store, app, call };
}

async function room(s: ReturnType<typeof setup>, people: Identity[], event: object = {}) {
  for (const p of people) await s.call(p, 'PUT', '/me', profile(p.id.split(':')[1]));
  const { body } = await s.call(alice, 'POST', '/events', {
    name: 'Founders night',
    place: 'KL',
    startsAt: '2026-11-20T09:00:00Z',
    endsAt: '2026-11-20T14:00:00Z',
    ...event,
  });
  for (const p of people) expect((await s.call(p, 'POST', `/events/${body.id}/join`, {})).status).toBe(200);
  return body.id as string;
}

describe('profiles', () => {
  it('are private and need contact details to count as onboarded', async () => {
    const s = setup();
    const r = await s.call(alice, 'PUT', '/me', profile('Alice', { contact: { linkedin: '', email: '', phone: '' } }));
    expect(r.body.profile.onboarded).toBe(false);
    await s.call(alice, 'PUT', '/me', profile('Alice'));
    expect((await s.call(alice, 'GET', '/me')).body.profile.displayName).toBe('Alice');
    expect((await s.call(bob, 'GET', '/me')).body.profile).toBeNull();
  });

  it('rejects bad input', async () => {
    const s = setup();
    expect((await s.call(alice, 'PUT', '/me', profile(''))).status).toBe(400);
    expect((await s.call(alice, 'PUT', '/me', profile('A', { lookingFor: Array(7).fill('x') }))).status).toBe(400);
    expect((await s.call(alice, 'PUT', '/me', profile('A', { photoURL: 'javascript:alert(1)' }))).status).toBe(400);
  });

  it('must be finished before joining', async () => {
    const s = setup();
    const { body } = await s.call(alice, 'POST', '/events', { name: 'X' });
    const r = await s.call(bob, 'POST', `/events/${body.id}/join`, {});
    expect(r.status).toBe(409);
    expect(r.body.needsProfile).toBe(true);
  });
});

describe('the room', () => {
  it('shows cards only to people checked in, and never contact details or swipes', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    const outside = await s.call(carol, 'GET', `/events/${id}`);
    expect(outside.body.me).toBeNull();
    expect(outside.body.people).toBeUndefined();

    await s.call(bob, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true });
    const inside = await s.call(alice, 'GET', `/events/${id}`);
    expect(inside.body.people.map((p: any) => p.uid)).toEqual([bob.id]);
    expect(JSON.stringify(inside.body)).not.toContain('linkedin.com/in/bob');
    expect(inside.body.swipes).toEqual({}); // Bob's Connect on Alice stays private
  });

  it('keeps cards in step with the profile', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    await s.call(bob, 'PUT', '/me', profile('Bob', { headline: 'Now hiring' }));
    const r = await s.call(alice, 'GET', `/events/${id}`);
    expect(r.body.people[0].headline).toBe('Now hiring');
  });

  it('hides people who turned visibility off, and blocked people both ways', async () => {
    const s = setup();
    const id = await room(s, [alice, bob, carol]);
    await s.call(bob, 'POST', `/events/${id}/visible`, { visible: false });
    await s.call(carol, 'POST', '/block', { uid: alice.id });
    expect((await s.call(alice, 'GET', `/events/${id}`)).body.people).toEqual([]);
  });

  it('closes when the event is over', async () => {
    const s = setup();
    await s.call(bob, 'PUT', '/me', profile('Bob'));
    const { body } = await s.call(alice, 'POST', '/events', {
      name: 'Old',
      startsAt: '2026-11-19T09:00:00Z',
      endsAt: '2026-11-19T12:00:00Z',
    });
    expect((await s.call(bob, 'POST', `/events/${body.id}/join`, {})).body.error).toBe('This event has ended.');
    expect((await s.call(bob, 'GET', '/events')).body.open).toEqual([]);
  });

  it('checks you are at the venue when it has a location', async () => {
    const s = setup();
    await s.call(bob, 'PUT', '/me', profile('Bob'));
    const { body } = await s.call(alice, 'POST', '/events', { name: 'KLCC', lat: 3.1579, lng: 101.7116 });
    expect((await s.call(bob, 'POST', `/events/${body.id}/join`, {})).body.needsLocation).toBe(true);
    const far = await s.call(bob, 'POST', `/events/${body.id}/join`, { fix: { lat: 3.17, lng: 101.7116, accuracy: 20 } });
    expect(far.body.tooFar).toBe(true);
    const near = await s.call(bob, 'POST', `/events/${body.id}/join`, { fix: { lat: 3.16, lng: 101.7116, accuracy: 20 } });
    expect(near.status).toBe(200);
  });
});

describe('swipes and matches', () => {
  it('match only when both Connect, and only then share contacts', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    expect((await s.call(alice, 'POST', `/events/${id}/swipe`, { to: bob.id, like: true })).body.match).toBe(false);
    expect((await s.call(alice, 'GET', `/events/${id}/matches/${encodeURIComponent(bob.id)}`)).status).toBe(404);
    expect((await s.call(bob, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true })).body.match).toBe(true);

    const m = await s.call(alice, 'GET', `/events/${id}/matches/${encodeURIComponent(bob.id)}`);
    expect(m.body.contact.linkedin).toBe('linkedin.com/in/bob');
    expect(m.body.exchange.opener).toBeTruthy();
    expect((await s.call(bob, 'GET', `/events/${id}`)).body.matches.map((x: any) => x.uid)).toEqual([alice.id]);
  });

  it('a Pass never matches', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    await s.call(alice, 'POST', `/events/${id}/swipe`, { to: bob.id, like: false });
    expect((await s.call(bob, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true })).body.match).toBe(false);
  });

  it('needs both people at the event, and no block', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    await s.call(carol, 'PUT', '/me', profile('Carol'));
    expect((await s.call(carol, 'POST', `/events/${id}/swipe`, { to: bob.id, like: true })).status).toBe(403);
    expect((await s.call(alice, 'POST', `/events/${id}/swipe`, { to: carol.id, like: true })).status).toBe(404);
    await s.call(bob, 'POST', '/block', { uid: alice.id });
    expect((await s.call(alice, 'POST', `/events/${id}/swipe`, { to: bob.id, like: true })).status).toBe(404);
  });
});

describe('guests', () => {
  it('can fill in a profile, check in and be scouted, but must sign in to swipe', async () => {
    const s = setup();
    const id = await room(s, [alice, guest]);
    const view = await s.call(guest, 'GET', `/events/${id}`);
    expect(view.body.guest).toBe(true);
    expect(view.body.people.map((p: any) => p.uid)).toEqual([alice.id]);
    expect((await s.call(guest, 'POST', `/events/${id}/scout`)).body.picks).toHaveLength(1);

    const r = await s.call(guest, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true });
    expect(r.status).toBe(403);
    expect(r.body.needsLogin).toBe(true);

    // After Google sign-in the identity id stays the same, so the check-in carries over.
    const signedIn = { ...guest, guest: false };
    expect((await s.call(signedIn, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true })).status).toBe(200);
  });
});

describe('place check-ins', () => {
  const day = '20261120';
  const dayStart = '2026-11-19T16:00:00Z'; // midnight in Kuala Lumpur
  const places: Places = {
    suggest: async () => [],
    nearby: async () => [],
    details: async (placeId) => ({ placeId, name: 'Common Ground', address: 'KL', lat: 3.1579, lng: 101.7116 }),
  };

  it('puts everyone at the same place on the same day in one room', async () => {
    const s = setup({ places });
    for (const p of [alice, bob]) await s.call(p, 'PUT', '/me', profile(p.id));
    const fix = { lat: 3.158, lng: 101.7116, accuracy: 30 };
    const a = await s.call(alice, 'POST', '/checkin', { place: 'Common Ground, KL', placeId: 'AQAB-xyz', day, dayStart, fix });
    const b = await s.call(bob, 'POST', '/checkin', { place: 'Common Ground', placeId: 'AQAB-xyz', day, dayStart, fix });
    expect(a.body.id).toBe(placeRoomId('AQAB-xyz', '', day));
    expect(b.body.id).toBe(a.body.id);
    const r = await s.call(alice, 'GET', `/events/${a.body.id}`);
    expect(r.body.event.kind).toBe('place');
    expect(r.body.people).toHaveLength(1);
  });

  it('needs you to be there', async () => {
    const s = setup({ places });
    await s.call(alice, 'PUT', '/me', profile('Alice'));
    const far = { lat: 3.25, lng: 101.7116, accuracy: 30 };
    const r = await s.call(alice, 'POST', '/checkin', { place: 'Common Ground', placeId: 'AQAB-xyz', day, dayStart, fix: far });
    expect(r.status).toBe(403);
    expect(r.body.error).toMatch(/away/);
  });

  it('slugs typed places and rejects a wrong date', async () => {
    const s = setup();
    await s.call(alice, 'PUT', '/me', profile('Alice'));
    const r = await s.call(alice, 'POST', '/checkin', { place: 'Café Común, Bangsar', day, dayStart });
    expect(r.body.id).toBe('place-t-cafe-comun-20261120');
    const bad = await s.call(alice, 'POST', '/checkin', { place: 'X', day, dayStart: '2026-10-01T00:00:00Z' });
    expect(bad.status).toBe(400);
  });
});

describe('the sidekick', () => {
  it('uses the model when it answers, and caches it', async () => {
    let calls = 0;
    const s = setup({
      model: async () => {
        calls++;
        return { text: '{"picks":[{"id":"p0","score":91,"reason":"Bob can help you raise."}]}' };
      },
    });
    const id = await room(s, [alice, bob]);
    const first = await s.call(alice, 'POST', `/events/${id}/scout`);
    expect(first.body).toMatchObject({ source: 'llm', picks: [{ uid: bob.id, score: 91 }] });
    await s.call(alice, 'POST', `/events/${id}/scout`);
    expect(calls).toBe(1);
  });

  it('falls back to the template when the model fails', async () => {
    const s = setup({ model: async () => ({ text: null, error: 'boom' }) });
    const id = await room(s, [alice, bob]);
    expect((await s.call(alice, 'POST', `/events/${id}/scout`)).body.source).toBe('template');
  });
});

describe('accounts', () => {
  it('delete removes the profile and the cards', async () => {
    const s = setup();
    const id = await room(s, [alice, bob]);
    await s.call(bob, 'DELETE', '/me');
    expect((await s.call(bob, 'GET', '/me')).body.profile).toBeNull();
    expect((await s.call(alice, 'GET', `/events/${id}`)).body.people).toEqual([]);
  });
});

describe('sidekick status', () => {
  it('reports no model when none is set up', async () => {
    const s = setup();
    const r = await s.call(guest, 'POST', '/status/check');
    expect(r.body).toMatchObject({ ok: false, model: null });
  });

  it('pings the model and remembers the last result', async () => {
    let reply: string | null = 'OK';
    const s = setup({ model: async () => ({ text: reply, error: reply ? undefined : 'OpenRouter 429: busy' }), modelName: 'test-model' });
    const ok = await s.call(alice, 'POST', '/status/check');
    expect(ok.body).toMatchObject({ ok: true, model: 'test-model', reply: 'OK', error: null });
    expect((await s.call(alice, 'GET', '/status')).body).toMatchObject({ model: 'test-model', lastOk: expect.any(String), lastError: null });
    reply = null;
    const bad = await s.call(alice, 'POST', '/status/check');
    expect(bad.body).toMatchObject({ ok: false, error: 'OpenRouter 429: busy' });
    expect((await s.call(alice, 'GET', '/status')).body.lastError).toMatchObject({ error: 'OpenRouter 429: busy' });
  });
});
