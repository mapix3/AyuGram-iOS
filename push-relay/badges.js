import { statsStub } from './stats.js';

export const BADGE_SYMBOLS = ['sparkles', 'star.fill', 'heart.fill', 'flame.fill', 'bolt.fill', 'crown.fill', 'moon.stars.fill', 'sun.max.fill', 'leaf.fill', 'pawprint.fill', 'gamecontroller.fill', 'music.note', 'airplane', 'eye.fill', 'theatermasks.fill', 'wand.and.stars', 'diamond.fill', 'shield.fill', 'checkmark.seal.fill', 'hare.fill', 'tortoise.fill', 'ant.fill', 'ladybug.fill', 'fish.fill', 'snowflake', 'drop.fill', 'cloud.fill', 'atom', 'infinity', 'hand.peace.fill'];

const DEFAULT_PAY = 'https://t.me/send?start=IVM3XypxxOuG';
const REQUESTS_PER_DAY = 3;

export function cleanBadge(value) {
  const input = value && typeof value === 'object' ? value : {};
  const hex = (text, fallback) => (typeof text === 'string' && /^[0-9a-fA-F]{6}$/.test(text) ? text.toUpperCase() : fallback);
  const emoji = typeof input.emoji === 'string' ? [...input.emoji.replace(/[\u0000-\u001f\u007f<>&"']/g, '').trim()].slice(0, 4).join('') : '';
  return {
    symbol: BADGE_SYMBOLS.includes(input.symbol) ? input.symbol : 'sparkles',
    emoji: /^[\x20-\x7e]*$/.test(emoji) ? '' : emoji,
    shape: [0, 1, 2, 3].includes(input.shape) ? input.shape : 0,
    top: hex(input.top, '8E61F2'),
    bottom: hex(input.bottom, 'C9B3FF'),
    darkGlyph: input.darkGlyph === true,
  };
}

function accountId(value) {
  const text = typeof value === 'number' ? String(value) : typeof value === 'string' ? value : '';
  return /^[1-9][0-9]{0,15}$/.test(text) ? text : '';
}

async function lockOf(secret) {
  if (typeof secret !== 'string' || !/^[A-Za-z0-9_-]{24,80}$/.test(secret)) {
    return '';
  }
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('ayugram-badge|' + secret));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function body(request) {
  try {
    const raw = await request.text();
    return raw.length > 2048 ? null : JSON.parse(raw);
  } catch (error) {
    return null;
  }
}

function json(value, status) {
  return new Response(JSON.stringify(value), { status: status || 200, headers: { 'content-type': 'application/json; charset=utf-8' } });
}

async function notifyOwner(env, text, markup) {
  if (!env || !env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
    return;
  }
  await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/sendMessage', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ chat_id: env.REPORT_CHAT_ID, text, reply_markup: markup }),
  }).catch(() => null);
}

export async function handleBadges(request, env, url, ctx) {
  const stub = statsStub(env);
  if (!stub) {
    return json({ error: 'unavailable' }, 503);
  }
  const call = (path, payload) => stub.fetch('https://stats.ayugram.invalid' + path, { method: payload ? 'POST' : 'GET', body: payload ? JSON.stringify(payload) : undefined });
  if (request.method === 'GET' && url.pathname === '/badges') {
    const response = await call('/badge-list');
    const data = response.ok ? await response.json() : { items: [] };
    return new Response(JSON.stringify({ pay: env.BADGE_PAY_URL || DEFAULT_PAY, price: env.BADGE_PRICE || '3', items: data.items }), { headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'public, max-age=120' } });
  }
  if (request.method !== 'POST') {
    return json({ error: 'not found' }, 404);
  }
  const input = await body(request);
  const id = accountId(input && input.id);
  const lock = await lockOf(input && input.secret);
  if (!id || !lock) {
    return json({ error: 'bad request' }, 400);
  }
  if (url.pathname === '/badges/status') {
    return call('/badge-status', { id, lock });
  }
  if (url.pathname === '/badges/request') {
    const name = typeof input.name === 'string' ? input.name.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 64) : '';
    const response = await call('/badge-request', { id, lock, name, limit: REQUESTS_PER_DAY });
    const result = await response.json().catch(() => ({}));
    if (response.ok && result.fresh) {
      const notice = notifyOwner(env, '💎 Запрос бейджа поддержки\nID ' + id + (name ? ' · ' + name : '') + '\nКод: ' + result.code + '\nПроверь оплату с этим кодом и выдай бейдж.', { inline_keyboard: [[{ text: '✅ Выдать', callback_data: 'G:' + result.code }, { text: '❌ Отклонить', callback_data: 'D:' + result.code }]] });
      if (ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil(notice);
      } else {
        await notice;
      }
    }
    return json({ code: result.code || '', granted: result.granted === true, error: result.error }, response.status);
  }
  if (url.pathname === '/badges/set') {
    return call('/badge-set', { id, lock, badge: cleanBadge(input.badge) });
  }
  return json({ error: 'not found' }, 404);
}

export async function badgeStorage(storage, request, url, now) {
  if (request.method === 'GET' && url.pathname === '/badge-list') {
    const items = [];
    for (const [key, value] of await storage.list({ prefix: 'sup:' })) {
      items.push({ id: key.slice(4), b: value.badge });
    }
    return Response.json({ items });
  }
  if (request.method !== 'POST' || !url.pathname.startsWith('/badge-')) {
    return null;
  }
  if (url.pathname.startsWith('/badge-grant/') || url.pathname.startsWith('/badge-deny/')) {
    const code = url.pathname.split('/')[2];
    const pending = /^[A-Z0-9]{6}$/.test(code || '') ? await storage.get('breq:' + code) : null;
    if (!pending) {
      return new Response('not found\n', { status: 404 });
    }
    await storage.delete('breq:' + code);
    await storage.delete('bpend:' + pending.id);
    if (url.pathname.startsWith('/badge-grant/')) {
      const existing = await storage.get('sup:' + pending.id);
      await storage.put('sup:' + pending.id, { lock: pending.lock, time: now, badge: existing ? existing.badge : cleanBadge(null) });
    }
    return Response.json({ id: pending.id, name: pending.name || '' });
  }
  if (url.pathname.startsWith('/badge-grant-id/') || url.pathname.startsWith('/badge-revoke/')) {
    const id = accountId(url.pathname.split('/')[2]);
    if (!id) {
      return new Response('bad request\n', { status: 400 });
    }
    if (url.pathname.startsWith('/badge-revoke/')) {
      const existed = Boolean(await storage.get('sup:' + id));
      await storage.delete('sup:' + id);
      return Response.json({ id, existed });
    }
    const existing = await storage.get('sup:' + id);
    const pendingCode = await storage.get('bpend:' + id);
    const pending = pendingCode ? await storage.get('breq:' + pendingCode) : null;
    await storage.put('sup:' + id, { lock: pending ? pending.lock : (existing ? existing.lock : ''), time: now, badge: existing ? existing.badge : cleanBadge(null) });
    if (pendingCode) {
      await storage.delete('breq:' + pendingCode);
      await storage.delete('bpend:' + id);
    }
    return Response.json({ id, existed: Boolean(existing) });
  }
  const input = await request.json();
  const supporter = await storage.get('sup:' + input.id);
  if (url.pathname === '/badge-status') {
    if (supporter && (supporter.lock === input.lock || !supporter.lock)) {
      return Response.json({ granted: true, badge: supporter.badge });
    }
    const code = await storage.get('bpend:' + input.id);
    const pending = code ? await storage.get('breq:' + code) : null;
    return Response.json({ granted: false, code: pending && pending.lock === input.lock ? code : '', taken: Boolean(supporter) });
  }
  if (url.pathname === '/badge-request') {
    if (supporter && (supporter.lock === input.lock || !supporter.lock)) {
      return Response.json({ granted: true, code: '' });
    }
    const existingCode = await storage.get('bpend:' + input.id);
    const existing = existingCode ? await storage.get('breq:' + existingCode) : null;
    if (existing && existing.lock === input.lock) {
      return Response.json({ code: existingCode, fresh: false });
    }
    const day = Math.floor(now / 86400000);
    const limitKey = 'blim:' + input.id + ':' + day;
    const count = (await storage.get(limitKey)) || 0;
    if (count >= input.limit) {
      return Response.json({ error: 'limit' }, { status: 429 });
    }
    await storage.put(limitKey, count + 1);
    if (existingCode) {
      await storage.delete('breq:' + existingCode);
    }
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const bytes = crypto.getRandomValues(new Uint8Array(6));
    const code = [...bytes].map((byte) => alphabet[byte % alphabet.length]).join('');
    await storage.put('breq:' + code, { id: input.id, lock: input.lock, name: input.name || '', time: now });
    await storage.put('bpend:' + input.id, code);
    return Response.json({ code, fresh: true });
  }
  if (url.pathname === '/badge-set') {
    if (!supporter) {
      return Response.json({ error: 'not granted' }, { status: 403 });
    }
    if (supporter.lock && supporter.lock !== input.lock) {
      return Response.json({ error: 'locked' }, { status: 403 });
    }
    await storage.put('sup:' + input.id, { lock: input.lock, time: supporter.time, badge: cleanBadge(input.badge) });
    return Response.json({ ok: true });
  }
  return new Response('not found\n', { status: 404 });
}
