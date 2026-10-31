// AyuGram push relay (Cloudflare Worker).
//
// A sideloaded AyuGram cannot receive Apple push notifications: Telegram holds no APNs key for
// its bundle. Instead AyuGram registers a Telegram Web Push subscription whose endpoint is this
// worker. The endpoint path carries the subscription's private key, auth secret and the user's
// Bark device key, so the worker stores nothing: it decrypts the push (RFC 8291) and forwards
// the title and text to Bark, which shows the notification.

const BARK_BASE = 'https://api.day.app';
const BARK_PUSH = BARK_BASE + '/push';
// Bark keeps relayed notifications in its history for a day, then deletes them itself.
const ARCHIVE_TTL = 24 * 60 * 60;

const ICON = 'https://raw.githubusercontent.com/mapix3/AyuGram-iOS/standard/Swiftgram/SGSettingsUI/Images.xcassets/AyuUpdatesChannel.imageset/AyuUpdatesChannel@3x.png';

const encoder = new TextEncoder();

const NOTIFY_DELAY_MS = 0;
const SEEN_TTL = 120;
const ACTIVE_MAX_SECONDS = 300;
const SENT_TTL_MS = 10 * 60 * 1000;

export class Presence {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const storage = this.state.storage;
    if (request.method === 'POST' && url.pathname === '/deliver') {
      const now = Date.now();
      if (((await storage.get('until')) || 0) > now) {
        return new Response('active');
      }
      const id = (await request.text()).slice(0, 200);
      if (!id) {
        return new Response('send');
      }
      const sent = (await storage.get('sent')) || {};
      for (const [key, time] of Object.entries(sent)) {
        if (now - time > SENT_TTL_MS) {
          delete sent[key];
        }
      }
      if (sent[id]) {
        return new Response('duplicate');
      }
      sent[id] = now;
      await storage.put('sent', sent);
      return new Response('send');
    }
    if (request.method === 'POST') {
      const seconds = Math.min(Math.max(Number(await request.text()) || 0, 0), ACTIVE_MAX_SECONDS);
      await storage.put('until', seconds ? Date.now() + seconds * 1000 : 0);
      return new Response('ok\n');
    }
    return new Response(String((await storage.get('until')) || 0));
  }
}

export async function activityId(barkKey) {
  return base64urlEncode(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode('ayugram-active|' + barkKey))));
}

function presence(env, id) {
  return env && env.PRESENCE ? env.PRESENCE.get(env.PRESENCE.idFromName(id)) : null;
}

export async function claimDelivery(env, barkKey, id) {
  const stub = presence(env, await activityId(barkKey));
  if (!stub) {
    return true;
  }
  try {
    const response = await stub.fetch('https://presence.ayugram.invalid/deliver', { method: 'POST', body: id || '' });
    return (await response.text()) === 'send';
  } catch (error) {
    console.log('presence unavailable: ' + error);
    return true;
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    // Open /test/<Bark key> in a browser to send a test notification and see Bark's answer.
    if (request.method === 'GET' && url.pathname.startsWith('/test/')) {
      const key = decodeURIComponent(url.pathname.slice(6)).replace(/\/+$/, '');
      const result = await sendToBark(key, 'AyuGram', 'Test notification');
      return new Response((result.ok ? 'OK' : 'Bark refused') + ' (' + result.status + '): ' + result.body + '\n', {
        status: result.ok ? 200 : 502,
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      });
    }
    if (request.method === 'POST' && url.pathname.startsWith('/active/')) {
      const id = url.pathname.slice(8);
      const stub = /^[A-Za-z0-9_-]{43}$/.test(id) ? presence(env, id) : null;
      if (!stub) {
        return new Response('bad id\n', { status: 400 });
      }
      await stub.fetch('https://presence.ayugram.invalid/', { method: 'POST', body: await request.text() });
      return new Response('ok\n');
    }
    if (request.method !== 'POST' || !url.pathname.startsWith('/p/')) {
      return new Response('AyuGram push relay\n');
    }
    let route;
    try {
      route = parseRoute(url.pathname.slice(3));
    } catch {
      return new Response('bad subscription\n', { status: 400 });
    }
    try {
      const body = new Uint8Array(await request.arrayBuffer());
      const encoding = (request.headers.get('content-encoding') || 'aes128gcm').toLowerCase();
      const plain = encoding === 'aesgcm'
        ? await decryptAesgcm(body, request.headers, route)
        : await decryptAes128gcm(body, route);
      const data = JSON.parse(new TextDecoder().decode(plain));
      const seen = seenUpdate(data);
      if (seen) {
        await rememberSeen(route.barkKey, seen);
        return new Response(null, { status: 201 });
      }
      const notification = describe(data);
      if (!notification) {
        return new Response(null, { status: 201 });
      }
      const delay = Number(env && env.NOTIFY_DELAY_MS !== undefined ? env.NOTIFY_DELAY_MS : NOTIFY_DELAY_MS);
      const deliver = async () => {
        if (delay > 0) {
          await new Promise((resolve) => setTimeout(resolve, delay));
        }
        const { title, text, link, icon, id } = notification;
        if (await alreadySeen(route.barkKey, data.custom) || !await claimDelivery(env, route.barkKey, id)) {
          return;
        }
        const result = await sendToBark(route.barkKey, title, text, { url: link, icon, id });
        if (!result.ok) {
          console.log('Bark refused the push: ' + result.status + ' ' + result.body);
        }
      };
      if (ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil(deliver().catch((error) => console.log('push not delivered: ' + error)));
      } else {
        await deliver();
      }
    } catch (error) {
      console.log('push not delivered: ' + error);
    }
    // Always accepted: an error status could make Telegram drop the subscription.
    return new Response(null, { status: 201 });
  },
};

// Sends a notification through Bark's JSON API; if Bark refuses it, retries with the older
// path API (/<key>/<title>/<body>). Returns the last answer.
export async function sendToBark(key, title, text, options = {}) {
  const url = options.url || 'ayugram://';
  const icon = options.icon || ICON;
  const attempt = async (request) => {
    const response = await request();
    return { ok: response.ok, status: response.status, body: (await response.text()).slice(0, 300) };
  };
  const json = await attempt(() => fetch(BARK_PUSH, {
    method: 'POST',
    headers: { 'content-type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ device_key: key, title, body: text, group: 'AyuGram', icon, url, isArchive: '1', ttl: ARCHIVE_TTL, ...(options.id ? { id: options.id } : {}) }),
  }));
  if (json.ok) {
    return json;
  }
  const query = new URLSearchParams({ group: 'AyuGram', icon, url, isArchive: '1', ttl: String(ARCHIVE_TTL), ...(options.id ? { id: options.id } : {}) });
  const path = BARK_BASE + '/' + encodeURIComponent(key) + '/' + encodeURIComponent(title) + '/' + encodeURIComponent(text) + '?' + query;
  const legacy = await attempt(() => fetch(path));
  return legacy.ok ? legacy : { ok: false, status: legacy.status, body: 'json ' + json.status + ' ' + json.body + ' | path ' + legacy.status + ' ' + legacy.body };
}

// Path layout (base64url): private key d (32) | public key (65, uncompressed) | auth (16) | Bark key.
export function parseRoute(token) {
  const blob = base64urlDecode(token);
  if (blob.length < 114 || blob[32] !== 4) {
    throw new Error('short subscription');
  }
  return {
    d: blob.slice(0, 32),
    publicKey: blob.slice(32, 97),
    auth: blob.slice(97, 113),
    barkKey: new TextDecoder().decode(blob.slice(113)),
  };
}

const MEDIA = {
  PHOTO: '📷 Photo', PHOTOS: '📷 Photos', VIDEO: '📹 Video', VIDEOS: '📹 Videos', ROUND: '📹 Video message',
  AUDIO: '🎤 Voice message', DOC: '📎 File', DOCS: '📎 Files', PLAYLIST: '🎵 Music', GIF: 'GIF', STICKER: 'Sticker',
  CONTACT: '👤 Contact', GEO: '📍 Location', GEOLIVE: '📍 Live location', POLL: '📊 Poll', QUIZ: '📊 Quiz',
  GAME: '🎮 Game', INVOICE: 'Invoice', FWDS: 'Forwarded messages', MESSAGES: 'Album', NOTEXT: 'Message',
};
// Sync pushes that tell other devices about reads or deletions; they are not notifications.
const SILENT = /^(READ_|MESSAGE_DELETED|MESSAGE_MUTED|SESSION_REVOKE|GEO_LIVE_PENDING)/;

// Telegram's placeholder avatar colors, picked by id the way Telegram picks them.
const AVATAR_COLORS = ['e17076', 'eda86c', 'a695e7', '7bc862', '6ec9cb', '65aadd', 'ee7aae'];

// The chat a push belongs to: a link that opens it in AyuGram and a letter avatar for it.
// Real profile photos need Telegram's own protocol, so the avatar shows the first letter.
export function chatTarget(custom, name) {
  if (!custom || typeof custom !== 'object') {
    return {};
  }
  let kind = null;
  let id = null;
  for (const [field, value] of [['channel', custom.channel_id], ['chat', custom.chat_id], ['user', custom.from_id]]) {
    if (value !== undefined && /^\d+$/.test(String(value))) {
      kind = field;
      id = String(value);
      break;
    }
  }
  if (!kind) {
    return {};
  }
  const color = AVATAR_COLORS[Number(BigInt(id) % 7n)];
  const letter = (Array.from(name.trim())[0] || '?').toUpperCase();
  const icon = 'https://ui-avatars.com/api/?' + new URLSearchParams({ name: letter, size: '128', background: color, color: 'ffffff', bold: 'true', format: 'png', length: '1' });
  const target = { link: 'ayugram://chat?' + kind + '=' + id, icon };
  if (custom.msg_id !== undefined && /^\d+$/.test(String(custom.msg_id))) {
    target.id = kind + id + 'm' + custom.msg_id;
  }
  return target;
}

export function chatKey(custom) {
  if (!custom || typeof custom !== 'object') {
    return null;
  }
  for (const [field, value] of [['channel', custom.channel_id], ['chat', custom.chat_id], ['user', custom.from_id]]) {
    if (value !== undefined && /^\d+$/.test(String(value))) {
      return field + String(value);
    }
  }
  return null;
}

export function seenUpdate(data) {
  const key = typeof data.loc_key === 'string' ? data.loc_key : '';
  const chat = chatKey(data.custom);
  if (!chat) {
    return null;
  }
  if (key.startsWith('READ_HISTORY') && /^\d+$/.test(String(data.custom.max_id))) {
    return { chat, maxId: Number(data.custom.max_id) };
  }
  if (key.startsWith('MESSAGE_DELETED') && data.custom.messages !== undefined) {
    const deleted = String(data.custom.messages).split(',').map((value) => value.trim()).filter((value) => /^\d+$/.test(value));
    return deleted.length ? { chat, deleted } : null;
  }
  return null;
}

function seenCache() {
  return typeof caches !== 'undefined' && caches.default ? caches.default : null;
}

async function seenRequest(barkKey, parts) {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode([barkKey, ...parts].join('|'))));
  return new Request('https://seen.ayugram.invalid/' + base64urlEncode(digest));
}

async function rememberSeen(barkKey, seen) {
  const cache = seenCache();
  if (!cache) {
    return;
  }
  const headers = { 'cache-control': 'max-age=' + SEEN_TTL };
  if (seen.maxId !== undefined) {
    const request = await seenRequest(barkKey, ['read', seen.chat]);
    const previous = await cache.match(request);
    const current = previous ? Number(await previous.text()) : 0;
    await cache.put(request, new Response(String(Math.max(current, seen.maxId)), { headers }));
  }
  for (const id of seen.deleted || []) {
    await cache.put(await seenRequest(barkKey, ['deleted', seen.chat, id]), new Response('1', { headers }));
  }
}

export async function alreadySeen(barkKey, custom) {
  const cache = seenCache();
  const chat = chatKey(custom);
  if (!cache || !chat || !/^\d+$/.test(String(custom.msg_id))) {
    return false;
  }
  const read = await cache.match(await seenRequest(barkKey, ['read', chat]));
  if (read && Number(await read.text()) >= Number(custom.msg_id)) {
    return true;
  }
  return Boolean(await cache.match(await seenRequest(barkKey, ['deleted', chat, String(custom.msg_id)])));
}

// Title and text of a notification, or null for a push that shows nothing.
export function describe(data) {
  const args = Array.isArray(data.loc_args) ? data.loc_args.map(String) : [];
  const key = typeof data.loc_key === 'string' ? data.loc_key : null;
  if (key !== null && (key === '' || SILENT.test(key))) {
    return null;
  }
  if (data.custom && typeof data.custom === 'object' && String(data.custom.schedule) === '1') {
    return null;
  }
  if (key !== null) {
    let title = args[0], author = null, rest = args.slice(1);
    if (key.startsWith('CHAT_')) {
      author = args[0];
      title = args[1];
      rest = args.slice(2);
    }
    const kind = key.replace(/^(CHAT_|CHANNEL_)?(PINNED_)?MESSAGES?_/, '').replace(/^(CHAT_|CHANNEL_)?MESSAGES$/, 'MESSAGES');
    let text;
    if (kind === 'TEXT') {
      text = rest.join(' ');
    } else if (kind === 'STICKER') {
      text = [rest[0], MEDIA.STICKER].filter(Boolean).join(' ');
    } else if (kind === 'POLL' || kind === 'QUIZ') {
      text = [MEDIA[kind], rest[0]].filter(Boolean).join(': ');
    } else if (MEDIA[kind]) {
      text = MEDIA[kind];
    } else {
      text = rest.join(' ');
    }
    text = text || 'New message';
    if (key.startsWith('PHONE_CALL_REQUEST')) {
      text = '📞 Incoming call';
    }
    if (key.startsWith('PINNED_') || key.includes('_PINNED_')) {
      text = '📌 ' + text;
    }
    const name = title || 'AyuGram';
    return { title: name, text: author ? author + ': ' + text : text, ...chatTarget(data.custom, name) };
  }
  const alert = data.aps && typeof data.aps.alert === 'object' ? data.aps.alert : {};
  const title = data.title || alert.title || 'AyuGram';
  const text = data.description || data.body || alert.body || 'New message';
  return { title: String(title), text: String(text) };
}

async function decryptAes128gcm(body, route) {
  const salt = body.slice(0, 16);
  const recordSize = new DataView(body.buffer, body.byteOffset + 16, 4).getUint32(0);
  const idLength = body[20];
  const senderKey = body.slice(21, 21 + idLength);
  const ciphertext = body.slice(21 + idLength);
  const ecdh = await sharedSecret(route, senderKey);
  const ikm = await hkdfExpand(await hmac(route.auth, ecdh), concat(encoder.encode('WebPush: info\0'), route.publicKey, senderKey), 32);
  const prk = await hmac(salt, ikm);
  const key = await hkdfExpand(prk, encoder.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdfExpand(prk, encoder.encode('Content-Encoding: nonce\0'), 12);
  const chunks = [];
  for (let offset = 0, sequence = 0; offset < ciphertext.length; offset += recordSize, sequence++) {
    const record = await aesGcmDecrypt(key, recordNonce(nonce, sequence), ciphertext.slice(offset, offset + recordSize));
    let end = record.length - 1;
    while (end >= 0 && record[end] === 0) {
      end--;
    }
    chunks.push(record.slice(0, Math.max(end, 0)));
  }
  return concat(...chunks);
}

async function decryptAesgcm(body, headers, route) {
  const salt = base64urlDecode(headerParameter(headers.get('encryption'), 'salt'));
  const senderKey = base64urlDecode(headerParameter(headers.get('crypto-key'), 'dh'));
  const ecdh = await sharedSecret(route, senderKey);
  const prk = await hkdfExpand(await hmac(route.auth, ecdh), encoder.encode('Content-Encoding: auth\0'), 32);
  const context = concat(encoder.encode('P-256\0'), uint16(route.publicKey.length), route.publicKey, uint16(senderKey.length), senderKey);
  const saltedPrk = await hmac(salt, prk);
  const key = await hkdfExpand(saltedPrk, concat(encoder.encode('Content-Encoding: aesgcm\0'), context), 16);
  const nonce = await hkdfExpand(saltedPrk, concat(encoder.encode('Content-Encoding: nonce\0'), context), 12);
  const record = await aesGcmDecrypt(key, nonce, body);
  const padding = (record[0] << 8) | record[1];
  return record.slice(2 + padding);
}

async function sharedSecret(route, senderKey) {
  const jwk = {
    kty: 'EC', crv: 'P-256', ext: true,
    d: base64urlEncode(route.d),
    x: base64urlEncode(route.publicKey.slice(1, 33)),
    y: base64urlEncode(route.publicKey.slice(33, 65)),
  };
  const privateKey = await crypto.subtle.importKey('jwk', jwk, { name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits']);
  const publicKey = await crypto.subtle.importKey('raw', senderKey, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  return new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: publicKey }, privateKey, 256));
}

async function hmac(key, data) {
  const hmacKey = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', hmacKey, data));
}

async function hkdfExpand(prk, info, length) {
  return (await hmac(prk, concat(info, new Uint8Array([1])))).slice(0, length);
}

async function aesGcmDecrypt(key, nonce, data) {
  const aesKey = await crypto.subtle.importKey('raw', key, { name: 'AES-GCM' }, false, ['decrypt']);
  return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aesKey, data));
}

function recordNonce(nonce, sequence) {
  const result = nonce.slice();
  for (let i = 0; i < 6; i++) {
    result[11 - i] ^= Math.floor(sequence / 2 ** (8 * i)) & 0xff;
  }
  return result;
}

function headerParameter(header, name) {
  for (const part of (header || '').split(/[;,]/)) {
    const [key, value] = part.trim().split('=');
    if (key === name && value) {
      return value.replace(/"/g, '');
    }
  }
  throw new Error('missing ' + name);
}

function uint16(value) {
  return new Uint8Array([value >> 8, value & 0xff]);
}

function concat(...parts) {
  const result = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

export function base64urlDecode(text) {
  const base64 = text.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(text.length / 4) * 4, '=');
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

export function base64urlEncode(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
