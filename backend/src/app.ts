// The Sidekick API. Every request arrives signed with AWS credentials from the Cognito identity
// pool, so API Gateway has already checked who is calling: `identity.id` is the caller's Cognito
// identity id, and `identity.guest` is true until they sign in with Google.
//
// Privacy rules, enforced here (there is no other way to reach the data):
// - A profile is only ever returned to its owner.
// - Attendee cards are only shown to people checked in to the same event. Contact details are
//   never on a card: they're returned only to someone you matched with.
// - Swipes are never returned to anyone but the swiper, so nobody sees who passed or who
//   connected with them before it's mutual.
// - Guests can fill in a profile, check in and see who the sidekick picked, but swiping (and so
//   matching and seeing contacts) needs a Google sign-in.
// - Messages go only between two people who matched, and neither has blocked the other. Notes
//   (what's new with a match) go only to the person they're about.
// - Places and events don't check where anyone is. This is a prototype; a presence check comes later.
import { z } from 'zod';
import { buildImportPrompt, pageText, parseEventHtml, parseImportReply, safeUrl, type ImportedEvent } from './eventImport';
import { hash, placeRoomId } from './geo';
import type { Model } from './model';
import type { Places } from './places';
import {
  buildPrompt,
  buildScoutPrompt,
  parseLlmExchange,
  parseScout,
  templateExchange,
  templateScout,
  type Card,
  type Exchange,
  type Scout,
} from './sidekick';
import type { Item, Store } from './store';

export type Identity = { id: string; guest: boolean };
export type Deps = {
  store: Store;
  model: Model | null;
  modelName?: string;
  places: Places | null;
  fetch: typeof fetch;
  now: () => number;
  /** Cognito identity ids that may use the admin endpoints (signed in with Google only). */
  adminIds?: string[];
  /** Where profile photos are kept, and the public address they're served from (no trailing slash). */
  photos?: Photos;
  photoBaseUrl?: string;
};
/** Profile photo storage: a private bucket behind a CDN in production, a map in tests. */
export interface Photos {
  put(key: string, bytes: Uint8Array, contentType: string): Promise<void>;
  remove(key: string): Promise<void>;
}
export type Req = { method: string; path: string; body: unknown; identity: Identity };
export type Res = { status: number; body: unknown };

const DAY_S = 24 * 3600;
const SCOUTS_PER_USER_PER_EVENT = 15;
const OPENERS_PER_USER_PER_EVENT = 40;
const IMPORTS_PER_USER_PER_DAY = 20;
const PLACE_LOOKUPS_PER_USER_PER_DAY = 150;
const EVENTS_PER_USER_PER_DAY = 20;
const STATUS_CHECKS_PER_USER_PER_DAY = 30;
const MESSAGES_PER_USER_PER_DAY = 300;
const PHOTO_CHANGES_PER_USER_PER_DAY = 20;
const MAX_PHOTO_BYTES = 2_000_000;
const MAX_PHOTO_BASE64 = 2_800_000;
const MAX_MESSAGE = 500;
const NOTES_SHOWN = 100;

class HttpError extends Error {
  constructor(
    public status: number,
    message: string,
    public extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
}
const fail = (status: number, message: string, extra?: Record<string, unknown>): never => {
  throw new HttpError(status, message, extra);
};

// ---------- Validation ----------

const str = (max: number) => z.string().trim().max(max);
const tags = z.array(str(40).min(1)).max(6);
const contactSchema = z.object({
  linkedin: str(200).default(''),
  email: str(120).default(''),
  phone: str(40).default(''),
});
const profileSchema = z.object({
  displayName: str(80).min(1, 'Add your name.'),
  photoURL: z
    .string()
    .max(500)
    .refine((v) => v === '' || v.startsWith('https://'), 'Invalid photo.')
    .default(''),
  headline: str(100).default(''),
  lookingFor: tags.default([]),
  offering: tags.default([]),
  about: str(200).default(''),
  contact: contactSchema.default({ linkedin: '', email: '', phone: '' }),
});
// The look for people who haven't picked their own (the admin sets it).
const themes = ['system', 'light', 'dark'] as const;
const settingsSchema = z.object({ defaultTheme: z.enum(themes) });
const iso = z
  .string()
  .datetime({ offset: true })
  .transform((v) => new Date(v).toISOString());
const eventSchema = z
  .object({
    name: str(100).min(1, 'Give the event a name.'),
    place: str(140).default(''),
    placeId: str(300).optional(),
    lat: z.number().min(-90).max(90).optional(),
    lng: z.number().min(-180).max(180).optional(),
    startsAt: iso.nullable().default(null),
    endsAt: iso.nullable().default(null),
    sourceUrl: str(500).optional(),
  })
  .refine((e) => (e.lat === undefined) === (e.lng === undefined), 'Invalid location.')
  .refine((e) => !e.startsAt || !e.endsAt || e.endsAt > e.startsAt, 'The end must be after the start.');
const checkInSchema = z.object({
  place: str(140).min(1, 'Where are you?'),
  placeId: str(300).optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  day: z.string().regex(/^\d{8}$/),
  dayStart: iso,
});

function parse<T extends z.ZodTypeAny>(schema: T, body: unknown): z.output<T> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) return fail(400, r.error.issues[0]?.message || 'Invalid request.');
  return r.data;
}

// ---------- Shapes ----------

type Profile = z.output<typeof profileSchema> & { onboarded: boolean };
type EventOut = {
  id: string;
  name: string;
  place: string;
  placeId?: string;
  lat?: number;
  lng?: number;
  startsAt: string | null;
  endsAt: string | null;
  sourceUrl?: string;
  kind?: 'place';
  createdBy: string;
};
type CardOut = Card & { photoURL: string; visible: boolean };

const eventOut = (i: Item): EventOut => ({
  id: i.pk.slice('EVENT#'.length),
  name: i.name,
  place: i.place ?? '',
  placeId: i.placeId,
  lat: i.lat,
  lng: i.lng,
  startsAt: i.startsAt ?? null,
  endsAt: i.endsAt ?? null,
  sourceUrl: i.sourceUrl,
  kind: i.kind,
  createdBy: i.createdBy,
});
const cardOut = (i: Item): CardOut => ({
  uid: i.uid,
  displayName: i.displayName ?? '',
  photoURL: i.photoURL ?? '',
  headline: i.headline ?? '',
  lookingFor: i.lookingFor ?? [],
  offering: i.offering ?? [],
  about: i.about ?? '',
  visible: i.visible !== false,
});
const profileOut = (i: Item | null): Profile | null =>
  i
    ? {
        displayName: i.displayName ?? '',
        photoURL: i.photoURL ?? '',
        headline: i.headline ?? '',
        lookingFor: i.lookingFor ?? [],
        offering: i.offering ?? [],
        about: i.about ?? '',
        contact: { linkedin: '', email: '', phone: '', ...(i.contact ?? {}) },
        onboarded: i.onboarded === true,
      }
    : null;

const hasContact = (c: { linkedin: string; email: string; phone: string }) =>
  Boolean(c.linkedin.trim() || c.email.trim() || c.phone.trim());

/** When an event is over. Without an end, 6 hours after it starts. */
function endsAtMs(e: { startsAt: string | null; endsAt: string | null }): number | null {
  if (e.endsAt) return Date.parse(e.endsAt);
  if (e.startsAt) return Date.parse(e.startsAt) + 6 * 3600_000;
  return null;
}
const isOver = (e: { startsAt: string | null; endsAt: string | null }, now: number) => {
  const end = endsAtMs(e);
  return end !== null && end < now;
};

const matchKey = (a: string, b: string) => (a < b ? `MATCH#${a}#${b}` : `MATCH#${b}#${a}`);
const pairOf = (a: string, b: string): [string, string] => (a < b ? [a, b] : [b, a]);
const exchangeKey = (a: string, b: string) => `EXCHANGE#${pairOf(a, b).join('#')}`;
const chatPk = (eventId: string, a: string, b: string) => `CHAT#${eventId}#${pairOf(a, b).join('#')}`;
const randomId = () => crypto.randomUUID().replace(/-/g, '').slice(0, 16);

/** Checks the first bytes, so a file has to really be the image type it says it is. */
function isImage(bytes: Uint8Array, type: string): boolean {
  const head = (n: number) => Buffer.from(bytes.subarray(0, n)).toString('hex');
  if (type === 'image/jpeg') return head(3) === 'ffd8ff';
  if (type === 'image/png') return head(8) === '89504e470d0a1a0a';
  return head(4) === '52494646' && Buffer.from(bytes.subarray(8, 12)).toString('ascii') === 'WEBP';
}

/** A note as the app shows it. The name and photo are the person's current ones, if they're still here. */
const noteOut = ({ note, card }: { note: Record<string, any>; card: Item | null }) => ({
  eventId: note.eventId as string,
  other: note.other as string,
  name: (card?.displayName as string) || (note.name as string) || 'Someone',
  photoURL: card ? ((card.photoURL as string) ?? '') : ((note.photoURL as string) ?? ''),
  left: !card,
  kind: note.kind as string,
  at: note.at as string,
  preview: (note.preview as string) ?? '',
  matchedAt: (note.matchedAt as string) ?? null,
  alertUnread: note.alertUnread === true,
  chatUnread: note.chatUnread === true,
});

// ---------- The app ----------

export class App {
  constructor(private d: Deps) {
    // Remember how the model's last real call went, so the status check can tell whether the
    // sidekick has been falling back to quick reads.
    const model = d.model;
    if (model) {
      this.d = {
        ...d,
        model: async (prompt, opts) => {
          const r = await model(prompt, opts);
          await this.store
            .put({
              pk: 'STATUS#model',
              sk: r.text ? 'LAST_OK' : 'LAST_ERROR',
              at: this.nowIso(),
              ...(r.text ? {} : { error: (r.error ?? 'No reply').slice(0, 300) }),
            })
            .catch(() => {});
          return r;
        },
      };
    }
  }

  private get store() {
    return this.d.store;
  }
  private nowIso = () => new Date(this.d.now()).toISOString();
  private ttl = (seconds: number) => Math.floor(this.d.now() / 1000) + seconds;

  async handle(req: Req): Promise<Res> {
    try {
      return { status: 200, body: await this.route(req) };
    } catch (e) {
      if (e instanceof HttpError) return { status: e.status, body: { error: e.message, ...e.extra } };
      console.error('Unhandled error', req.method, req.path, e);
      return { status: 500, body: { error: 'Something went wrong. Try again.' } };
    }
  }

  private async route({ method, path, body, identity: me }: Req): Promise<unknown> {
    const parts = path.replace(/^\/+|\/+$/g, '').split('/').filter(Boolean).map(decodeURIComponent);
    const is = (m: string, ...p: string[]) =>
      method === m && parts.length === p.length && p.every((x, i) => x === '*' || x === parts[i]);

    if (is('GET', 'me'))
      return {
        id: me.id,
        guest: me.guest,
        admin: this.isAdmin(me),
        profile: profileOut(await this.store.get(`USER#${me.id}`, 'PROFILE')),
        defaultTheme: await this.defaultTheme(),
      };
    if (parts[0] === 'admin') return this.admin(me, method, parts.slice(1), body);
    if (is('PUT', 'me')) return this.saveProfile(me, body);
    if (is('POST', 'me', 'photo')) return this.uploadPhoto(me, body);
    if (is('DELETE', 'me')) return this.deleteAccount(me);
    if (is('GET', 'events')) return this.listEvents(me);
    if (is('POST', 'events')) return this.createEvent(me, body);
    if (is('POST', 'checkin')) return this.checkIn(me, body);
    if (is('POST', 'import-event')) return this.importEvent(me, body);
    if (is('POST', 'places')) return this.places(me, body);
    if (is('POST', 'block')) return this.block(me, body);
    if (is('POST', 'report')) return this.report(me, body);
    if (is('GET', 'status')) return this.status();
    if (is('POST', 'status', 'check')) return this.checkModel(me);
    if (is('GET', 'alerts')) return this.alerts(me);
    if (is('POST', 'alerts', 'read')) return this.readAlerts(me);
    if (is('GET', 'chats')) return this.chats(me);
    if (is('GET', 'connections')) return this.connections(me);
    if (parts[0] === 'chats' && parts.length >= 3) {
      const [eventId, uid] = [parts[1], parts[2]];
      if (!/^[\w-]{1,160}$/.test(eventId) || uid.length > 128) fail(404, 'Not found.');
      if (is('GET', 'chats', '*', '*')) return this.chat(me, eventId, uid);
      if (is('POST', 'chats', '*', '*', 'messages')) return this.send(me, eventId, uid, body);
    }
    if (parts[0] === 'events' && parts.length >= 2) {
      const id = parts[1];
      if (!/^[\w-]{1,160}$/.test(id)) fail(404, 'Event not found.');
      if (is('GET', 'events', '*')) return this.room(me, id);
      if (is('POST', 'events', '*', 'join')) return this.join(me, id);
      if (is('POST', 'events', '*', 'leave')) return this.leave(me, id);
      if (is('POST', 'events', '*', 'visible')) return this.setVisible(me, id, body);
      if (is('POST', 'events', '*', 'scout')) return this.scout(me, id);
      if (is('POST', 'events', '*', 'swipe')) return this.swipe(me, id, body);
      if (is('GET', 'events', '*', 'matches', '*')) return this.match(me, id, parts[3]);
    }
    return fail(404, 'Not found.');
  }

  // ---------- Quotas and cache ----------

  private async takeQuota(key: string, limit: number, seconds = 2 * DAY_S) {
    return (await this.store.increment(`QUOTA#${key}`, 'QUOTA', this.ttl(seconds))) <= limit;
  }
  private async cached<T>(key: string): Promise<T | null> {
    const i = await this.store.get(`CACHE#${key}`, 'CACHE');
    if (!i || (i.ttl && i.ttl * 1000 < this.d.now())) return null;
    return JSON.parse(i.value) as T;
  }
  private async cache(key: string, value: unknown, seconds: number) {
    await this.store.put({ pk: `CACHE#${key}`, sk: 'CACHE', value: JSON.stringify(value), ttl: this.ttl(seconds) });
  }

  // ---------- Profile ----------

  private async saveProfile(me: Identity, body: unknown) {
    const p = parse(profileSchema, body);
    if (p.photoURL && !this.isOwnOrGooglePhoto(p.photoURL)) fail(400, 'Invalid photo.');
    const before = await this.store.get(`USER#${me.id}`, 'PROFILE');
    // An uploaded photo stays as long as the link is the same. A different link replaces it.
    const keepPhoto = Boolean(before?.photoKey) && before?.photoURL === p.photoURL;
    if (before?.photoKey && !keepPhoto) await this.removePhoto(before.photoKey);
    const profile: Profile = { ...p, onboarded: hasContact(p.contact) };
    await this.store.put({
      pk: `USER#${me.id}`,
      sk: 'PROFILE',
      ...profile,
      ...(keepPhoto ? { photoKey: before!.photoKey } : {}),
      guest: me.guest,
      updatedAt: this.nowIso(),
    });
    await this.refreshCards(me, profile);
    return { guest: me.guest, profile };
  }

  /** Keeps my cards at events that are still on in step with my profile. */
  private async refreshCards(me: Identity, profile: Profile) {
    const now = this.d.now();
    for (const e of await this.store.query(`USER#${me.id}`, 'EVENT#')) {
      if (isOver({ startsAt: e.startsAt ?? null, endsAt: e.endsAt ?? null }, now)) continue;
      const eventId = e.sk.slice('EVENT#'.length);
      const card = await this.store.get(`EVENT#${eventId}`, `ATT#${me.id}`);
      if (card) await this.store.put({ ...card, ...this.cardFields(me, profile), visible: card.visible !== false });
    }
  }

  /** Profile photos come from Google's sign-in picture or from our own photo store, and nowhere else. */
  private isOwnOrGooglePhoto(url: string) {
    let host: string;
    try {
      host = new URL(url).hostname;
    } catch {
      return false;
    }
    return host.endsWith('.googleusercontent.com') || (!!this.d.photoBaseUrl && url.startsWith(`${this.d.photoBaseUrl}/`));
  }

  /** Stores a new profile photo (base64 in the body), checks it really is an image, and replaces the old one. */
  private async uploadPhoto(me: Identity, body: unknown) {
    const { image, type } = parse(
      z.object({
        image: z.string().min(1).max(MAX_PHOTO_BASE64),
        type: z.enum(['image/jpeg', 'image/png', 'image/webp']),
      }),
      body,
    );
    if (!this.d.photos || !this.d.photoBaseUrl) fail(503, 'Photos are not set up yet.');
    const bytes = new Uint8Array(Buffer.from(image, 'base64'));
    if (bytes.length === 0 || bytes.length > MAX_PHOTO_BYTES) fail(400, 'Choose a photo under 2 MB.');
    if (!isImage(bytes, type)) fail(400, 'That file is not a JPEG, PNG or WebP photo.');
    const before =
      (await this.store.get(`USER#${me.id}`, 'PROFILE')) ?? fail(409, 'Finish your profile first.', { needsProfile: true });
    const today = new Date(this.d.now()).toISOString().slice(0, 10);
    if (!(await this.takeQuota(`photo:${today}:${me.id}`, PHOTO_CHANGES_PER_USER_PER_DAY, DAY_S)))
      fail(429, 'Too many photo changes today. Try again tomorrow.');
    const ext = type === 'image/png' ? 'png' : type === 'image/webp' ? 'webp' : 'jpg';
    const key = `photos/${crypto.randomUUID()}.${ext}`;
    await this.d.photos!.put(key, bytes, type);
    const next = { ...before, photoURL: `${this.d.photoBaseUrl}/${key}`, photoKey: key, updatedAt: this.nowIso() };
    await this.store.put(next);
    if (before.photoKey) await this.removePhoto(before.photoKey);
    await this.refreshCards(me, profileOut(next)!);
    return { photoURL: next.photoURL };
  }

  private async removePhoto(key: string) {
    await this.d.photos?.remove(key).catch((e) => console.error('photo remove failed', key, e));
  }

  private cardFields(me: Identity, p: Profile) {
    return {
      uid: me.id,
      displayName: p.displayName,
      photoURL: p.photoURL,
      headline: p.headline,
      lookingFor: p.lookingFor,
      offering: p.offering,
      about: p.about,
      contact: p.contact,
      guest: me.guest,
    };
  }

  // ---------- Admin ----------

  private isAdmin(me: Identity) {
    return !me.guest && (this.d.adminIds ?? []).includes(me.id);
  }

  /** The theme for people who haven't picked their own. */
  private async defaultTheme(): Promise<(typeof themes)[number]> {
    const s = await this.store.get('SETTINGS#app', 'SETTINGS');
    return (themes as readonly string[]).includes(s?.defaultTheme) ? s!.defaultTheme : 'dark';
  }

  private async admin(me: Identity, method: string, p: string[], body: unknown): Promise<unknown> {
    if (!this.isAdmin(me)) fail(403, 'This account is not an admin.');
    const is = (m: string, ...want: string[]) =>
      method === m && p.length === want.length && want.every((x, i) => x === '*' || x === p[i]);
    const id = p[1] ?? '';
    if (p.length > 1 && !/^[\w:.-]{1,160}$/.test(id)) fail(400, 'Invalid id.');

    if (is('PUT', 'settings')) {
      const s = parse(settingsSchema, body);
      await this.store.put({ pk: 'SETTINGS#app', sk: 'SETTINGS', defaultTheme: s.defaultTheme, updatedAt: this.nowIso() });
      return { defaultTheme: s.defaultTheme };
    }

    if (is('GET', 'overview')) {
      const [profiles, events, reports] = await Promise.all([
        this.store.scanBySk('PROFILE'),
        this.store.recent('EVENTS', 500),
        this.store.scanBySk('REPORT'),
      ]);
      const names = new Map(profiles.map((u) => [u.pk.slice('USER#'.length), String(u.displayName ?? '')]));
      return {
        users: profiles
          .map((u) => ({
            id: u.pk.slice('USER#'.length),
            displayName: u.displayName ?? '',
            headline: u.headline ?? '',
            guest: u.guest === true,
            contact: u.contact ?? null,
            updatedAt: u.updatedAt ?? null,
          }))
          .sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt))),
        events: events.map((e) => ({ ...eventOut(e), kind: e.kind ?? 'event', createdAt: e.createdAt ?? null })),
        reports: reports
          .map((r) => ({
            id: r.pk.slice('REPORT#'.length),
            reporter: r.reporter,
            reporterName: names.get(r.reporter) ?? '',
            reported: r.reported,
            reportedName: names.get(r.reported) ?? '',
            eventId: r.eventId ?? null,
            reason: r.reason ?? '',
            at: r.at ?? null,
          }))
          .sort((a, b) => String(b.at).localeCompare(String(a.at))),
      };
    }
    if (is('GET', 'events', '*')) {
      const meta = await this.store.get(`EVENT#${id}`, 'META');
      if (!meta) fail(404, 'Event not found.');
      const items = await this.store.query(`EVENT#${id}`, '');
      return {
        event: eventOut(meta!),
        attendees: items
          .filter((i) => i.sk.startsWith('ATT#'))
          .map((a) => ({ id: a.uid, displayName: a.displayName ?? '', headline: a.headline ?? '', guest: a.guest === true, visible: a.visible !== false })),
        swipes: items.filter((i) => i.sk.startsWith('SWIPE#')).length,
        matches: items.filter((i) => i.sk.startsWith('MATCH#')).length,
      };
    }
    if (is('DELETE', 'events', '*')) {
      for (const i of await this.store.query(`EVENT#${id}`, '', 100_000)) {
        if (i.sk.startsWith('ATT#')) await this.store.delete(`USER#${i.sk.slice('ATT#'.length)}`, `EVENT#${id}`);
        if (i.sk.startsWith('MATCH#')) {
          await this.dropConversation(id, i.users[0], i.users[1]);
          await this.dropConnection(id, i.users[0], i.users[1]);
        }
        await this.store.delete(i.pk, i.sk);
      }
      return { ok: true };
    }
    if (is('DELETE', 'users', '*')) return this.deleteAccount({ id, guest: false });
    if (is('DELETE', 'reports', '*')) {
      await this.store.delete(`REPORT#${id}`, 'REPORT');
      return { ok: true };
    }
    return fail(404, 'Not found.');
  }

  private async deleteAccount(me: Identity) {
    const mine = await this.store.query(`USER#${me.id}`, '');
    const photo = mine.find((i) => i.sk === 'PROFILE')?.photoKey;
    if (photo) await this.removePhoto(photo);
    // Matches, swipes, notes and messages go too, and the other side loses the match with them.
    for (const n of mine.filter((i) => i.sk.startsWith('NOTE#'))) await this.dropConversation(n.eventId, me.id, n.other);
    for (const i of mine.filter((i) => i.sk.startsWith('EVENT#'))) {
      const eventId = i.sk.slice('EVENT#'.length);
      await this.store.delete(`EVENT#${eventId}`, `ATT#${me.id}`);
      for (const s of await this.store.query(`EVENT#${eventId}`, `SWIPE#${me.id}#`)) await this.store.delete(s.pk, s.sk);
      for (const m of await this.store.query(`EVENT#${eventId}`, 'MATCH#')) {
        if (m.users.includes(me.id)) await this.dropConversation(eventId, me.id, m.users.find((u: string) => u !== me.id));
      }
    }
    // Connections go on both sides, so nobody keeps a listing for someone who has gone.
    for (const c of mine.filter((i) => i.sk.startsWith('CONN#'))) {
      await this.store.delete(`USER#${c.sk.slice('CONN#'.length)}`, `CONN#${me.id}`);
    }
    for (const i of mine) await this.store.delete(i.pk, i.sk);
    return { ok: true };
  }

  private async requireProfile(me: Identity): Promise<Profile> {
    const p = profileOut(await this.store.get(`USER#${me.id}`, 'PROFILE'));
    if (!p || !p.onboarded) fail(409, 'Finish your profile first.', { needsProfile: true });
    return p!;
  }

  // ---------- Events ----------

  private async listEvents(me: Identity) {
    const now = this.d.now();
    const recent = (await this.store.recent('EVENTS', 60)).map(eventOut);
    const byId = new Map(recent.map((e) => [e.id, e]));
    const mine = (await this.store.query(`USER#${me.id}`, 'EVENT#')).map((i) => {
      const id = i.sk.slice('EVENT#'.length);
      return {
        id,
        name: i.name,
        place: i.place ?? '',
        startsAt: i.startsAt ?? byId.get(id)?.startsAt ?? null,
        endsAt: i.endsAt ?? byId.get(id)?.endsAt ?? null,
        kind: i.kind,
        joinedAt: i.joinedAt,
      };
    });
    mine.sort((a, b) => (a.joinedAt < b.joinedAt ? 1 : -1));
    return { mine, open: recent.filter((e) => !isOver(e, now)) };
  }

  private async createEvent(me: Identity, body: unknown) {
    const e = parse(eventSchema, body);
    if (!(await this.takeQuota(`ev:${new Date(this.d.now()).toISOString().slice(0, 10)}:${me.id}`, EVENTS_PER_USER_PER_DAY, DAY_S)))
      fail(429, "You've added a lot of events today. Try again tomorrow.");
    if (e.sourceUrl && !safeUrl(e.sourceUrl)) fail(400, 'Invalid link.');
    const id = crypto.randomUUID().replace(/-/g, '').slice(0, 20);
    const createdAt = this.nowIso();
    await this.store.put({
      pk: `EVENT#${id}`,
      sk: 'META',
      ...e,
      createdBy: me.id,
      createdAt,
      gsi1pk: 'EVENTS',
      gsi1sk: `${createdAt}#${id}`,
    });
    return { id };
  }

  /** Check in to a place that isn't an event: one room per place per day. Opens it if needed, then joins. */
  private async checkIn(me: Identity, body: unknown) {
    const c = parse(checkInSchema, body);
    const profile = await this.requireProfile(me);
    const start = Date.parse(c.dayStart);
    if (Math.abs(start - this.d.now()) > 36 * 3600_000) fail(400, 'Check the date on your phone.');
    const id = placeRoomId(c.placeId, c.place, c.day);
    const existing = await this.store.get(`EVENT#${id}`, 'META');
    let where =
      typeof existing?.lat === 'number' ? { lat: existing.lat as number, lng: existing.lng as number } : null;
    if (!where && c.lat !== undefined && c.lng !== undefined) where = { lat: c.lat, lng: c.lng };
    if (!where && c.placeId && this.d.places) {
      const d = await this.d.places.details(c.placeId).catch(() => null);
      if (d) where = { lat: d.lat, lng: d.lng };
    }
    if (!existing) {
      const createdAt = this.nowIso();
      await this.store.create({
        pk: `EVENT#${id}`,
        sk: 'META',
        name: c.place.split(',')[0].trim().slice(0, 100),
        place: c.place,
        placeId: c.placeId,
        ...(where ?? {}),
        startsAt: new Date(start).toISOString(),
        endsAt: new Date(start + DAY_S * 1000).toISOString(),
        kind: 'place',
        createdBy: me.id,
        createdAt,
        gsi1pk: 'EVENTS',
        gsi1sk: `${createdAt}#${id}`,
      });
    }
    const event = eventOut((await this.store.get(`EVENT#${id}`, 'META'))!);
    await this.addAttendee(me, profile, event);
    return { id };
  }

  private async getEvent(id: string): Promise<EventOut> {
    const i = await this.store.get(`EVENT#${id}`, 'META');
    if (!i) fail(404, 'Event not found.');
    return eventOut(i!);
  }

  private async join(me: Identity, id: string) {
    const event = await this.getEvent(id);
    const profile = await this.requireProfile(me);
    const end = endsAtMs(event);
    if (event.endsAt && end! < this.d.now())
      fail(403, event.kind === 'place' ? 'Check-ins here are closed for the day.' : 'This event has ended.');
    await this.addAttendee(me, profile, event);
    return { ok: true };
  }

  private async addAttendee(me: Identity, profile: Profile, event: EventOut) {
    const existing = await this.store.get(`EVENT#${event.id}`, `ATT#${me.id}`);
    await this.store.put({
      pk: `EVENT#${event.id}`,
      sk: `ATT#${me.id}`,
      ...this.cardFields(me, profile),
      visible: existing ? existing.visible !== false : true,
      checkedInAt: existing?.checkedInAt ?? this.nowIso(),
    });
    await this.store.put({
      pk: `USER#${me.id}`,
      sk: `EVENT#${event.id}`,
      name: event.name,
      place: event.place,
      startsAt: event.startsAt,
      endsAt: event.endsAt,
      kind: event.kind,
      joinedAt: this.nowIso(),
    });
  }

  private async leave(me: Identity, id: string) {
    await this.store.delete(`EVENT#${id}`, `ATT#${me.id}`);
    await this.store.delete(`USER#${me.id}`, `EVENT#${id}`);
    return { ok: true };
  }

  private async setVisible(me: Identity, id: string, body: unknown) {
    const { visible } = parse(z.object({ visible: z.boolean() }), body);
    const card = await this.store.get(`EVENT#${id}`, `ATT#${me.id}`);
    if (!card) fail(403, 'Join the event first.');
    await this.store.put({ ...card!, visible });
    return { ok: true };
  }

  // ---------- The room ----------

  private async blockedSet(uid: string) {
    return new Set((await this.store.query(`USER#${uid}`, 'BLOCK#')).map((i) => i.sk.slice('BLOCK#'.length)));
  }

  /** People in the room I can see: visible, not me, and nobody blocked either way. */
  private async visibleOthers(me: Identity, id: string, cards: Item[]) {
    const blocked = await this.blockedSet(me.id);
    const out: Item[] = [];
    for (const c of cards) {
      if (c.uid === me.id || c.visible === false || blocked.has(c.uid)) continue;
      if ((await this.store.get(`USER#${c.uid}`, `BLOCK#${me.id}`)) !== null) continue;
      out.push(c);
    }
    return out;
  }

  private async room(me: Identity, id: string) {
    const event = await this.getEvent(id);
    // Three narrow reads instead of the whole event. Each has its own cap, so a busy room can't
    // push my swipes out of the query and bring back people I've already passed.
    const pk = `EVENT#${id}`;
    const [cards, mySwipes, matchItems] = await Promise.all([
      this.store.query(pk, 'ATT#'),
      this.store.query(pk, `SWIPE#${me.id}#`),
      this.store.query(pk, 'MATCH#'),
    ]);
    const mine = cards.find((c) => c.uid === me.id);
    if (!mine) return { event, guest: me.guest, me: null, count: cards.length };
    const others = await this.visibleOthers(me, id, cards);
    const known = await this.connectionsOf(me.id);
    const swipes: Record<string, boolean> = {};
    for (const s of mySwipes) swipes[s.to] = s.like === true;
    const matches = matchItems
      .filter((m) => m.users.includes(me.id))
      .map((m) => ({ uid: m.users.find((u: string) => u !== me.id), createdAt: m.createdAt }));
    return {
      event,
      guest: me.guest,
      me: cardOut(mine),
      count: cards.length,
      people: others.map(cardOut),
      // People here I've already connected with, at this event or an earlier one. The app skips them in the deck.
      connected: others.filter((c) => known.has(c.uid)).map((c) => ({ ...cardOut(c), eventId: known.get(c.uid)!.eventId })),
      swipes,
      matches,
    };
  }

  private async scout(me: Identity, id: string): Promise<Scout> {
    const items = await this.store.query(`EVENT#${id}`, 'ATT#');
    const mine = items.find((c) => c.uid === me.id);
    if (!mine) fail(403, 'Join the event first.');
    const meCard = cardOut(mine!);
    const known = await this.connectionsOf(me.id);
    // The sidekick doesn't suggest people I've already connected with: they don't need a second connect.
    const others = (await this.visibleOthers(me, id, items))
      .filter((c) => !known.has(c.uid))
      .map(cardOut)
      .sort((a, b) => (a.uid < b.uid ? -1 : 1));
    if (!others.length) return { source: 'template', picks: [] };
    const strip = (c: CardOut): Card => ({
      uid: c.uid,
      displayName: c.displayName,
      headline: c.headline,
      lookingFor: c.lookingFor,
      offering: c.offering,
      about: c.about,
    });
    const meC = strip(meCard);
    const othersC = others.map(strip);
    const key = `scout:${id}:${me.id}:${hash(JSON.stringify([meC, othersC]))}`;
    const hit = await this.cached<Scout>(key);
    if (hit) return hit;
    if (this.d.model && (await this.takeQuota(`rls:${id}:${me.id}`, SCOUTS_PER_USER_PER_EVENT))) {
      const { text, error } = await this.d.model(buildScoutPrompt(meC, othersC), { maxTokens: 2000, temperature: 0.2 });
      if (error) console.error('scout model error', error);
      const scout = text ? parseScout(text, meC, othersC) : null;
      if (scout) {
        await this.cache(key, scout, DAY_S);
        return scout;
      }
    }
    return templateScout(meC, othersC);
  }

  private async swipe(me: Identity, id: string, body: unknown) {
    if (me.guest) fail(403, 'Sign in with Google to connect with people.', { needsLogin: true });
    const { to, like } = parse(z.object({ to: z.string().min(1).max(128), like: z.boolean() }), body);
    if (to === me.id) fail(400, 'Invalid request.');
    const [mine, theirs] = await Promise.all([
      this.store.get(`EVENT#${id}`, `ATT#${me.id}`),
      this.store.get(`EVENT#${id}`, `ATT#${to}`),
    ]);
    if (!mine) fail(403, 'Join the event first.');
    if (!theirs) fail(404, 'This person has left the event.');
    if (like && theirs!.visible === false) fail(404, 'This person has left the event.');
    const blocked =
      (await this.store.get(`USER#${me.id}`, `BLOCK#${to}`)) || (await this.store.get(`USER#${to}`, `BLOCK#${me.id}`));
    if (blocked) fail(404, 'This person has left the event.');
    await this.store.put({ pk: `EVENT#${id}`, sk: `SWIPE#${me.id}#${to}`, from: me.id, to, like, at: this.nowIso() });
    if (!like) return { match: false };
    const back = await this.store.get(`EVENT#${id}`, `SWIPE#${to}#${me.id}`);
    if (back?.like !== true) return { match: false };
    const users = [me.id, to].sort();
    const at = this.nowIso();
    if (await this.store.create({ pk: `EVENT#${id}`, sk: matchKey(me.id, to), users, createdAt: at })) {
      await this.bumpNote(me.id, id, to, theirs, { kind: 'match', at, matchedAt: at, alertUnread: false });
      await this.bumpNote(to, id, me.id, mine, { kind: 'match', at, matchedAt: at, alertUnread: true });
      await this.recordConnection(me.id, to, id, at);
    }
    return { match: true };
  }

  private async match(me: Identity, id: string, other: string) {
    if (me.guest) fail(403, 'Sign in with Google to see your matches.', { needsLogin: true });
    const m = await this.store.get(`EVENT#${id}`, matchKey(me.id, other));
    if (!m) fail(404, 'No match with this person.');
    const [mine, theirs] = await Promise.all([
      this.store.get(`EVENT#${id}`, `ATT#${me.id}`),
      this.store.get(`EVENT#${id}`, `ATT#${other}`),
    ]);
    if (!theirs || !mine) fail(404, 'This person has left the event.');
    if ((await this.store.get(`USER#${me.id}`, `BLOCK#${other}`)) || (await this.store.get(`USER#${other}`, `BLOCK#${me.id}`)))
      fail(404, 'No match with this person.');
    const a = cardOut(mine!);
    const b = cardOut(theirs!);
    return {
      person: b,
      contact: { linkedin: '', email: '', phone: '', ...(theirs!.contact ?? {}) },
      matchedAt: m!.createdAt,
      exchange: await this.exchangeFor(id, a, b),
    };
  }

  /** The agents' conversation for a match. It's made once, on first view, and kept with the match for good. */
  private async exchangeFor(eventId: string, a: Card, b: Card): Promise<Exchange> {
    const pk = `EVENT#${eventId}`;
    const sk = exchangeKey(a.uid, b.uid);
    const kept = await this.store.get(pk, sk);
    if (kept) return kept.exchange as Exchange;
    let ex: Exchange | null = null;
    if (this.d.model && (await this.takeQuota(`rl:${eventId}:${a.uid}`, OPENERS_PER_USER_PER_EVENT))) {
      const { text, error } = await this.d.model(buildPrompt(a, b), { maxTokens: 500, temperature: 0.7 });
      if (error) console.error('exchange model error', error);
      ex = text ? parseLlmExchange(text, a, b) : null;
    }
    ex ??= templateExchange(a, b);
    // First write wins, so both people always read the same conversation.
    if (await this.store.create({ pk, sk, exchange: ex, createdAt: this.nowIso() })) return ex;
    return ((await this.store.get(pk, sk))?.exchange ?? ex) as Exchange;
  }

  // ---------- Alerts and messages ----------

  /** My note about one match: the latest thing between us, and what I haven't seen yet. */
  private async bumpNote(owner: string, eventId: string, other: string, card: Item | null, patch: Record<string, unknown>) {
    const sk = `NOTE#${eventId}#${other}`;
    const prev: Record<string, any> = (await this.store.get(`USER#${owner}`, sk)) ?? {};
    await this.store.put({
      ...prev,
      pk: `USER#${owner}`,
      sk,
      eventId,
      other,
      name: card?.displayName || prev.name || 'Someone',
      photoURL: card ? (card.photoURL ?? '') : (prev.photoURL ?? ''),
      ...patch,
    });
  }

  /** Talking is only for people who matched, and only while neither side has blocked the other. */
  private async matchedPair(me: Identity, eventId: string, other: string) {
    if (!(await this.store.get(`EVENT#${eventId}`, matchKey(me.id, other)))) fail(404, 'No match with this person.');
    if ((await this.store.get(`USER#${me.id}`, `BLOCK#${other}`)) || (await this.store.get(`USER#${other}`, `BLOCK#${me.id}`)))
      fail(404, 'No match with this person.');
  }

  /** My notes, newest first, skipping anyone blocked either way. Names and photos are read now. */
  private async notes(me: Identity) {
    const [rows, blocked] = await Promise.all([this.store.query(`USER#${me.id}`, 'NOTE#'), this.blockedSet(me.id)]);
    const out: { note: Record<string, any>; card: Item | null }[] = [];
    for (const note of rows) {
      if (blocked.has(note.other)) continue;
      if ((await this.store.get(`USER#${note.other}`, `BLOCK#${me.id}`)) !== null) continue;
      out.push({ note, card: await this.store.get(`EVENT#${note.eventId}`, `ATT#${note.other}`) });
    }
    return out.sort((a, b) => String(b.note.at).localeCompare(String(a.note.at)));
  }

  private async alerts(me: Identity) {
    const all = (await this.notes(me)).map(noteOut);
    return { items: all.slice(0, NOTES_SHOWN), unread: all.filter((n) => n.alertUnread).length };
  }

  private async readAlerts(me: Identity) {
    for (const n of await this.store.query(`USER#${me.id}`, 'NOTE#')) {
      if (n.alertUnread === true) await this.store.put({ ...n, alertUnread: false });
    }
    return { ok: true };
  }

  private async chats(me: Identity) {
    const all = (await this.notes(me)).map(noteOut);
    return { items: all.slice(0, NOTES_SHOWN), unread: all.filter((n) => n.chatUnread).length };
  }

  /** One conversation: the latest messages, oldest first. Opening it marks it read. */
  private async chat(me: Identity, eventId: string, other: string) {
    if (me.guest) fail(403, 'Sign in with Google to message people.', { needsLogin: true });
    await this.matchedPair(me, eventId, other);
    const [card, note, rows] = await Promise.all([
      this.store.get(`EVENT#${eventId}`, `ATT#${other}`),
      this.store.get(`USER#${me.id}`, `NOTE#${eventId}#${other}`),
      this.store.query(chatPk(eventId, me.id, other), 'MSG#', 50, true),
    ]);
    if (note?.chatUnread === true) await this.store.put({ ...note, chatUnread: false });
    return {
      person: {
        uid: other,
        name: card?.displayName || note?.name || 'Someone',
        photoURL: card ? (card.photoURL ?? '') : (note?.photoURL ?? ''),
        left: !card,
      },
      messages: rows.reverse().map((m) => ({ id: m.sk, mine: m.from === me.id, text: m.text, at: m.at })),
    };
  }

  /** Sends a message to someone I matched with, and lets them know. */
  private async send(me: Identity, eventId: string, other: string, body: unknown) {
    if (me.guest) fail(403, 'Sign in with Google to message people.', { needsLogin: true });
    const { text } = parse(z.object({ text: str(MAX_MESSAGE).min(1, 'Write a message first.') }), body);
    await this.matchedPair(me, eventId, other);
    const today = new Date(this.d.now()).toISOString().slice(0, 10);
    if (!(await this.takeQuota(`msg:${today}:${me.id}`, MESSAGES_PER_USER_PER_DAY, DAY_S)))
      fail(429, "You've sent a lot of messages today. Try again tomorrow.");
    const at = this.nowIso();
    const sk = `MSG#${at}#${randomId()}`;
    await this.store.put({ pk: chatPk(eventId, me.id, other), sk, from: me.id, text, at });
    const [mine, theirs] = await Promise.all([
      this.store.get(`EVENT#${eventId}`, `ATT#${me.id}`),
      this.store.get(`EVENT#${eventId}`, `ATT#${other}`),
    ]);
    const preview = text.slice(0, 80);
    await this.bumpNote(me.id, eventId, other, theirs, { kind: 'message', at, preview, chatUnread: false });
    await this.bumpNote(other, eventId, me.id, mine, { kind: 'message', at, preview, chatUnread: true, alertUnread: true });
    return { message: { id: sk, mine: true, text, at } };
  }

  /** Takes a match, and everything said in it, for both people. */
  private async dropConversation(eventId: string, a: string, b: string) {
    const pk = `EVENT#${eventId}`;
    await this.store.delete(pk, matchKey(a, b));
    await this.store.delete(pk, exchangeKey(a, b));
    for (const m of await this.store.query(chatPk(eventId, a, b), '')) await this.store.delete(m.pk, m.sk);
    await this.store.delete(`USER#${a}`, `NOTE#${eventId}#${b}`);
    await this.store.delete(`USER#${b}`, `NOTE#${eventId}#${a}`);
  }

  // ---------- Connections ----------

  /** Kept on both sides, across events, so two people who connected needn't connect again. Latest event wins. */
  private async recordConnection(a: string, b: string, eventId: string, matchedAt: string) {
    await this.store.put({ pk: `USER#${a}`, sk: `CONN#${b}`, eventId, matchedAt });
    await this.store.put({ pk: `USER#${b}`, sk: `CONN#${a}`, eventId, matchedAt });
  }

  /** The people I've connected with, by uid, with the event where we last connected. */
  private async connectionsOf(uid: string) {
    const rows = await this.store.query(`USER#${uid}`, 'CONN#');
    return new Map(rows.map((r) => [r.sk.slice('CONN#'.length), r] as const));
  }

  /** Everyone I've connected with, across events, with their contact details. Blocked people are left out. */
  private async connections(me: Identity) {
    if (me.guest) fail(403, 'Sign in with Google to see your connections.', { needsLogin: true });
    const [rows, blocked] = await Promise.all([this.store.query(`USER#${me.id}`, 'CONN#'), this.blockedSet(me.id)]);
    const out: Record<string, any>[] = [];
    for (const row of rows) {
      const uid = row.sk.slice('CONN#'.length);
      if (blocked.has(uid)) continue;
      if ((await this.store.get(`USER#${uid}`, `BLOCK#${me.id}`)) !== null) continue;
      const [profile, meta] = await Promise.all([
        this.store.get(`USER#${uid}`, 'PROFILE'),
        this.store.get(`EVENT#${row.eventId}`, 'META'),
      ]);
      const p = profileOut(profile);
      if (!p) continue;
      out.push({
        uid,
        displayName: p.displayName,
        photoURL: p.photoURL,
        headline: p.headline,
        contact: p.contact,
        eventId: row.eventId as string,
        eventName: (meta?.name as string) ?? '',
        matchedAt: row.matchedAt as string,
      });
    }
    return { items: out.sort((a, b) => String(b.matchedAt).localeCompare(String(a.matchedAt))) };
  }

  /** Forgets a connection made at this event, unless the two have connected again at a later one. */
  private async dropConnection(eventId: string, a: string, b: string) {
    const pairs: [string, string][] = [
      [a, b],
      [b, a],
    ];
    for (const [owner, other] of pairs) {
      const c = await this.store.get(`USER#${owner}`, `CONN#${other}`);
      if (c?.eventId === eventId) await this.store.delete(`USER#${owner}`, `CONN#${other}`);
    }
  }

  // ---------- Safety ----------

  private async block(me: Identity, body: unknown) {
    const { uid } = parse(z.object({ uid: z.string().min(1).max(128) }), body);
    if (uid === me.id) fail(400, 'Invalid request.');
    await this.store.put({ pk: `USER#${me.id}`, sk: `BLOCK#${uid}`, at: this.nowIso() });
    return { ok: true };
  }

  private async report(me: Identity, body: unknown) {
    const r = parse(
      z.object({ uid: z.string().min(1).max(128), eventId: z.string().max(160).optional(), reason: str(500).min(1) }),
      body,
    );
    if (!(await this.takeQuota(`rep:${me.id}`, 30, DAY_S))) fail(429, 'Too many reports today.');
    await this.store.put({
      pk: `REPORT#${crypto.randomUUID()}`,
      sk: 'REPORT',
      reporter: me.id,
      reported: r.uid,
      eventId: r.eventId,
      reason: r.reason,
      at: this.nowIso(),
    });
    return { ok: true };
  }

  // ---------- Places and imports ----------

  private async places(me: Identity, body: unknown) {
    const b = parse(
      z.object({
        input: str(200).optional(),
        placeId: str(400).optional(),
        lat: z.number().min(-90).max(90).optional(),
        lng: z.number().min(-180).max(180).optional(),
      }),
      body,
    );
    const p = this.d.places;
    if (!p) return { suggestions: [], places: [], place: null, disabled: true };
    const today = new Date(this.d.now()).toISOString().slice(0, 10);
    if (!(await this.takeQuota(`rlp:${today}:${me.id}`, PLACE_LOOKUPS_PER_USER_PER_DAY, DAY_S)))
      return { suggestions: [], places: [], place: null };
    try {
      if (b.placeId) return { place: await p.details(b.placeId) };
      if (b.lat !== undefined && b.lng !== undefined) return { places: await p.nearby(b.lat, b.lng) };
      if ((b.input ?? '').length >= 3) return { suggestions: await p.suggest(b.input!) };
      return { suggestions: [] };
    } catch (e) {
      console.error('places error', e);
      return { suggestions: [], places: [], place: null };
    }
  }

  private async importEvent(me: Identity, body: unknown): Promise<ImportedEvent> {
    const url = safeUrl((body as any)?.url);
    if (!url) fail(400, 'Paste a public https link to the event page.');
    const key = `import:${url!.toString()}`;
    const hit = await this.cached<ImportedEvent>(key);
    if (hit) return hit;
    const page = await fetchPage(this.d.fetch, url!).catch((): PageResult => ({ failed: 'unreachable' }));
    if ('failed' in page) fail(422, FAILURE_MESSAGES[page.failed], { reason: page.failed });
    const ok = page as { html: string; finalUrl: string };
    let result = parseEventHtml(ok.html, ok.finalUrl);
    if (result?.source !== 'structured' && this.d.model) {
      const today = new Date(this.d.now()).toISOString().slice(0, 10);
      if (await this.takeQuota(`rli:${today}:${me.id}`, IMPORTS_PER_USER_PER_DAY, DAY_S)) {
        const { text } = await this.d.model(buildImportPrompt(pageText(ok.html), ok.finalUrl, today), {
          maxTokens: 300,
          temperature: 0,
        });
        result = (text && parseImportReply(text, ok.finalUrl)) || result;
      }
    }
    if (!result) fail(422, "Couldn't find an event on that page. Fill in the details yourself.");
    await this.cache(key, result, DAY_S);
    return result!;
  }

  private async status() {
    const [ok, err] = await Promise.all([
      this.store.get('STATUS#model', 'LAST_OK'),
      this.store.get('STATUS#model', 'LAST_ERROR'),
    ]);
    return {
      model: this.d.model ? (this.d.modelName ?? 'configured') : null,
      places: this.d.places ? 'amazon location' : 'off',
      lastOk: ok?.at ?? null,
      lastError: err ? { at: err.at, error: err.error } : null,
    };
  }

  /** Sends the model a tiny prompt right now and reports whether it answered, and how fast. */
  private async checkModel(me: Identity) {
    if (!this.d.model) return { ok: false, model: null, ms: 0, error: 'No model is set up. The sidekick uses quick reads.' };
    const today = new Date(this.d.now()).toISOString().slice(0, 10);
    if (!(await this.takeQuota(`rlc:${today}:${me.id}`, STATUS_CHECKS_PER_USER_PER_DAY, DAY_S)))
      fail(429, 'That is enough checks for today. Try again tomorrow.');
    const started = Date.now();
    const r = await this.d.model(
      { system: 'You are a health check. Reply with the single word OK.', user: 'Are you there?' },
      { maxTokens: 300, temperature: 0 },
    );
    return {
      ok: !!r.text,
      model: this.d.modelName ?? 'configured',
      ms: Date.now() - started,
      reply: r.text?.slice(0, 80) ?? null,
      error: r.text ? null : (r.error ?? 'No reply'),
    };
  }
}

// ---------- Reading event pages ----------

const MAX_BYTES = 1_500_000;
const HEADERS = {
  'user-agent': 'SidekickBot/1.0 (+https://sidekick.artifisi.com)',
  accept: 'text/html,application/xhtml+xml',
};
type PageResult =
  | { html: string; finalUrl: string }
  | { failed: 'blocked' | 'missing' | 'not-a-page' | 'unreachable'; status?: number };

const FAILURE_MESSAGES: Record<string, string> = {
  blocked: "This site doesn't allow automatic reading. Fill in the details yourself.",
  missing: "That page doesn't exist. Check the link, or fill in the details yourself.",
  'not-a-page': "That link isn't a web page. Paste the event page's link instead.",
  unreachable: "Couldn't open that page. Check the link, or fill in the details yourself.",
};

async function fetchPage(doFetch: typeof fetch, url: URL): Promise<PageResult> {
  let current = url;
  for (let hop = 0; hop < 5; hop++) {
    const res = await doFetch(current.toString(), { redirect: 'manual', headers: HEADERS, signal: AbortSignal.timeout(8000) });
    if (res.status >= 300 && res.status < 400) {
      const next = safeUrl(new URL(res.headers.get('location') ?? '', current).toString());
      if (!next) return { failed: 'unreachable', status: res.status };
      current = next;
      continue;
    }
    if (!res.ok) return { failed: res.status === 404 || res.status === 410 ? 'missing' : 'blocked', status: res.status };
    if (!(res.headers.get('content-type') ?? '').includes('html')) return { failed: 'not-a-page' };
    const reader = res.body?.getReader();
    if (!reader) return { failed: 'not-a-page' };
    const chunks: Uint8Array[] = [];
    let size = 0;
    while (size < MAX_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      size += value.length;
    }
    await reader.cancel().catch(() => {});
    const bytes = new Uint8Array(Math.min(size, MAX_BYTES));
    let at = 0;
    for (const c of chunks) {
      const n = Math.min(c.length, bytes.length - at);
      if (n <= 0) break;
      bytes.set(c.subarray(0, n), at);
      at += n;
    }
    return { html: new TextDecoder().decode(bytes), finalUrl: current.toString() };
  }
  return { failed: 'unreachable' };
}
