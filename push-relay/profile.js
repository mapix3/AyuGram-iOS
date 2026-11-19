import { accountId, lockOf } from './badges.js';
import { ipTag, sameToken, statsStub } from './stats.js';

export const PROFILE_LIMITS = { nfts: 30, pinned: 6, usernames: 10, body: 16384, photo: 1572864, video: 8388608, seconds: 15, ids: 50 };

const CHUNK = 1048576;
const SECONDS_SLACK = 0.25;
const MAX_SIDE = 16384;
const READ_TTL = 60;
const MEDIA_EDGE_TTL = 3600;
const WRITES_PER_ID = 40;
const WRITES_PER_IP = 80;
const UPLOADS_PER_ID = 8;
const UPLOADS_PER_IP = 12;
const UPLOADS_TOTAL = 3000;
const CLAIMS_PER_IP = 6;
const VERIFY_TTL = 600000;
const VERIFY_PER_ID = 10;
const VERIFY_PER_IP = 30;
const VERIFY_TOTAL = 20000;
const VERIFY_USES_PER_USER = 40;
const SWEEP_BATCH = 128;
const SWEEP_ROUNDS = 16;
const VERIFY_PATH = '/profile/verify/start';
const NONCE = /^[0-9a-f]{32}$/;
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const BOT_NAME = /^[A-Za-z][A-Za-z0-9_]{3,31}$/;
const botNames = new Map();
const MEDIA_BUDGET = 3221225472;
const INTERNAL = 'https://profiles.ayugram.invalid';
const READ_CACHE = 'https://profile.ayugram.invalid/v1/';
const MEDIA_CACHE = 'https://profile-media.ayugram.invalid/v1/';
const UPLOAD_TYPES = {
  'image/jpeg': 'photo',
  'image/jpg': 'photo',
  'image/png': 'photo',
  'image/heic': 'photo',
  'image/heif': 'photo',
  'video/mp4': 'video',
  'video/quicktime': 'video',
};
const MEDIA_EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/heic': 'heic', 'video/mp4': 'mp4', 'video/quicktime': 'mov' };
const HEIC_BRANDS = new Set(['heic', 'heix', 'heim', 'heis', 'hevc', 'hevx', 'mif1', 'msf1']);
const MP4_BRANDS = new Set(['isom', 'iso2', 'iso3', 'iso4', 'iso5', 'iso6', 'mp41', 'mp42', 'avc1', 'M4V ', 'M4VH', 'M4VP', 'dash', 'mmp4', 'MSNV', '3gp4', '3gp5', '3gp6', 'f4v ']);
const MOV_FIRST = new Set(['moov', 'mdat', 'wide', 'free', 'skip', 'pnot']);
const RESERVED_USERNAMES = new Set(['botfather', 'spambot', 'premium', 'stars', 'gift', 'gifts', 'wallet', 'notoscam', 'verify', 'username', 'usernames', 'jobs', 'news', 'team', 'durov', 'pavel', 'nikolai']);
const RESERVED_PARTS = ['telegram', 'ayugram', 'official', 'support', 'admin', 'fragment', 'security', 'moderator'];
const SLUG = /^[A-Za-z][A-Za-z0-9]{1,47}-[1-9][0-9]{0,6}$/;
const HEX = /^[0-9a-fA-F]{6}$/;

function fail(error, status, extra) {
  return new Response(JSON.stringify({ error, ...(extra || {}) }), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } });
}

function ok(value, headers) {
  return new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...(headers || {}) } });
}

async function hex(bytes) {
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function label(value) {
  if (typeof value !== 'string') {
    return '';
  }
  const clean = value.normalize('NFC').replace(/[\u0000-\u001f\u007f-\u009f\u00ad\u061c\u180e\u200b-\u200f\u2028-\u202e\u2060-\u2069\ufeff<>&"'`\\]/g, '').replace(/\s+/g, ' ').trim();
  return [...clean].slice(0, 48).join('');
}

function cleanColors(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return null;
  }
  const colors = {};
  for (const name of ['center', 'edge', 'pattern', 'text']) {
    if (typeof value[name] === 'string' && HEX.test(value[name])) {
      colors[name] = value[name].toUpperCase();
    }
  }
  return colors.center && colors.edge ? colors : null;
}

export function cleanNft(item) {
  if (!item || typeof item !== 'object' || Array.isArray(item)) {
    return null;
  }
  const pinned = item.pinned === true;
  if (item.slug !== undefined && item.slug !== null && item.slug !== '') {
    return typeof item.slug === 'string' && SLUG.test(item.slug) ? { slug: item.slug, pinned } : null;
  }
  const collection = label(item.collection);
  const number = Number.isInteger(item.number) && item.number >= 1 && item.number <= 9999999 ? item.number : 0;
  if (!collection || !number) {
    return null;
  }
  const nft = { collection, model: label(item.model), backdrop: label(item.backdrop), pattern: label(item.pattern), number, pinned };
  const colors = cleanColors(item.colors);
  if (colors) {
    nft.colors = colors;
  }
  return nft;
}

export function cleanNfts(value) {
  if (!Array.isArray(value)) {
    return { error: 'bad_nfts' };
  }
  if (value.length > PROFILE_LIMITS.nfts) {
    return { error: 'too_many_nfts', extra: { max: PROFILE_LIMITS.nfts } };
  }
  const seen = new Set();
  const list = [];
  let pinned = 0;
  for (let index = 0; index < value.length; index += 1) {
    const nft = cleanNft(value[index]);
    if (!nft) {
      return { error: 'bad_nft', extra: { index } };
    }
    const key = nft.slug ? 's:' + nft.slug.toLowerCase() : 'c:' + nft.collection.toLowerCase() + '#' + nft.number;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    if (nft.pinned) {
      pinned += 1;
      nft.pinned = pinned <= PROFILE_LIMITS.pinned;
    }
    list.push(nft);
  }
  return { value: list };
}

export function cleanUsernames(value) {
  if (!Array.isArray(value)) {
    return { error: 'bad_usernames' };
  }
  if (value.length > PROFILE_LIMITS.usernames) {
    return { error: 'too_many_usernames', extra: { max: PROFILE_LIMITS.usernames } };
  }
  const list = [];
  for (const raw of value) {
    const name = typeof raw === 'string' ? raw.trim().replace(/^@/, '').toLowerCase() : '';
    if (!/^[a-z0-9_]{4,32}$/.test(name)) {
      return { error: 'bad_username', extra: { value: typeof raw === 'string' ? raw.slice(0, 40) : '' } };
    }
    if (RESERVED_USERNAMES.has(name) || RESERVED_PARTS.some((part) => name.includes(part))) {
      return { error: 'reserved_username', extra: { value: name } };
    }
    if (!list.includes(name)) {
      list.push(name);
    }
  }
  return { value: list };
}

export function cleanPatch(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { error: 'bad_request' };
  }
  const patch = {};
  if ('nfts' in input) {
    const nfts = cleanNfts(input.nfts);
    if (nfts.error) {
      return nfts;
    }
    patch.nfts = nfts.value;
  }
  if ('usernames' in input) {
    const usernames = cleanUsernames(input.usernames);
    if (usernames.error) {
      return usernames;
    }
    patch.usernames = usernames.value;
  }
  if ('bubbles' in input) {
    if (typeof input.bubbles !== 'boolean') {
      return { error: 'bad_bubbles' };
    }
    patch.bubbles = input.bubbles;
  }
  if ('background' in input) {
    if (input.background !== null) {
      return { error: 'bad_background' };
    }
    patch.background = null;
  }
  return Object.keys(patch).length ? { value: patch } : { error: 'bad_request' };
}

function ascii(bytes, start, end) {
  return end <= bytes.length ? String.fromCharCode(...bytes.subarray(start, end)) : '';
}

function boxes(view, start, end) {
  const list = [];
  let at = start;
  while (at + 8 <= end) {
    let size = view.getUint32(at);
    let header = 8;
    if (size === 1) {
      if (at + 16 > end) {
        break;
      }
      size = view.getUint32(at + 8) * 4294967296 + view.getUint32(at + 12);
      header = 16;
    } else if (size === 0) {
      size = end - at;
    }
    if (size < header || at + size > end) {
      break;
    }
    list.push({ type: String.fromCharCode(view.getUint8(at + 4), view.getUint8(at + 5), view.getUint8(at + 6), view.getUint8(at + 7)), start: at + header, end: at + size });
    at += size;
  }
  return list;
}

function spanSeconds(view, box) {
  if (box.end - box.start < 20) {
    return 0;
  }
  const v1 = view.getUint8(box.start) === 1;
  if (v1 && box.end - box.start < 32) {
    return 0;
  }
  const scale = view.getUint32(box.start + (v1 ? 20 : 12));
  const duration = v1 ? view.getUint32(box.start + 24) * 4294967296 + view.getUint32(box.start + 28) : view.getUint32(box.start + 16);
  return scale > 0 && duration > 0 && duration !== 4294967295 ? duration / scale : 0;
}

function movieInfo(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const top = boxes(view, 0, bytes.length);
  const moov = top.find((box) => box.type === 'moov');
  const info = { seconds: 0, width: 0, height: 0, boxes: top.length, fragmented: top.some((box) => box.type === 'moof') };
  if (!moov) {
    return info;
  }
  for (const box of boxes(view, moov.start, moov.end)) {
    if (box.type === 'mvhd') {
      info.seconds = Math.max(info.seconds, spanSeconds(view, box));
    }
    if (box.type === 'mvex') {
      info.fragmented = true;
    }
    if (box.type !== 'trak') {
      continue;
    }
    const children = boxes(view, box.start, box.end);
    const mdia = children.find((child) => child.type === 'mdia');
    const mdhd = mdia ? boxes(view, mdia.start, mdia.end).find((child) => child.type === 'mdhd') : null;
    if (mdhd) {
      info.seconds = Math.max(info.seconds, spanSeconds(view, mdhd));
    }
    const tkhd = children.find((child) => child.type === 'tkhd');
    if (tkhd && !info.width) {
      const v1 = view.getUint8(tkhd.start) === 1;
      const matrix = tkhd.start + (v1 ? 52 : 40);
      if (matrix + 44 <= tkhd.end) {
        const width = Math.round(view.getUint32(matrix + 36) / 65536);
        const height = Math.round(view.getUint32(matrix + 40) / 65536);
        if (width > 0 && height > 0) {
          const turned = Math.abs(view.getInt32(matrix) / 65536) < 0.5 && Math.abs(view.getInt32(matrix + 16) / 65536) < 0.5;
          info.width = turned ? height : width;
          info.height = turned ? width : height;
        }
      }
    }
  }
  return info;
}

function jpegSize(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let at = 2;
  while (at + 4 <= bytes.length) {
    if (bytes[at] !== 0xff) {
      return null;
    }
    const marker = bytes[at + 1];
    if (marker === 0xff) {
      at += 1;
      continue;
    }
    if (marker === 0x01 || marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7)) {
      at += 2;
      continue;
    }
    if (marker === 0xd9 || marker === 0xda) {
      return null;
    }
    const length = view.getUint16(at + 2);
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker) && at + 9 <= bytes.length) {
      return { height: view.getUint16(at + 5), width: view.getUint16(at + 7) };
    }
    at += 2 + length;
  }
  return null;
}

function heicSize(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const limit = Math.min(bytes.length - 16, 262144);
  let best = null;
  for (let at = 4; at < limit; at += 1) {
    if (bytes[at] === 0x69 && bytes[at + 1] === 0x73 && bytes[at + 2] === 0x70 && bytes[at + 3] === 0x65) {
      const width = view.getUint32(at + 8);
      const height = view.getUint32(at + 12);
      if (width > 0 && height > 0 && width <= MAX_SIDE && height <= MAX_SIDE && (!best || width * height > best.width * best.height)) {
        best = { width, height };
      }
    }
  }
  return best;
}

export function sniffMedia(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 24 && [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((byte, index) => bytes[index] === byte)) {
    return 'image/png';
  }
  if (bytes.length >= 12 && ascii(bytes, 4, 8) === 'ftyp') {
    const brand = ascii(bytes, 8, 12);
    if (HEIC_BRANDS.has(brand)) {
      return 'image/heic';
    }
    if (brand === 'qt  ') {
      return 'video/quicktime';
    }
    if (MP4_BRANDS.has(brand)) {
      return 'video/mp4';
    }
    return '';
  }
  return bytes.length >= 16 && MOV_FIRST.has(ascii(bytes, 4, 8)) ? 'video/quicktime' : '';
}

function side(value) {
  const number = Number.parseInt(String(value || ''), 10);
  return Number.isInteger(number) && number > 0 && number <= MAX_SIDE ? number : 0;
}

export function inspectMedia(bytes, kind, hint) {
  const mime = sniffMedia(bytes);
  if (!mime || UPLOAD_TYPES[mime] !== kind) {
    return { error: 'unsupported_type', status: 415 };
  }
  let found = null;
  let seconds = 0;
  if (mime === 'image/png') {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    found = ascii(bytes, 12, 16) === 'IHDR' ? { width: view.getUint32(16), height: view.getUint32(20) } : null;
    if (!found) {
      return { error: 'bad_media', status: 422 };
    }
  } else if (mime === 'image/jpeg') {
    found = jpegSize(bytes);
    if (!found) {
      return { error: 'bad_media', status: 422 };
    }
  } else if (mime === 'image/heic') {
    found = heicSize(bytes);
  } else {
    const info = movieInfo(bytes);
    if (!info.boxes || info.fragmented || !info.seconds) {
      return { error: 'bad_media', status: 422 };
    }
    seconds = info.seconds;
    found = info.width ? { width: info.width, height: info.height } : null;
    if (seconds > PROFILE_LIMITS.seconds + SECONDS_SLACK) {
      return { error: 'too_long', status: 422, extra: { seconds: Math.round(seconds * 100) / 100, max: PROFILE_LIMITS.seconds } };
    }
  }
  const wide = side(hint && hint.width);
  const tall = side(hint && hint.height);
  let width = found ? side(found.width) : 0;
  let height = found ? side(found.height) : 0;
  if (found && (!width || !height)) {
    return { error: 'bad_media', status: 422 };
  }
  if (!found || (wide === height && tall === width)) {
    width = wide;
    height = tall;
  }
  return { mime, ext: MEDIA_EXT[mime], type: kind, width, height, duration: seconds ? Math.round(seconds * 100) / 100 : null };
}

function randomHex(size) {
  return [...crypto.getRandomValues(new Uint8Array(size))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function randomCode() {
  return [...crypto.getRandomValues(new Uint8Array(4))].map((byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join('');
}

function unverified() {
  return fail('unverified', 403, { verifyUrl: VERIFY_PATH });
}

function emptyRecord(lock, now) {
  return { lock, nfts: [], usernames: [], bubbles: false, background: null, updatedAt: now, claimedAt: now };
}

function publicData(record) {
  if (!record) {
    return null;
  }
  const data = { nfts: record.nfts || [], usernames: record.usernames || [], bubbles: record.bubbles === true, background: record.background || null, updatedAt: record.updatedAt || 0 };
  return data.nfts.length || data.usernames.length || data.bubbles || data.background ? data : null;
}

function presentBackground(id, background, origin) {
  if (!background) {
    return null;
  }
  return {
    type: background.type,
    url: origin + '/profile/media/' + id + '/' + background.version + '.' + background.ext,
    width: background.width || 0,
    height: background.height || 0,
    mime: background.mime,
    size: background.size || 0,
    duration: background.duration === undefined ? null : background.duration,
    updatedAt: background.updatedAt || 0,
  };
}

function presentEntry(id, data, origin) {
  if (!data) {
    return null;
  }
  return { id, fake: true, nfts: data.nfts, usernames: data.usernames, background: presentBackground(id, data.background, origin), bubbles: data.bubbles, updatedAt: data.updatedAt };
}

function presentOwn(id, record, origin, verified) {
  const data = record ? { nfts: record.nfts || [], usernames: record.usernames || [], bubbles: record.bubbles === true, background: record.background || null, updatedAt: record.updatedAt || 0 } : { nfts: [], usernames: [], bubbles: false, background: null, updatedAt: 0 };
  return { ...presentEntry(id, data, origin), claimed: Boolean(record), verified: verified !== false, limits: PROFILE_LIMITS };
}

export class Profiles {
  constructor(state) {
    this.state = state;
    this.verifying = Promise.resolve();
  }

  async sweep(now, day) {
    const storage = this.state.storage;
    if ((await storage.get('limday')) === day) {
      return;
    }
    const cursor = await storage.get('sweep');
    let prefix = cursor && cursor.day === day ? cursor.prefix : 'lim:';
    let after = cursor && cursor.day === day ? cursor.after : '';
    for (let round = 0; round < SWEEP_ROUNDS; round += 1) {
      const page = await storage.list(after ? { prefix, startAfter: after, limit: SWEEP_BATCH } : { prefix, limit: SWEEP_BATCH });
      const entries = [...page];
      const stale = entries.filter(([key, value]) => (prefix === 'n:' ? !value || !(value.expires > now) : !key.endsWith(':' + day))).map(([key]) => key);
      if (stale.length) {
        await storage.delete(stale);
      }
      if (entries.length < SWEEP_BATCH) {
        if (prefix === 'lim:') {
          prefix = 'n:';
          after = '';
          continue;
        }
        await storage.delete('sweep');
        await storage.put('limday', day);
        return;
      }
      after = entries[entries.length - 1][0];
    }
    await storage.put('sweep', { day, prefix, after });
  }

  async allow(checks, now) {
    const storage = this.state.storage;
    const day = Math.floor(now / 86400000);
    await this.sweep(now, day);
    const active = checks.filter(([, subject]) => subject).map(([name, subject, limit]) => ['lim:' + name + ':' + subject + ':' + day, limit]);
    const counts = [];
    for (const [key, limit] of active) {
      const count = (await storage.get(key)) || 0;
      if (count >= limit) {
        return false;
      }
      counts.push([key, count]);
    }
    for (const [key, count] of counts) {
      await storage.put(key, count + 1);
    }
    return true;
  }

  async addBytes(delta) {
    if (!delta) {
      return;
    }
    const storage = this.state.storage;
    await storage.put('bytes', Math.max(((await storage.get('bytes')) || 0) + delta, 0));
  }

  async evict(key, stored) {
    const background = stored && stored.background;
    await this.state.storage.delete(key);
    if (background) {
      await this.addBytes(-(background.size || 0));
    }
    return background ? background.version : '';
  }

  async dropBackground(key, record, now) {
    const background = record.background;
    if (!background) {
      return '';
    }
    record.background = null;
    record.updatedAt = now;
    await this.state.storage.put(key, record);
    await this.addBytes(-(background.size || 0));
    return background.version;
  }

  async verifiedLock(id) {
    const verified = await this.state.storage.get('v:' + id);
    return verified && typeof verified.lock === 'string' ? verified.lock : '';
  }

  async authorize(input, now, claim) {
    const storage = this.state.storage;
    if (await storage.get('blk:' + input.id)) {
      return { error: fail('blocked', 403) };
    }
    if ((await this.verifiedLock(input.id)) !== input.lock) {
      return { error: unverified() };
    }
    const stored = await storage.get('p:' + input.id);
    const taken = stored && stored.lock !== input.lock ? stored : null;
    let record = taken ? null : stored || null;
    if (!record && claim) {
      if (!(await this.allow([['c', input.ip, CLAIMS_PER_IP]], now))) {
        return { error: fail('rate_limited', 429) };
      }
      record = emptyRecord(input.lock, now);
    }
    return { record, taken };
  }

  async verifyUse(input, now) {
    const storage = this.state.storage;
    const nonce = typeof input.nonce === 'string' && NONCE.test(input.nonce) ? input.nonce : '';
    const user = accountId(input.user);
    if (!nonce || !user) {
      return Response.json({ status: 'invalid' });
    }
    if (!(await this.allow([['vu', user, VERIFY_USES_PER_USER]], now))) {
      return Response.json({ status: 'limited' });
    }
    const pending = await storage.get('n:' + nonce);
    if (!pending || pending.expires <= now) {
      if (pending) {
        await storage.delete('n:' + nonce);
      }
      return Response.json({ status: 'invalid' });
    }
    if (input.bot === true || user !== pending.id) {
      await storage.delete('n:' + nonce);
      return Response.json({ status: 'wrong' });
    }
    if (input.commit !== true) {
      return Response.json({ status: 'ready', code: pending.code });
    }
    await storage.delete('n:' + nonce);
    const key = 'p:' + pending.id;
    const previousLock = await this.verifiedLock(pending.id);
    const stored = await storage.get(key);
    let previous = '';
    let wiped = false;
    if (stored && stored.lock !== pending.lock) {
      if (previousLock && previousLock === stored.lock) {
        stored.lock = pending.lock;
        await storage.put(key, stored);
      } else {
        previous = await this.evict(key, stored);
        wiped = true;
      }
    }
    await storage.put('v:' + pending.id, { lock: pending.lock, time: now });
    return Response.json({ status: 'verified', id: pending.id, wiped, previous });
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.startsWith('/media-')) {
      return this.media(request, url);
    }
    const storage = this.state.storage;
    const now = Date.now();
    if (request.method !== 'POST') {
      return fail('not_found', 404);
    }
    if (url.pathname === '/read') {
      const input = await request.json();
      const ids = (Array.isArray(input.ids) ? input.ids : []).filter((id) => accountId(id)).slice(0, PROFILE_LIMITS.ids);
      const found = ids.length ? await storage.get(ids.flatMap((id) => ['p:' + id, 'v:' + id])) : new Map();
      const items = {};
      for (const id of ids) {
        const record = found.get('p:' + id);
        const owner = found.get('v:' + id);
        items[id] = record && owner && owner.lock === record.lock ? publicData(record) : null;
      }
      return Response.json({ items });
    }
    if (url.pathname === '/verify-use') {
      const input = await request.json();
      const run = this.verifying.then(() => this.verifyUse(input, Date.now()));
      this.verifying = run.catch(() => null);
      return run;
    }
    const admin = /^\/admin\/(wipe|background|block|unblock)\/([1-9][0-9]{0,15})$/.exec(url.pathname);
    if (admin) {
      const [, action, id] = admin;
      const key = 'p:' + id;
      const record = await storage.get(key);
      if (action === 'unblock') {
        const existed = Boolean(await storage.get('blk:' + id));
        await storage.delete('blk:' + id);
        return Response.json({ ok: true, existed });
      }
      if (action === 'background') {
        const previous = record ? await this.dropBackground(key, record, now) : '';
        return Response.json({ ok: true, existed: Boolean(previous), previous });
      }
      if (action === 'block') {
        await storage.put('blk:' + id, { time: now });
      }
      const previous = record ? await this.evict(key, record) : '';
      return Response.json({ ok: true, existed: Boolean(record), previous });
    }
    const input = await request.json();
    if (!accountId(input.id) || typeof input.lock !== 'string' || !input.lock) {
      return fail('bad_auth', 401);
    }
    const key = 'p:' + input.id;
    if (url.pathname === '/me') {
      if (await storage.get('blk:' + input.id)) {
        return fail('blocked', 403);
      }
      const stored = await storage.get(key);
      const verified = (await this.verifiedLock(input.id)) === input.lock;
      return Response.json({ record: stored && stored.lock === input.lock ? stored : null, verified });
    }
    if (url.pathname === '/verify-status') {
      return Response.json({ verified: (await this.verifiedLock(input.id)) === input.lock });
    }
    if (url.pathname === '/verify-start') {
      if (await storage.get('blk:' + input.id)) {
        return fail('blocked', 403);
      }
      if (!(await this.allow([['vs', input.id + '.' + input.lock.slice(0, 16), VERIFY_PER_ID], ['vi', input.ip, VERIFY_PER_IP], ['va', 'all', VERIFY_TOTAL]], now))) {
        return fail('rate_limited', 429);
      }
      const nonce = randomHex(16);
      const code = randomCode();
      const expires = now + VERIFY_TTL;
      await storage.put('n:' + nonce, { id: input.id, lock: input.lock, code, expires, time: now });
      return Response.json({ nonce, code, expiresAt: expires });
    }
    if (url.pathname === '/write' || url.pathname === '/clear') {
      const clearing = url.pathname === '/clear';
      const patch = clearing ? { nfts: [], usernames: [], bubbles: false, background: null } : input.patch && typeof input.patch === 'object' ? input.patch : {};
      const keys = Object.keys(patch);
      const removing = keys.length === 1 && keys[0] === 'background';
      const auth = await this.authorize(input, now, !clearing && !removing);
      if (auth.error) {
        return auth.error;
      }
      if (auth.record && !(await this.allow([['w', input.id, WRITES_PER_ID], ['wi', input.ip, WRITES_PER_IP]], now))) {
        return fail('rate_limited', 429);
      }
      const evicted = auth.taken ? await this.evict(key, auth.taken) : '';
      if (!auth.record) {
        return Response.json({ record: null, previous: evicted });
      }
      const record = auth.record;
      for (const field of ['nfts', 'usernames', 'bubbles']) {
        if (field in patch) {
          record[field] = patch[field];
        }
      }
      const dropped = 'background' in patch ? await this.dropBackground(key, record, now) : '';
      record.updatedAt = now;
      await storage.put(key, record);
      return Response.json({ record, previous: dropped || evicted });
    }
    if (url.pathname === '/upload-check') {
      const auth = await this.authorize(input, now, false);
      return auth.error || Response.json({ ok: true });
    }
    if (url.pathname === '/upload-begin') {
      const size = Number.isInteger(input.size) && input.size > 0 ? input.size : 0;
      if (!size) {
        return fail('bad_request', 400);
      }
      const auth = await this.authorize(input, now, true);
      if (auth.error) {
        return auth.error;
      }
      const current = auth.record.background ? auth.record.background.size || 0 : 0;
      const squatted = auth.taken && auth.taken.background ? auth.taken.background.size || 0 : 0;
      if (((await storage.get('bytes')) || 0) - current - squatted + size > MEDIA_BUDGET) {
        return fail('storage_full', 507);
      }
      if (!(await this.allow([['u', input.id, UPLOADS_PER_ID], ['ui', input.ip, UPLOADS_PER_IP], ['ua', 'all', UPLOADS_TOTAL]], now))) {
        return fail('rate_limited', 429);
      }
      const evicted = auth.taken ? await this.evict(key, auth.taken) : '';
      await storage.put(key, auth.record);
      return Response.json({ ok: true, previous: evicted });
    }
    if (url.pathname === '/background-set') {
      const background = input.background;
      if (!background || typeof background.version !== 'string' || !Number.isInteger(background.size)) {
        return fail('bad_request', 400);
      }
      const auth = await this.authorize(input, now, false);
      if (auth.error) {
        return auth.error;
      }
      if (auth.taken) {
        await this.evict(key, auth.taken);
      }
      if (!auth.record) {
        return fail('conflict', 409);
      }
      const old = auth.record.background;
      auth.record.background = background;
      auth.record.updatedAt = now;
      await storage.put(key, auth.record);
      await this.addBytes(background.size - (old ? old.size || 0 : 0));
      const previous = old && old.version !== background.version ? old.version : '';
      return Response.json({ record: auth.record, previous });
    }
    return fail('not_found', 404);
  }

  async dropVersion(version) {
    const storage = this.state.storage;
    const meta = await storage.get('m:' + version);
    if (!meta) {
      return false;
    }
    const keys = Array.from({ length: meta.chunks }, (_, index) => 'c:' + version + ':' + index);
    for (let index = 0; index < keys.length; index += 128) {
      await storage.delete(keys.slice(index, index + 128));
    }
    await storage.delete('m:' + version);
    return true;
  }

  async media(request, url) {
    const storage = this.state.storage;
    if (request.method === 'POST' && url.pathname === '/media-put') {
      const version = request.headers.get('x-version') || '';
      const mime = request.headers.get('x-mime') || '';
      const bytes = new Uint8Array(await request.arrayBuffer());
      if (!/^[0-9a-f]{16}$/.test(version) || !MEDIA_EXT[mime] || !bytes.length || bytes.length > PROFILE_LIMITS.video) {
        return fail('bad_request', 400);
      }
      const chunks = Math.ceil(bytes.length / CHUNK);
      for (let index = 0; index < chunks; index += 1) {
        await storage.put('c:' + version + ':' + index, bytes.slice(index * CHUNK, (index + 1) * CHUNK).buffer);
      }
      await storage.put('m:' + version, { mime, size: bytes.length, chunks, time: Date.now() });
      return Response.json({ ok: true });
    }
    if (request.method === 'GET' && url.pathname === '/media-get') {
      const version = url.searchParams.get('v') || '';
      const meta = /^[0-9a-f]{16}$/.test(version) ? await storage.get('m:' + version) : null;
      if (!meta) {
        return fail('not_found', 404);
      }
      const keys = Array.from({ length: meta.chunks }, (_, index) => 'c:' + version + ':' + index);
      const found = await storage.get(keys);
      const out = new Uint8Array(meta.size);
      let at = 0;
      for (const key of keys) {
        const part = found.get(key);
        if (!part) {
          return fail('not_found', 404);
        }
        const view = part instanceof Uint8Array ? part : new Uint8Array(part);
        if (at + view.length > out.length) {
          return fail('not_found', 404);
        }
        out.set(view, at);
        at += view.length;
      }
      if (at !== meta.size) {
        return fail('not_found', 404);
      }
      return new Response(out, { headers: { 'content-type': meta.mime } });
    }
    if (request.method === 'POST' && url.pathname === '/media-delete') {
      const input = await request.json().catch(() => ({}));
      if (input && typeof input.version === 'string' && input.version) {
        return Response.json({ ok: true, existed: await this.dropVersion(input.version) });
      }
      const versions = [...(await storage.list({ prefix: 'm:' })).keys()].map((key) => key.slice(2));
      for (const version of versions) {
        await this.dropVersion(version);
      }
      return Response.json({ ok: true, existed: versions.length > 0 });
    }
    return fail('not_found', 404);
  }
}

function metaStub(env) {
  return env && env.PROFILES ? env.PROFILES.get(env.PROFILES.idFromName('global')) : null;
}

function mediaStub(env, id) {
  return env && env.PROFILES ? env.PROFILES.get(env.PROFILES.idFromName('media-' + id)) : null;
}

function call(stub, path, body) {
  return stub.fetch(INTERNAL + path, { method: 'POST', body: JSON.stringify(body || {}) });
}

function edgeCache() {
  return typeof caches !== 'undefined' && caches.default ? caches.default : null;
}

async function later(ctx, work) {
  const guarded = work.catch((error) => console.log('profile task failed: ' + error));
  if (ctx && typeof ctx.waitUntil === 'function') {
    ctx.waitUntil(guarded);
  } else {
    await guarded;
  }
}

async function purge(id) {
  const cache = edgeCache();
  if (cache && typeof cache.delete === 'function') {
    await cache.delete(new Request(READ_CACHE + id)).catch(() => false);
  }
}

async function purgeMedia(id, version) {
  const cache = edgeCache();
  if (cache && typeof cache.delete === 'function' && version) {
    await cache.delete(new Request(MEDIA_CACHE + id + '/' + version)).catch(() => false);
  }
}

async function readLimited(request, limit) {
  if (Number(request.headers.get('content-length') || 0) > limit) {
    return { error: fail('too_large', 413, { max: limit }) };
  }
  if (!request.body) {
    return { bytes: new Uint8Array(0) };
  }
  const reader = request.body.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    const part = value instanceof Uint8Array ? value : new Uint8Array(value);
    total += part.byteLength;
    if (total > limit) {
      await reader.cancel().catch(() => null);
      return { error: fail('too_large', 413, { max: limit }) };
    }
    parts.push(part);
  }
  const bytes = new Uint8Array(total);
  let at = 0;
  for (const part of parts) {
    bytes.set(part, at);
    at += part.byteLength;
  }
  return { bytes };
}

async function readJson(request, limit) {
  const read = await readLimited(request, limit);
  if (read.error) {
    return read;
  }
  try {
    return { value: JSON.parse(new TextDecoder().decode(read.bytes)) };
  } catch {
    return { error: fail('bad_request', 400) };
  }
}

export function network(ip) {
  const text = String(ip || '').trim().toLowerCase().replace(/%.*$/, '');
  if (!text.includes(':')) {
    return text;
  }
  const tail = text.split(':').pop();
  if (tail.includes('.')) {
    return tail;
  }
  const halves = text.split('::');
  if (halves.length > 2) {
    return text;
  }
  const left = halves[0] ? halves[0].split(':') : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
  const groups = halves.length === 2 ? [...left, ...Array(Math.max(8 - left.length - right.length, 0)).fill('0'), ...right] : left;
  if (groups.length !== 8 || groups.some((group) => !/^[0-9a-f]{1,4}$/.test(group))) {
    return text;
  }
  return groups.slice(0, 4).map((group) => group.replace(/^0+(?=.)/, '')).join(':') + '::/64';
}

async function identify(request, env) {
  const id = accountId(request.headers.get('x-ayugram-id') || '');
  const lock = await lockOf(request.headers.get('x-ayugram-secret') || '');
  if (!id || !lock) {
    return { error: fail('bad_auth', 401) };
  }
  let guard = { banned: false };
  const stats = statsStub(env);
  if (stats) {
    const response = await stats.fetch('https://stats.ayugram.invalid/profile-guard', { method: 'POST', body: JSON.stringify({ id }) }).catch(() => null);
    if (!response || !response.ok) {
      return { error: fail('unavailable', 503) };
    }
    guard = await response.json();
  }
  if (guard.banned) {
    return { error: fail('banned', 403) };
  }
  const ip = network(request.headers.get('cf-connecting-ip') || '');
  return { id, base: { id, lock, ip: ip ? await ipTag(ip) : '' } };
}

async function passError(response) {
  const text = await response.text();
  try {
    const parsed = JSON.parse(text);
    if (parsed && typeof parsed.error === 'string') {
      return fail(parsed.error, response.status, Object.fromEntries(Object.entries(parsed).filter(([name]) => name !== 'error')));
    }
  } catch {
    return fail('unavailable', response.status >= 500 ? response.status : 503);
  }
  return fail('unavailable', 503);
}

async function dropMedia(env, id, version) {
  const stub = mediaStub(env, id);
  if (stub && version !== '') {
    await call(stub, '/media-delete', version ? { version } : {});
  }
}

async function notifyBackground(env, id, bytes, media) {
  if (!env || !env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
    return false;
  }
  const caption = (media.type === 'video' ? '🎬 Новое видео' : '🖼 Новое фото') + ' на фоне профиля\nID ' + id + ' · ' + Math.round(bytes.length / 1024) + ' КБ' + (media.duration ? ' · ' + media.duration + ' с' : '');
  const markup = JSON.stringify({ inline_keyboard: [[{ text: '🗑 Удалить фон', callback_data: 'P:' + id }], [{ text: '⛔ Стереть всё и запретить', callback_data: 'J:' + id }]] });
  const send = async (method, field) => {
    const form = new FormData();
    form.append('chat_id', String(env.REPORT_CHAT_ID));
    form.append('caption', caption);
    form.append('reply_markup', markup);
    form.append(field, new Blob([bytes], { type: media.mime }), 'background.' + media.ext);
    const response = await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/' + method, { method: 'POST', body: form });
    return response.ok;
  };
  const direct = media.mime === 'image/jpeg' || media.mime === 'image/png' ? ['sendPhoto', 'photo'] : media.type === 'video' ? ['sendVideo', 'video'] : null;
  return (direct && (await send(direct[0], direct[1]))) || send('sendDocument', 'document');
}

export async function botUsername(env) {
  const configured = env && typeof env.REPORT_BOT_USERNAME === 'string' ? env.REPORT_BOT_USERNAME.trim().replace(/^@/, '') : '';
  if (BOT_NAME.test(configured)) {
    return configured;
  }
  const token = env && env.REPORT_BOT_TOKEN;
  if (!token) {
    return '';
  }
  if (botNames.has(token)) {
    return botNames.get(token);
  }
  const response = await fetch('https://api.telegram.org/bot' + token + '/getMe').catch(() => null);
  const data = response && response.ok ? await response.json().catch(() => null) : null;
  const name = data && data.ok && data.result && typeof data.result.username === 'string' && BOT_NAME.test(data.result.username) ? data.result.username : '';
  if (name) {
    botNames.set(token, name);
  }
  return name;
}

export async function profileVerify(env, nonce, user, commit) {
  const stub = metaStub(env);
  if (!stub || typeof nonce !== 'string' || !NONCE.test(nonce) || !user || !accountId(user.id)) {
    return { status: stub ? 'invalid' : 'error' };
  }
  const response = await call(stub, '/verify-use', { nonce, user: accountId(user.id), bot: user.is_bot === true, commit: commit === true }).catch(() => null);
  if (!response || !response.ok) {
    return { status: 'error' };
  }
  const result = await response.json();
  if (result.status === 'verified') {
    if (result.wiped) {
      await dropMedia(env, result.id, null);
    }
    await purge(result.id);
    await purgeMedia(result.id, result.previous);
  }
  return { status: result.status, code: result.code || '' };
}

export async function profileAdmin(env, id, action) {
  const stub = metaStub(env);
  if (!stub || !accountId(id) || !['wipe', 'background', 'block', 'unblock'].includes(action)) {
    return null;
  }
  const response = await call(stub, '/admin/' + action + '/' + id);
  if (!response.ok) {
    return null;
  }
  const result = await response.json();
  if (action !== 'unblock') {
    await dropMedia(env, id, null);
  }
  await purge(id);
  await purgeMedia(id, result.previous);
  delete result.previous;
  return result;
}

async function publicRead(request, env, url, ctx, stub) {
  const raw = url.searchParams.get('ids') || '';
  if (raw.length > 1200) {
    return fail('too_many_ids', 400, { max: PROFILE_LIMITS.ids });
  }
  const ids = [...new Set(raw.split(',').map((part) => part.trim()).filter(Boolean))];
  if (!ids.length || ids.some((id) => accountId(id) !== id)) {
    return fail('bad_ids', 400);
  }
  if (ids.length > PROFILE_LIMITS.ids) {
    return fail('too_many_ids', 400, { max: PROFILE_LIMITS.ids });
  }
  const cache = edgeCache();
  const records = {};
  const missing = [];
  await Promise.all(ids.map(async (id) => {
    const hit = cache ? await cache.match(new Request(READ_CACHE + id)).catch(() => null) : null;
    const parsed = hit ? await hit.json().catch(() => undefined) : undefined;
    if (parsed && 'r' in parsed) {
      records[id] = parsed.r;
    } else {
      missing.push(id);
    }
  }));
  if (missing.length) {
    const response = await call(stub, '/read', { ids: missing });
    if (!response.ok) {
      return fail('unavailable', 503);
    }
    const { items } = await response.json();
    for (const id of missing) {
      records[id] = items[id] || null;
    }
    if (cache) {
      await later(ctx, Promise.all(missing.map((id) => cache.put(new Request(READ_CACHE + id), new Response(JSON.stringify({ r: records[id] }), { headers: { 'content-type': 'application/json', 'cache-control': 'public, max-age=' + READ_TTL } })))));
    }
  }
  const body = JSON.stringify({ items: ids.map((id) => presentEntry(id, records[id], url.origin)).filter(Boolean) });
  const etag = 'W/"' + (await hex(new TextEncoder().encode(body))).slice(0, 20) + '"';
  const headers = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'public, max-age=' + READ_TTL, etag };
  if (request.headers.get('if-none-match') === etag) {
    return new Response(null, { status: 304, headers });
  }
  return new Response(body, { headers });
}

function byteRange(header, size) {
  const match = /^bytes=(\d*)-(\d*)$/.exec((header || '').trim());
  if (!match || (!match[1] && !match[2])) {
    return null;
  }
  let start;
  let end;
  if (!match[1]) {
    const suffix = Number(match[2]);
    if (!suffix) {
      return { invalid: true };
    }
    start = Math.max(size - suffix, 0);
    end = size - 1;
  } else {
    start = Number(match[1]);
    end = match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
  }
  return start > end || start >= size ? { invalid: true } : { start, end };
}

async function serveMedia(request, env, ctx, id, version, ext) {
  const etag = '"' + version + '"';
  const base = { etag, 'accept-ranges': 'bytes', 'cache-control': 'public, max-age=31536000, immutable', 'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'none'; sandbox", 'cross-origin-resource-policy': 'cross-origin' };
  if (request.headers.get('if-none-match') === etag) {
    return new Response(null, { status: 304, headers: base });
  }
  const cache = edgeCache();
  const key = new Request(MEDIA_CACHE + id + '/' + version);
  let bytes = null;
  let mime = '';
  const hit = cache ? await cache.match(key).catch(() => null) : null;
  if (hit && hit.ok) {
    mime = (hit.headers.get('content-type') || '').split(';')[0];
    bytes = new Uint8Array(await hit.arrayBuffer());
  }
  if (!bytes || !bytes.length || MEDIA_EXT[mime] !== ext) {
    const response = await mediaStub(env, id).fetch(INTERNAL + '/media-get?v=' + version);
    if (!response.ok) {
      return fail('not_found', 404);
    }
    mime = (response.headers.get('content-type') || '').split(';')[0];
    bytes = new Uint8Array(await response.arrayBuffer());
    if (MEDIA_EXT[mime] !== ext) {
      return fail('not_found', 404);
    }
    if (cache) {
      await later(ctx, cache.put(key, new Response(bytes, { headers: { 'content-type': mime, 'cache-control': 'public, max-age=' + MEDIA_EDGE_TTL } })));
    }
  }
  const size = bytes.length;
  const range = byteRange(request.headers.get('range'), size);
  const head = request.method === 'HEAD';
  if (range && range.invalid) {
    return new Response(null, { status: 416, headers: { ...base, 'content-range': 'bytes */' + size } });
  }
  if (range) {
    const part = bytes.subarray(range.start, range.end + 1);
    return new Response(head ? null : part, { status: 206, headers: { ...base, 'content-type': mime, 'content-length': String(part.length), 'content-range': 'bytes ' + range.start + '-' + range.end + '/' + size } });
  }
  return new Response(head ? null : bytes, { headers: { ...base, 'content-type': mime, 'content-length': String(size) } });
}

async function upload(request, env, url, ctx, stub, who) {
  const declared = (request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  const kind = UPLOAD_TYPES[declared];
  if (!kind) {
    return fail('unsupported_type', 415);
  }
  const limit = kind === 'video' ? PROFILE_LIMITS.video : PROFILE_LIMITS.photo;
  if (Number(request.headers.get('content-length') || 0) > limit) {
    return fail('too_large', 413, { max: limit });
  }
  const checked = await call(stub, '/upload-check', who.base);
  if (!checked.ok) {
    return passError(checked);
  }
  const read = await readLimited(request, limit);
  if (read.error) {
    return read.error;
  }
  const bytes = read.bytes;
  if (!bytes.length) {
    return fail('empty', 400);
  }
  const media = inspectMedia(bytes, kind, { width: request.headers.get('x-ayugram-width'), height: request.headers.get('x-ayugram-height') });
  if (media.error) {
    return fail(media.error, media.status, media.extra);
  }
  const begun = await call(stub, '/upload-begin', { ...who.base, size: bytes.length });
  if (!begun.ok) {
    return passError(begun);
  }
  const squatter = (await begun.json()).previous;
  if (squatter) {
    await dropMedia(env, who.id, null);
    await purgeMedia(who.id, squatter);
  }
  const version = [...crypto.getRandomValues(new Uint8Array(8))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  const stored = await mediaStub(env, who.id).fetch(INTERNAL + '/media-put', { method: 'POST', headers: { 'x-version': version, 'x-mime': media.mime }, body: bytes });
  if (!stored.ok) {
    return fail('store_failed', 502);
  }
  const now = Date.now();
  const background = { type: media.type, version, ext: media.ext, mime: media.mime, width: media.width, height: media.height, size: bytes.length, duration: media.duration, updatedAt: now };
  const set = await call(stub, '/background-set', { ...who.base, background });
  if (!set.ok) {
    await dropMedia(env, who.id, set.status === 409 ? null : version);
    return passError(set);
  }
  const { record, previous } = await set.json();
  if (previous) {
    await dropMedia(env, who.id, previous);
  }
  await purge(who.id);
  await purgeMedia(who.id, previous);
  await later(ctx, notifyBackground(env, who.id, bytes, media));
  return ok(presentOwn(who.id, record, url.origin));
}

export async function handleProfile(request, env, url, ctx) {
  const stub = metaStub(env);
  if (!stub) {
    return fail('unavailable', 503);
  }
  const path = url.pathname.replace(/\/+$/, '') || '/profile';
  const method = request.method;
  const media = /^\/profile\/media\/([1-9][0-9]{0,15})\/([0-9a-f]{16})\.(jpg|png|heic|mp4|mov)$/.exec(path);
  if (media) {
    return method === 'GET' || method === 'HEAD' ? serveMedia(request, env, ctx, media[1], media[2], media[3]) : fail('method_not_allowed', 405);
  }
  const admin = /^\/profile\/admin\/([1-9][0-9]{0,15})(?:\/(background|block|unblock))?$/.exec(path);
  if (admin) {
    const header = request.headers.get('authorization') || '';
    if (!sameToken(header.startsWith('Bearer ') ? header.slice(7) : '', env.STATS_TOKEN)) {
      return fail('forbidden', 403);
    }
    const action = !admin[2] ? (method === 'DELETE' ? 'wipe' : '') : admin[2] === 'background' ? (method === 'DELETE' ? 'background' : '') : method === 'POST' ? admin[2] : '';
    if (!action) {
      return fail('method_not_allowed', 405);
    }
    const result = await profileAdmin(env, admin[1], action);
    return result ? ok({ ...result, id: admin[1], action }) : fail('unavailable', 503);
  }
  if (path === '/profile' && method === 'GET') {
    return publicRead(request, env, url, ctx, stub);
  }
  const routes = { '/profile': ['PUT', 'POST', 'DELETE'], '/profile/me': ['GET'], '/profile/background': ['PUT', 'POST', 'DELETE'], '/profile/verify/start': ['POST'], '/profile/verify/status': ['GET'] };
  if (!routes[path]) {
    return fail('not_found', 404);
  }
  if (!routes[path].includes(method)) {
    return fail('method_not_allowed', 405);
  }
  const who = await identify(request, env);
  if (who.error) {
    return who.error;
  }
  if (path === '/profile/me') {
    const response = await call(stub, '/me', who.base);
    if (!response.ok) {
      return passError(response);
    }
    const own = await response.json();
    return ok(presentOwn(who.id, own.record, url.origin, own.verified === true));
  }
  if (path === '/profile/verify/status') {
    const response = await call(stub, '/verify-status', who.base);
    if (!response.ok) {
      return passError(response);
    }
    return ok({ verified: (await response.json()).verified === true });
  }
  if (path === '/profile/verify/start') {
    const name = await botUsername(env);
    if (!name) {
      return fail('unavailable', 503);
    }
    const response = await call(stub, '/verify-start', who.base);
    if (!response.ok) {
      return passError(response);
    }
    const started = await response.json();
    return ok({ nonce: started.nonce, code: started.code, url: 'https://t.me/' + name + '?start=pv_' + started.nonce, expiresAt: started.expiresAt, expiresIn: Math.round(VERIFY_TTL / 1000) });
  }
  if (path === '/profile/background' && method !== 'DELETE') {
    return upload(request, env, url, ctx, stub, who);
  }
  let response;
  if (path === '/profile' && method === 'DELETE') {
    response = await call(stub, '/clear', who.base);
  } else if (path === '/profile/background') {
    response = await call(stub, '/write', { ...who.base, patch: { background: null } });
  } else {
    const input = await readJson(request, PROFILE_LIMITS.body);
    if (input.error) {
      return input.error;
    }
    const patch = cleanPatch(input.value);
    if (patch.error) {
      return fail(patch.error, 400, patch.extra);
    }
    response = await call(stub, '/write', { ...who.base, patch: patch.value });
  }
  if (!response.ok) {
    return passError(response);
  }
  const result = await response.json();
  if (result.previous) {
    await dropMedia(env, who.id, result.previous);
  }
  await purge(who.id);
  await purgeMedia(who.id, result.previous);
  return ok(presentOwn(who.id, result.record, url.origin));
}
