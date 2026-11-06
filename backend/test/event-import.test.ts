import { afterEach, describe, expect, it, vi } from 'vitest';
import { parseEventHtml, parseIcs, parseImportReply, pageText, safeUrl } from '../src/eventImport';

const lumaLike = `<html><head><title>x</title>
<script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"Organization","name":"Org"},
{"@type":"BusinessEvent","name":"Fintech Demo Day &amp; Mixer","startDate":"2026-11-20T18:30:00+08:00","endDate":"2026-11-20T21:30:00+08:00",
"location":{"@type":"Place","name":"Common Ground","address":{"streetAddress":"Jalan Ampang","addressLocality":"Kuala Lumpur"}}}]}</script>
</head><body>hello</body></html>`;

describe('parseEventHtml', () => {
  it('reads schema.org events, including inside @graph', () => {
    const ev = parseEventHtml(lumaLike, 'https://lu.ma/abc');
    expect(ev).toEqual({
      name: 'Fintech Demo Day & Mixer',
      place: 'Common Ground, Jalan Ampang, Kuala Lumpur',
      startsAt: '2026-11-20T10:30:00.000Z',
      endsAt: '2026-11-20T13:30:00.000Z',
      url: 'https://lu.ma/abc',
      source: 'structured',
    });
  });
  it('marks online events and skips broken JSON-LD', () => {
    const html = `<script type="application/ld+json">{oops</script><script type="application/ld+json">[{"@type":"Event","name":"AI Night","location":{"@type":"VirtualLocation","url":"https://zoom.us"}}]</script>`;
    expect(parseEventHtml(html, 'https://x.com')?.place).toBe('Online');
  });
  it('falls back to Open Graph, then gives up', () => {
    expect(parseEventHtml('<meta property="og:title" content="Startup Mixer">', 'https://x.com')).toMatchObject({ name: 'Startup Mixer', source: 'meta', startsAt: null });
    expect(parseEventHtml('<p>nothing</p>', 'https://x.com')).toBeNull();
  });
});

describe('sidekick import helpers', () => {
  it('strips scripts and tags from page text', () => {
    expect(pageText('<style>a{}</style><p>Hi <b>there</b></p><script>evil()</script>')).toBe('Hi there');
  });
  it('validates the model reply and never invents a bad date', () => {
    expect(parseImportReply('{"name":"Demo Day","place":"KL","startsAt":"not a date"}', 'https://x.com')).toMatchObject({ name: 'Demo Day', startsAt: null, source: 'llm' });
    expect(parseImportReply('{"name":"","place":"","startsAt":null}', 'https://x.com')).toBeNull();
    expect(parseImportReply('sure!', 'https://x.com')).toBeNull();
  });
});

describe('safeUrl', () => {
  it('allows only public https pages', () => {
    expect(safeUrl('https://lu.ma/abc#x')?.toString()).toBe('https://lu.ma/abc');
    for (const bad of ['http://lu.ma/a', 'https://localhost/a', 'https://127.0.0.1/a', 'https://[::1]/a', 'https://intranet/a', 'https://u:p@lu.ma/', 'https://lu.ma:8443/', 'javascript:alert(1)', 'nope'])
      expect(safeUrl(bad)).toBeNull();
  });
});

describe('parseIcs', () => {
  const ics = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'BEGIN:VTIMEZONE',
    'TZID:Asia/Kuala_Lumpur',
    'END:VTIMEZONE',
    'BEGIN:VEVENT',
    'SUMMARY:AI Builders KL\\, November',
    'DTSTART;TZID=Asia/Kuala_Lumpur:20261120T190000',
    'DTEND;TZID=Asia/Kuala_Lumpur:20261120T220000',
    'LOCATION:Common Ground Damansara Heights\\, Kuala Lumpur\\, Malaysia with a very long line that gets',
    '  folded by the calendar app',
    'URL:https://luma.com/ykboepwr',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');

  it('reads name, place, start and end (with time zone) and link', () => {
    expect(parseIcs(ics)).toEqual({
      name: 'AI Builders KL, November',
      place: 'Common Ground Damansara Heights, Kuala Lumpur, Malaysia with a very long line that gets folded by the calendar app',
      startsAt: '2026-11-20T11:00:00.000Z',
      endsAt: '2026-11-20T14:00:00.000Z',
      url: 'https://luma.com/ykboepwr',
      source: 'structured',
    });
  });
  it('handles UTC times and rejects files without an event', () => {
    expect(parseIcs('BEGIN:VEVENT\nSUMMARY:Demo\nDTSTART:20261121T010000Z\nEND:VEVENT')?.startsAt).toBe('2026-11-21T01:00:00.000Z');
    expect(parseIcs('BEGIN:VCALENDAR\nEND:VCALENDAR')).toBeNull();
  });
});
