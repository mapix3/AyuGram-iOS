import { sameToken, statsStub } from './stats.js';

export const BADGE_SYMBOLS = ['sparkles', 'star.fill', 'heart.fill', 'flame.fill', 'bolt.fill', 'crown.fill', 'moon.stars.fill', 'sun.max.fill', 'leaf.fill', 'pawprint.fill', 'gamecontroller.fill', 'music.note', 'airplane', 'eye.fill', 'theatermasks.fill', 'wand.and.stars', 'diamond.fill', 'shield.fill', 'checkmark.seal.fill', 'hare.fill', 'tortoise.fill', 'ant.fill', 'ladybug.fill', 'fish.fill', 'snowflake', 'drop.fill', 'cloud.fill', 'atom', 'infinity', 'hand.peace.fill'];

const DEFAULT_PAY = 'https://t.me/send?start=IVM3XypxxOuG';
const REQUESTS_PER_DAY = 3;
const TON_WALLET = 'UQCvj3aWiCCzawOO5OeRM9C3Ts5n4hc1tep1ZZ7aBYG33Glp';
const CHECK_EVERY = 8000;
const QUOTE_EVERY = 3600000;
const INVOICE_LIFE = 604800;
const PENDING_DAYS = 14;
let tonCache = { time: 0, address: '', list: null };
let rateCache = { time: 0, rate: 0 };

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

function priceOf(env) {
  const value = Number(env && env.BADGE_PRICE ? env.BADGE_PRICE : 3);
  return Number.isFinite(value) && value > 0 ? value : 3;
}

function walletOf(env) {
  return env && typeof env.BADGE_TON_WALLET === 'string' && /^[A-Za-z0-9_-]{48}$/.test(env.BADGE_TON_WALLET) ? env.BADGE_TON_WALLET : TON_WALLET;
}

function cryptoToken(env) {
  return env && env.CRYPTOPAY_TOKEN ? String(env.CRYPTOPAY_TOKEN).replace(/[\s"']/g, '') : '';
}

async function cryptoPay(env, method, params) {
  const token = cryptoToken(env);
  if (!token) {
    return null;
  }
  try {
    const response = await fetch((env.CRYPTOPAY_API || 'https://pay.crypt.bot/api/') + method, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'Crypto-Pay-API-Token': token },
      body: JSON.stringify(params || {}),
      signal: AbortSignal.timeout(10000),
    });
    const data = await response.json();
    return data && data.ok ? data.result : null;
  } catch (error) {
    return null;
  }
}

async function createInvoice(env, code) {
  const result = await cryptoPay(env, 'createInvoice', {
    currency_type: 'fiat',
    fiat: 'USD',
    amount: String(priceOf(env)),
    description: 'AyuGram iOS supporter badge · ' + code,
    payload: code,
    allow_comments: false,
    allow_anonymous: true,
    expires_in: INVOICE_LIFE,
  });
  const link = result && (result.bot_invoice_url || result.mini_app_invoice_url || result.pay_url);
  if (!result || !result.invoice_id || typeof link !== 'string' || !link.startsWith('https://')) {
    return null;
  }
  return { id: result.invoice_id, url: link, exp: Date.now() + INVOICE_LIFE * 1000 };
}

function rocketToken(env) {
  return env && env.XROCKET_TOKEN ? String(env.XROCKET_TOKEN).replace(/[\s"']/g, '') : '';
}

async function rocketPay(env, method, path, payload) {
  const token = rocketToken(env);
  if (!token) {
    return null;
  }
  try {
    const response = await fetch((env.XROCKET_API || 'https://pay.xrocket.tg') + path, {
      method,
      headers: { 'content-type': 'application/json', accept: 'application/json', 'Rocket-Pay-Key': token },
      body: payload ? JSON.stringify(payload) : undefined,
      signal: AbortSignal.timeout(10000),
    });
    const data = await response.json();
    return data && data.success !== false && data.data ? data.data : null;
  } catch (error) {
    return null;
  }
}

async function createRocketInvoice(env, code) {
  const result = await rocketPay(env, 'POST', '/tg-invoices', {
    amount: priceOf(env),
    numPayments: 1,
    currency: env.XROCKET_CURRENCY || 'USDT',
    description: 'AyuGram iOS supporter badge · ' + code,
    hiddenMessage: 'Thank you! Go back to AyuGram, the badge unlocks by itself.',
    payload: code,
    expiredIn: INVOICE_LIFE,
  });
  const link = result && result.link;
  if (!result || !result.id || typeof link !== 'string' || !link.startsWith('https://t.me/')) {
    return null;
  }
  return { id: result.id, url: link, exp: Date.now() + INVOICE_LIFE * 1000 };
}

function rocketResult(invoice, code, id) {
  if (!invoice || String(invoice.id) !== String(id) || (invoice.payload && invoice.payload !== code)) {
    return null;
  }
  const paid = invoice.status === 'paid' || Number(invoice.activatedCount || 0) >= 1 || (Array.isArray(invoice.payments) && invoice.payments.length > 0);
  if (paid) {
    return { key: 'xr:' + invoice.id, via: 'xRocket', amount: [invoice.amount, invoice.currency].filter(Boolean).join(' ') };
  }
  return invoice.status === 'expired' ? { expired: true, rocket: true } : null;
}

async function rocketCheck(env, code, pending) {
  if (!pending.rocket || !pending.rocket.id) {
    return null;
  }
  return rocketResult(await rocketPay(env, 'GET', '/tg-invoices/' + encodeURIComponent(pending.rocket.id)), code, pending.rocket.id);
}

async function tonRate(env) {
  if (rateCache.rate > 0 && Date.now() - rateCache.time < 600000) {
    return rateCache.rate;
  }
  let rate = 0;
  const rates = await cryptoPay(env, 'getExchangeRates');
  if (Array.isArray(rates)) {
    const item = rates.find((entry) => entry && entry.source === 'TON' && entry.target === 'USD' && entry.is_valid !== false);
    rate = item ? Number(item.rate) : 0;
  }
  if (!(rate > 0)) {
    try {
      const response = await fetch('https://api.coingecko.com/api/v3/simple/price?ids=the-open-network&vs_currencies=usd', { signal: AbortSignal.timeout(8000) });
      const data = await response.json();
      rate = Number(data && data['the-open-network'] && data['the-open-network'].usd);
    } catch (error) {
      rate = 0;
    }
  }
  if (rate > 0) {
    rateCache = { time: Date.now(), rate };
  }
  return rate > 0 ? rate : 0;
}

async function tonQuote(env) {
  const rate = await tonRate(env);
  if (!(rate > 0)) {
    return '';
  }
  const hundredths = Math.ceil((priceOf(env) / rate) * 100);
  return String(BigInt(hundredths) * 10000000n);
}

function tonText(nano) {
  const value = BigInt(nano);
  const whole = value / 1000000000n;
  const fraction = String(value % 1000000000n).padStart(9, '0').replace(/0+$/, '');
  return whole + (fraction ? '.' + fraction : '');
}

function messageText(message) {
  if (!message) {
    return '';
  }
  if (typeof message.message === 'string' && message.message) {
    return message.message;
  }
  const data = message.msg_data;
  if (data && data['@type'] === 'msg.dataText' && typeof data.text === 'string') {
    try {
      return new TextDecoder().decode(Uint8Array.from(atob(data.text), (char) => char.charCodeAt(0)));
    } catch (error) {
      return '';
    }
  }
  return '';
}

async function tonTransactions(env) {
  const address = walletOf(env);
  if (tonCache.list && tonCache.address === address && Date.now() - tonCache.time < 5000) {
    return tonCache.list;
  }
  try {
    const headers = env && env.TONCENTER_KEY ? { 'X-API-Key': String(env.TONCENTER_KEY).trim() } : {};
    const response = await fetch((env.TONCENTER_API || 'https://toncenter.com/api/v2/') + 'getTransactions?limit=60&archival=true&address=' + encodeURIComponent(address), { headers, signal: AbortSignal.timeout(10000) });
    const data = await response.json();
    if (!data || !data.ok || !Array.isArray(data.result)) {
      return [];
    }
    const list = data.result.map((item) => {
      const message = item && item.in_msg;
      if (!message || !message.source || !/^[0-9]+$/.test(String(message.value || ''))) {
        return null;
      }
      const id = item.transaction_id || {};
      return { key: 'ton:' + (id.hash || id.lt || ''), value: String(message.value), text: messageText(message).trim().toUpperCase(), time: Number(item.utime || 0) * 1000 };
    }).filter((item) => item && item.key.length > 4);
    tonCache = { time: Date.now(), address, list };
    return list;
  } catch (error) {
    return [];
  }
}

function tonMatches(list, code, pending) {
  if (!pending.ton || !pending.ton.min) {
    return [];
  }
  const floor = (BigInt(pending.ton.min) * 95n) / 100n;
  return list.filter((item) => item.text === code && BigInt(item.value) >= floor && item.time >= (pending.time || 0) - 120000).map((item) => ({ key: item.key, via: 'TON', amount: tonText(item.value) + ' TON' }));
}

function invoiceResult(invoice) {
  if (!invoice) {
    return null;
  }
  if (invoice.status === 'paid') {
    return { key: 'cp:' + invoice.invoice_id, via: 'Crypto Bot', amount: [invoice.paid_amount || invoice.amount, invoice.paid_asset || invoice.asset || invoice.fiat].filter(Boolean).join(' ') };
  }
  if (invoice.status === 'expired') {
    return { expired: true };
  }
  return null;
}

async function findPayments(env, code, pending) {
  const found = [];
  if (pending.invoice && pending.invoice.id) {
    const result = await cryptoPay(env, 'getInvoices', { invoice_ids: String(pending.invoice.id) });
    const items = result && Array.isArray(result.items) ? result.items : [];
    const outcome = invoiceResult(items.find((item) => item && String(item.invoice_id) === String(pending.invoice.id) && item.payload === code));
    if (outcome) {
      found.push(outcome);
    }
  }
  const rocket = await rocketCheck(env, code, pending);
  if (rocket) {
    found.push(rocket);
  }
  if (pending.ton) {
    found.push(...tonMatches(await tonTransactions(env), code, pending));
  }
  return found;
}

async function grantFirst(env, call, code, payments) {
  for (const paid of payments) {
    if (paid && paid.key) {
      const granted = await grantPaid(env, call, code, paid);
      if (granted) {
        return granted;
      }
    }
  }
  return null;
}

function payView(env, code, pending) {
  const view = { cryptobot: pending.invoice && pending.invoice.url ? pending.invoice.url : '', xrocket: pending.rocket && pending.rocket.url ? pending.rocket.url : '' };
  if (pending.ton && pending.ton.nano) {
    const address = walletOf(env);
    const query = '?amount=' + pending.ton.nano + '&text=' + encodeURIComponent(code);
    view.ton = { address, nano: pending.ton.nano, amount: tonText(pending.ton.nano), comment: code, url: 'ton://transfer/' + address + query, open: 'https://app.tonkeeper.com/transfer/' + address + query };
  }
  return view;
}

async function grantPaid(env, call, code, paid) {
  const response = await call('/badge-paid/' + code, { key: paid.key });
  if (!response.ok) {
    return null;
  }
  const result = await response.json();
  await notifyOwner(env, '💎 Бейдж выдан автоматически\nID ' + result.id + (result.name ? ' · ' + result.name : '') + '\nОплата: ' + paid.via + (paid.amount ? ' · ' + paid.amount : '') + '\nКод: ' + code, { inline_keyboard: [[{ text: 'Забрать бейдж', callback_data: 'R:' + result.id }]] });
  return result;
}

async function settle(env, call, status) {
  const code = status.code;
  const pending = status.pending || {};
  const now = Date.now();
  const update = {};
  if (!pending.checked || now - pending.checked > CHECK_EVERY) {
    update.checked = now;
    const payments = await findPayments(env, code, pending);
    const granted = await grantFirst(env, call, code, payments);
    if (granted) {
      return { granted: true, badge: granted.badge };
    }
    if (payments.some((paid) => paid.expired && !paid.rocket)) {
      pending.invoice = null;
      update.invoice = null;
    }
    if (payments.some((paid) => paid.expired && paid.rocket)) {
      pending.rocket = null;
      update.rocket = null;
    }
  }
  if (cryptoToken(env) && (!pending.invoice || !pending.invoice.exp || pending.invoice.exp < now + 86400000)) {
    const invoice = await createInvoice(env, code);
    if (invoice) {
      update.invoice = invoice;
    }
  }
  if (rocketToken(env) && (!pending.rocket || !pending.rocket.exp || pending.rocket.exp < now + 86400000)) {
    const rocket = await createRocketInvoice(env, code);
    if (rocket) {
      update.rocket = rocket;
    }
  }
  if (!pending.ton || !pending.ton.time || now - pending.ton.time > QUOTE_EVERY) {
    const nano = await tonQuote(env);
    if (nano) {
      const min = pending.ton && pending.ton.min && BigInt(pending.ton.min) < BigInt(nano) ? pending.ton.min : nano;
      update.ton = { nano, min, time: now };
    }
  }
  await call('/badge-pay/' + code, update);
  return { granted: false, code, pay: payView(env, code, Object.assign({}, pending, update)) };
}

async function signatureValid(env, raw, signature) {
  const token = cryptoToken(env);
  if (!token || typeof signature !== 'string' || !/^[0-9a-fA-F]{64}$/.test(signature)) {
    return false;
  }
  const secret = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const key = await crypto.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
  const bytes = new Uint8Array(signature.match(/../g).map((pair) => parseInt(pair, 16)));
  return crypto.subtle.verify('HMAC', key, bytes, new TextEncoder().encode(raw));
}

function badgeCall(stub) {
  return (path, payload) => stub.fetch('https://stats.ayugram.invalid' + path, { method: payload ? 'POST' : 'GET', body: payload ? JSON.stringify(payload) : undefined });
}

export async function handleCryptoPayHook(request, env) {
  if (request.method !== 'POST') {
    return new Response('not found\n', { status: 404 });
  }
  const raw = await request.text();
  if (raw.length > 16384 || !(await signatureValid(env, raw, request.headers.get('crypto-pay-api-signature')))) {
    return new Response('forbidden\n', { status: 403 });
  }
  let update = null;
  try {
    update = JSON.parse(raw);
  } catch (error) {
    return new Response('bad request\n', { status: 400 });
  }
  const invoice = update && update.update_type === 'invoice_paid' ? update.payload : null;
  const code = invoice && typeof invoice.payload === 'string' ? invoice.payload : '';
  const stub = statsStub(env);
  if (!stub || !/^[A-Z0-9]{6}$/.test(code)) {
    return new Response('ok\n');
  }
  const call = badgeCall(stub);
  const response = await call('/badge-pending-get/' + code);
  const pending = response.ok ? await response.json() : null;
  const paid = invoiceResult(invoice);
  if (pending && pending.invoice && String(pending.invoice.id) === String(invoice.invoice_id) && paid && paid.key) {
    await grantPaid(env, call, code, paid);
  }
  return new Response('ok\n');
}

function findCode(value, depth) {
  if (!value || typeof value !== 'object' || depth > 3) {
    return null;
  }
  if (typeof value.payload === 'string' && /^[A-Z0-9]{6}$/.test(value.payload) && (value.id || value.invoiceId)) {
    return { code: value.payload, id: value.invoiceId || value.id };
  }
  for (const child of Object.values(value)) {
    const found = findCode(child, depth + 1);
    if (found) {
      return found;
    }
  }
  return null;
}

async function rocketSignatureValid(env, raw, request) {
  const secret = env && env.XROCKET_WEBHOOK_TOKEN ? String(env.XROCKET_WEBHOOK_TOKEN).replace(/[\s"']/g, '') : '';
  if (!secret) {
    return true;
  }
  const given = ['rocket-pay-signature', 'x-rocket-pay-signature', 'x-signature', 'signature'].map((name) => request.headers.get(name)).find((value) => typeof value === 'string' && value.length > 0);
  if (!given) {
    return false;
  }
  const signature = given.trim().replace(/^sha256=/i, '').toLowerCase();
  const body = new TextEncoder().encode(raw);
  const keys = [new TextEncoder().encode(secret), new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(secret)))];
  for (const material of keys) {
    const key = await crypto.subtle.importKey('raw', material, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const bytes = new Uint8Array(await crypto.subtle.sign('HMAC', key, body));
    const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
    const base64 = btoa(String.fromCharCode(...bytes));
    if (signature === hex || given.trim() === base64) {
      return true;
    }
  }
  return false;
}

export async function handleRocketHook(request, env) {
  if (request.method !== 'POST') {
    return new Response('not found\n', { status: 404 });
  }
  const raw = await request.text();
  if (raw.length > 16384 || !(await rocketSignatureValid(env, raw, request))) {
    console.log('xrocket webhook signature mismatch');
    return new Response('forbidden\n', { status: 403 });
  }
  let update = null;
  try {
    update = raw.length > 16384 ? null : JSON.parse(raw);
  } catch (error) {
    update = null;
  }
  const found = findCode(update, 0);
  const stub = statsStub(env);
  if (!found || !stub || !rocketToken(env)) {
    return new Response('ok\n');
  }
  const call = badgeCall(stub);
  const response = await call('/badge-pending-get/' + found.code);
  const pending = response.ok ? await response.json() : null;
  if (pending && pending.rocket && String(pending.rocket.id) === String(found.id)) {
    const paid = await rocketCheck(env, found.code, pending);
    if (paid && paid.key) {
      await grantPaid(env, call, found.code, paid);
    }
  }
  return new Response('ok\n');
}

export async function checkBadgePayments(env) {
  const stub = statsStub(env);
  if (!stub) {
    return 0;
  }
  const call = badgeCall(stub);
  const response = await call('/badge-pending-list');
  const items = response.ok ? (await response.json()).items || [] : [];
  if (!items.length) {
    return 0;
  }
  const invoices = new Map();
  if (cryptoToken(env) && items.some((item) => item.invoice && item.invoice.id)) {
    const result = await cryptoPay(env, 'getInvoices', { status: 'paid', count: 1000 });
    for (const invoice of result && Array.isArray(result.items) ? result.items : []) {
      invoices.set(String(invoice.invoice_id), invoice);
    }
  }
  const list = items.some((item) => item.ton) ? await tonTransactions(env) : [];
  let granted = 0;
  let rocketChecks = 0;
  for (const item of items.slice().reverse()) {
    const invoice = item.invoice ? invoices.get(String(item.invoice.id)) : null;
    const payments = [invoice && invoice.payload === item.code ? invoiceResult(invoice) : null, ...tonMatches(list, item.code, item)];
    if (!payments.some((paid) => paid && paid.key) && item.rocket && rocketToken(env) && rocketChecks < 20) {
      rocketChecks += 1;
      payments.push(await rocketCheck(env, item.code, item));
    }
    if (await grantFirst(env, call, item.code, payments)) {
      granted += 1;
    }
  }
  return granted;
}

export async function paymentHealth(env) {
  const result = { cryptobot: { configured: Boolean(cryptoToken(env)), ok: false, app: '' }, xrocket: { configured: Boolean(rocketToken(env)), webhookToken: Boolean(env && env.XROCKET_WEBHOOK_TOKEN), ok: false, app: '' }, ton: { wallet: walletOf(env), keyed: Boolean(env && env.TONCENTER_KEY), ok: false, rate: 0, quote: '' }, pending: 0, price: priceOf(env) };
  if (result.cryptobot.configured) {
    const me = await cryptoPay(env, 'getMe');
    result.cryptobot.ok = Boolean(me && me.app_id);
    result.cryptobot.app = me && typeof me.name === 'string' ? me.name.slice(0, 64) : '';
  }
  if (result.xrocket.configured) {
    const info = await rocketPay(env, 'GET', '/app/info');
    result.xrocket.ok = Boolean(info);
    result.xrocket.app = info && typeof info.name === 'string' ? info.name.slice(0, 64) : '';
  }
  rateCache = { time: 0, rate: 0 };
  tonCache = { time: 0, address: '', list: null };
  result.ton.rate = await tonRate(env);
  const nano = result.ton.rate > 0 ? await tonQuote(env) : '';
  result.ton.quote = nano ? tonText(nano) : '';
  try {
    const headers = env && env.TONCENTER_KEY ? { 'X-API-Key': String(env.TONCENTER_KEY).trim() } : {};
    const response = await fetch((env.TONCENTER_API || 'https://toncenter.com/api/v2/') + 'getTransactions?limit=1&address=' + encodeURIComponent(walletOf(env)), { headers, signal: AbortSignal.timeout(10000) });
    const data = await response.json();
    result.ton.ok = Boolean(data && data.ok && Array.isArray(data.result));
  } catch (error) {
    result.ton.ok = false;
  }
  const stub = statsStub(env);
  if (stub) {
    const response = await badgeCall(stub)('/badge-pending-list');
    result.pending = response.ok ? ((await response.json()).items || []).length : 0;
  }
  return result;
}

export function paymentHealthText(health) {
  const mark = (ok, configured) => (!configured ? '⚪️ не настроен' : ok ? '✅ работает' : '❌ токен не принят');
  return [
    '💳 Проверка оплаты бейджей ($' + health.price + ')',
    'Crypto Bot: ' + mark(health.cryptobot.ok, health.cryptobot.configured) + (health.cryptobot.app ? ' · ' + health.cryptobot.app : ''),
    'xRocket: ' + mark(health.xrocket.ok, health.xrocket.configured) + (health.xrocket.app ? ' · ' + health.xrocket.app : '') + (health.xrocket.configured ? (health.xrocket.webhookToken ? ' · токен вебхука есть' : ' · без токена вебхука') : ''),
    'TON: ' + (health.ton.ok ? '✅ toncenter отвечает' : '❌ toncenter не ответил') + (health.ton.rate ? ' · курс $' + health.ton.rate + ' · к оплате ' + health.ton.quote + ' TON' : ' · курс не получен') + (health.ton.keyed ? ' · с ключом' : ' · без ключа'),
    'Ожидают оплаты: ' + health.pending,
  ].join('\n');
}

export async function handleBadges(request, env, url, ctx) {
  const stub = statsStub(env);
  if (!stub) {
    return json({ error: 'unavailable' }, 503);
  }
  const call = badgeCall(stub);
  if (request.method === 'GET' && url.pathname === '/badges') {
    const response = await call('/badge-list');
    const data = response.ok ? await response.json() : { items: [] };
    return new Response(JSON.stringify({ pay: env.BADGE_PAY_URL || DEFAULT_PAY, price: env.BADGE_PRICE || '3', items: data.items }), { headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'public, max-age=120' } });
  }
  if (request.method === 'GET' && url.pathname === '/badges/health') {
    const header = request.headers.get('authorization') || '';
    if (!sameToken(header.startsWith('Bearer ') ? header.slice(7) : '', env.STATS_TOKEN)) {
      return json({ error: 'forbidden' }, 403);
    }
    return json(await paymentHealth(env));
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
  const status = async () => {
    const response = await call('/badge-status', { id, lock });
    if (!response.ok) {
      return json({ error: 'unavailable' }, 503);
    }
    const result = await response.json();
    if (result.granted || !result.code) {
      return json({ granted: result.granted === true, badge: result.badge, code: '', taken: result.taken === true });
    }
    return json(await settle(env, call, result));
  };
  if (url.pathname === '/badges/status') {
    return status();
  }
  if (url.pathname === '/badges/request') {
    const name = typeof input.name === 'string' ? input.name.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 64) : '';
    const response = await call('/badge-request', { id, lock, name, limit: REQUESTS_PER_DAY });
    const result = await response.json().catch(() => ({}));
    if (response.ok && result.fresh) {
      const notice = notifyOwner(env, '💎 Запрос бейджа поддержки\nID ' + id + (name ? ' · ' + name : '') + '\nКод: ' + result.code + '\nCrypto Bot, xRocket и TON проверятся сами. Если оплатили иначе, проверь код в комментарии и выдай вручную.', { inline_keyboard: [[{ text: '✅ Выдать', callback_data: 'G:' + result.code }, { text: '❌ Отклонить', callback_data: 'D:' + result.code }]] });
      if (ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil(notice);
      } else {
        await notice;
      }
    }
    if (!response.ok || !result.code) {
      return json({ code: '', granted: result.granted === true, error: result.error }, response.status);
    }
    return status();
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
  if (request.method === 'GET' && url.pathname === '/badge-pending-list') {
    const items = [];
    for (const [key, value] of await storage.list({ prefix: 'breq:' })) {
      if (now - (value.time || 0) < PENDING_DAYS * 86400000 && (value.invoice || value.rocket || value.ton)) {
        items.push({ code: key.slice(5), time: value.time, invoice: value.invoice || null, rocket: value.rocket || null, ton: value.ton || null });
      }
    }
    return Response.json({ items: items.slice(-200) });
  }
  if (request.method === 'GET' && url.pathname.startsWith('/badge-pending-get/')) {
    const code = url.pathname.split('/')[2];
    const pending = /^[A-Z0-9]{6}$/.test(code || '') ? await storage.get('breq:' + code) : null;
    return pending ? Response.json({ time: pending.time, invoice: pending.invoice || null, rocket: pending.rocket || null, ton: pending.ton || null }) : new Response('not found\n', { status: 404 });
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
  if (url.pathname.startsWith('/badge-pay/') || url.pathname.startsWith('/badge-paid/')) {
    const code = url.pathname.split('/')[2];
    const pending = /^[A-Z0-9]{6}$/.test(code || '') ? await storage.get('breq:' + code) : null;
    const input = await request.json().catch(() => ({}));
    if (!pending) {
      return new Response('not found\n', { status: 404 });
    }
    if (url.pathname.startsWith('/badge-pay/')) {
      for (const field of ['checked', 'invoice', 'rocket', 'ton']) {
        if (field in input) {
          pending[field] = input[field];
        }
      }
      await storage.put('breq:' + code, pending);
      return Response.json({ ok: true });
    }
    if (typeof input.key !== 'string' || input.key.length < 4 || input.key.length > 120 || (await storage.get('btx:' + input.key))) {
      return new Response('used\n', { status: 409 });
    }
    await storage.put('btx:' + input.key, { code, id: pending.id, time: now });
    await storage.delete('breq:' + code);
    await storage.delete('bpend:' + pending.id);
    const existing = await storage.get('sup:' + pending.id);
    const badge = existing ? existing.badge : cleanBadge(null);
    await storage.put('sup:' + pending.id, { lock: pending.lock, time: now, badge });
    return Response.json({ id: pending.id, name: pending.name || '', badge });
  }
  const input = await request.json();
  const supporter = await storage.get('sup:' + input.id);
  if (url.pathname === '/badge-status') {
    if (supporter && (supporter.lock === input.lock || !supporter.lock)) {
      return Response.json({ granted: true, badge: supporter.badge });
    }
    const code = await storage.get('bpend:' + input.id);
    const pending = code ? await storage.get('breq:' + code) : null;
    const mine = pending && pending.lock === input.lock;
    return Response.json({ granted: false, code: mine ? code : '', pending: mine ? { time: pending.time, checked: pending.checked || 0, invoice: pending.invoice || null, rocket: pending.rocket || null, ton: pending.ton || null } : null, taken: Boolean(supporter) });
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
