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

  it('lets anyone join from anywhere while we are prototyping', async () => {
    const s = setup();
    await s.call(bob, 'PUT', '/me', profile('Bob'));
    const { body } = await s.call(alice, 'POST', '/events', { name: 'KLCC', lat: 3.1579, lng: 101.7116 });
    expect((await s.call(bob, 'POST', `/events/${body.id}/join`, { fix: { lat: 3.25, lng: 101.7116, accuracy: 20 } })).status).toBe(200);
    expect((await s.call(bob, 'GET', `/events/${body.id}`)).body.me).not.toBeNull();
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

  it('lets anyone check in from anywhere while we are prototyping', async () => {
    const s = setup({ places });
    await s.call(alice, 'PUT', '/me', profile('Alice'));
    const far = { lat: 3.25, lng: 101.7116, accuracy: 30 };
    const r = await s.call(alice, 'POST', '/checkin', { place: 'Common Ground', placeId: 'AQAB-xyz', day, dayStart, fix: far });
    expect(r.status).toBe(200);
    expect(r.body.id).toBe(placeRoomId('AQAB-xyz', '', day));
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

describe('admin', () => {
  const admin = alice;

  it('only lets listed, signed-in accounts in', async () => {
    const s = setup({ adminIds: [alice.id, guest.id] });
    expect((await s.call(alice, 'GET', '/me')).body).toMatchObject({ id: alice.id, admin: true });
    expect((await s.call(bob, 'GET', '/me')).body.admin).toBe(false);
    expect((await s.call(bob, 'GET', '/admin/overview')).status).toBe(403);
    // A guest identity is never an admin, even if listed.
    expect((await s.call(guest, 'GET', '/admin/overview')).status).toBe(403);
  });

  it('sets the theme for everyone who has not picked one, and only admins can', async () => {
    const s = setup({ adminIds: [admin.id] });
    expect((await s.call(bob, 'GET', '/me')).body.defaultTheme).toBe('dark');
    expect((await s.call(bob, 'PUT', '/admin/settings', { defaultTheme: 'light' })).status).toBe(403);
    expect((await s.call(admin, 'PUT', '/admin/settings', { defaultTheme: 'neon' })).status).toBe(400);
    expect((await s.call(admin, 'PUT', '/admin/settings', { defaultTheme: 'light' })).body).toEqual({ defaultTheme: 'light' });
    expect((await s.call(bob, 'GET', '/me')).body.defaultTheme).toBe('light');
    expect((await s.call(guest, 'GET', '/me')).body.defaultTheme).toBe('light');
  });

  it('lists people, events and reports, and deletes them', async () => {
    const s = setup({ adminIds: [admin.id] });
    const id = await room(s, [alice, bob, carol]);
    await s.call(carol, 'POST', '/report', { uid: bob.id, eventId: id, reason: 'Spam' });

    const o = (await s.call(admin, 'GET', '/admin/overview')).body;
    expect(o.users.map((u: any) => u.id).sort()).toEqual([alice.id, bob.id, carol.id].sort());
    expect(o.events.map((e: any) => e.id)).toContain(id);
    expect(o.reports).toHaveLength(1);
    expect(o.reports[0]).toMatchObject({ reported: bob.id, reportedName: 'bob', reason: 'Spam' });

    const ev = (await s.call(admin, 'GET', `/admin/events/${id}`)).body;
    expect(ev.attendees).toHaveLength(3);

    await s.call(admin, 'DELETE', `/admin/reports/${o.reports[0].id}`);
    expect((await s.call(admin, 'GET', '/admin/overview')).body.reports).toHaveLength(0);

    await s.call(admin, 'DELETE', `/admin/users/${encodeURIComponent(bob.id)}`);
    expect((await s.call(bob, 'GET', '/me')).body.profile).toBeNull();
    expect((await s.call(admin, 'GET', `/admin/events/${id}`)).body.attendees).toHaveLength(2);

    await s.call(admin, 'DELETE', `/admin/events/${id}`);
    expect((await s.call(admin, 'GET', `/admin/events/${id}`)).status).toBe(404);
    expect(await s.store.query(`USER#${alice.id}`, 'EVENT#')).toHaveLength(0);
  });
});

describe('a busy room', () => {
  it('keeps every pass, even past the 1,000-item query cap', async () => {
    const s = setup();
    const people: Identity[] = Array.from({ length: 40 }, (_, i) => ({
      id: `ap-southeast-1:p${String(i).padStart(2, '0')}`,
      guest: false,
    }));
    const id = await room(s, people);
    // Everyone passes on everyone else: 1,560 swipes, which is more than the cap.
    for (const from of people)
      for (const to of people)
        if (from !== to)
          await s.store.put({ pk: `EVENT#${id}`, sk: `SWIPE#${from.id}#${to.id}`, from: from.id, to: to.id, like: false, at: '' });
    const view = await s.call(people[39], 'GET', `/events/${id}`);
    expect(Object.keys(view.body.swipes)).toHaveLength(39);
    expect(view.body.people).toHaveLength(39);
  });
});

describe('the agents\' conversation', () => {
  it('is made once, kept with the match, and read back the same for both people', async () => {
    let calls = 0;
    const s = setup({
      model: async () => {
        calls++;
        return {
          text: JSON.stringify({
            turns: [
              { speaker: 'A', text: 'You build payments too?' },
              { speaker: 'B', text: 'Yes, for clinics.' },
            ],
            reason: 'Both build payments.',
            opener: 'Ask Bob about clinic billing.',
          }),
        };
      },
    });
    const id = await room(s, [alice, bob]);
    await s.call(alice, 'POST', `/events/${id}/swipe`, { to: bob.id, like: true });
    await s.call(bob, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true });
    const first = await s.call(alice, 'GET', `/events/${id}/matches/${encodeURIComponent(bob.id)}`);
    expect(first.body.exchange).toMatchObject({ source: 'llm', opener: 'Ask Bob about clinic billing.' });
    const second = await s.call(bob, 'GET', `/events/${id}/matches/${encodeURIComponent(alice.id)}`);
    expect(second.body.exchange).toEqual(first.body.exchange);
    expect(calls).toBe(1);
  });
});

describe('alerts and messages', () => {
  const matched = async (s: ReturnType<typeof setup>) => {
    const id = await room(s, [alice, bob, carol]);
    await s.call(alice, 'POST', `/events/${id}/swipe`, { to: bob.id, like: true });
    await s.call(bob, 'POST', `/events/${id}/swipe`, { to: alice.id, like: true });
    return id;
  };
  const talk = (s: ReturnType<typeof setup>, who: Identity, id: string, other: Identity, text: string) =>
    s.call(who, 'POST', `/chats/${id}/${encodeURIComponent(other.id)}/messages`, { text });

  it('tells the person who connected first when it becomes a match, and they can mark it read', async () => {
    const s = setup();
    const id = await matched(s);
    // Bob's Connect made the match, so he already saw it. Alice connected first and hears about it.
    expect((await s.call(alice, 'GET', '/alerts')).body).toMatchObject({
      unread: 1,
      items: [{ eventId: id, other: bob.id, name: 'bob', kind: 'match', alertUnread: true }],
    });
    expect((await s.call(bob, 'GET', '/alerts')).body.unread).toBe(0);
    await s.call(alice, 'POST', '/alerts/read');
    expect((await s.call(alice, 'GET', '/alerts')).body.unread).toBe(0);
  });

  it('sends messages between matched people, and marks them unread for the other', async () => {
    const s = setup();
    const id = await matched(s);
    const sent = await talk(s, alice, id, bob, '  Coffee tomorrow?  ');
    expect(sent.status).toBe(200);
    expect(sent.body.message).toMatchObject({ mine: true, text: 'Coffee tomorrow?' });
    expect((await s.call(bob, 'GET', '/chats')).body).toMatchObject({
      unread: 1,
      items: [{ other: alice.id, chatUnread: true, preview: 'Coffee tomorrow?' }],
    });
    expect((await s.call(alice, 'GET', '/chats')).body.unread).toBe(0);

    const thread = await s.call(bob, 'GET', `/chats/${id}/${encodeURIComponent(alice.id)}`);
    expect(thread.body.person).toMatchObject({ uid: alice.id, name: 'alice', left: false });
    expect(thread.body.messages).toMatchObject([{ mine: false, text: 'Coffee tomorrow?' }]);
    expect((await s.call(bob, 'GET', '/chats')).body.unread).toBe(0);
    const aliceThread = await s.call(alice, 'GET', `/chats/${id}/${encodeURIComponent(bob.id)}`);
    expect(aliceThread.body.messages[0].mine).toBe(true);
  });

  it('only lets matched people talk, and not once either side has blocked the other', async () => {
    const s = setup();
    const id = await matched(s);
    expect((await talk(s, carol, id, bob, 'hi')).status).toBe(404);
    expect((await talk(s, alice, id, bob, 'x'.repeat(501))).status).toBe(400);
    expect((await talk(s, guest, id, bob, 'hi')).body.needsLogin).toBe(true);
    await s.call(bob, 'POST', '/block', { uid: alice.id });
    expect((await talk(s, alice, id, bob, 'hi')).status).toBe(404);
    expect((await s.call(bob, 'GET', `/chats/${id}/${encodeURIComponent(alice.id)}`)).status).toBe(404);
    expect((await s.call(alice, 'GET', '/chats')).body.items).toEqual([]);
  });

  it('deleting an account takes its matches and messages away from the other side too', async () => {
    const s = setup();
    const id = await matched(s);
    await talk(s, alice, id, bob, 'hi');
    await s.call(alice, 'DELETE', '/me');
    expect((await s.call(bob, 'GET', '/chats')).body.items).toEqual([]);
    expect((await s.call(bob, 'GET', `/events/${id}`)).body.matches).toEqual([]);
    expect([...s.store.items.values()].filter((i) => i.pk.startsWith('CHAT#'))).toHaveLength(0);
  });
});

describe('profile photos', () => {
  const photoBaseUrl = 'https://photos.example.test';
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0]).toString('base64');
  const photoStore = () => {
    const files = new Map<string, Uint8Array>();
    return {
      files,
      photos: {
        put: async (key: string, bytes: Uint8Array) => void files.set(key, bytes),
        remove: async (key: string) => void files.delete(key),
      },
    };
  };

  it('stores an upload, shows it on the card, and replaces the old one', async () => {
    const p = photoStore();
    const s = setup({ photos: p.photos, photoBaseUrl });
    const id = await room(s, [alice, bob]);
    const first = await s.call(bob, 'POST', '/me/photo', { image: jpeg, type: 'image/jpeg' });
    expect(first.status).toBe(200);
    expect(first.body.photoURL).toMatch(/^https:\/\/photos\.example\.test\/photos\/.+\.jpg$/);
    expect((await s.call(alice, 'GET', `/events/${id}`)).body.people[0].photoURL).toBe(first.body.photoURL);

    // Saving the rest of the profile keeps the upload, because the link is the same.
    await s.call(bob, 'PUT', '/me', profile('bob', { photoURL: first.body.photoURL }));
    expect(p.files.size).toBe(1);

    await s.call(bob, 'POST', '/me/photo', { image: jpeg, type: 'image/jpeg' });
    expect(p.files.size).toBe(1);
    expect((await s.call(bob, 'GET', '/me')).body.profile.photoURL).not.toBe(first.body.photoURL);
  });

  it('refuses files that are not images, and photo links from other sites', async () => {
    const p = photoStore();
    const s = setup({ photos: p.photos, photoBaseUrl });
    await s.call(bob, 'PUT', '/me', profile('bob'));
    expect((await s.call(bob, 'POST', '/me/photo', { image: Buffer.from('hello').toString('base64'), type: 'image/jpeg' })).status).toBe(400);
    expect((await s.call(bob, 'PUT', '/me', profile('bob', { photoURL: 'https://tracker.example.com/a.jpg' }))).status).toBe(400);
    expect((await s.call(bob, 'PUT', '/me', profile('bob', { photoURL: 'https://lh3.googleusercontent.com/a/x' }))).status).toBe(200);
    expect(p.files.size).toBe(0);
  });

  it('says so when photos are not set up', async () => {
    const s = setup();
    await s.call(bob, 'PUT', '/me', profile('bob'));
    expect((await s.call(bob, 'POST', '/me/photo', { image: jpeg, type: 'image/jpeg' })).status).toBe(503);
  });
});
