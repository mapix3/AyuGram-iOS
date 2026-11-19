// node push-relay/test.mjs — encrypts Web Push payloads like a push service and checks the relay.
import assert from 'node:assert/strict';
import { webcrypto as crypto, createHash } from 'node:crypto';
import { accountHash } from './stats.js';
import { checkBadgePayments, lockOf } from './badges.js';
import { cleanNfts, cleanUsernames, inspectMedia, network } from './profile.js';
import worker, { Profiles, base64urlEncode, describe, sendToBark, chatTarget, seenUpdate, alreadySeen, Presence, activityId, Stats, stashRecord } from './worker.js';

const cacheStore = new Map();
globalThis.caches = { default: {
  async match(request) { const hit = cacheStore.get(request.url); return hit ? new Response(hit.body.slice(0), { headers: hit.headers }) : undefined; },
  async put(request, response) { cacheStore.set(request.url, { body: await response.arrayBuffer(), headers: [...response.headers] }); },
  async delete(request) { return cacheStore.delete(request.url); },
} };
const env = { NOTIFY_DELAY_MS: '0' };

const enc = new TextEncoder();
const concat = (...p) => { const r = new Uint8Array(p.reduce((s, x) => s + x.length, 0)); let o = 0; for (const x of p) { r.set(x, o); o += x.length; } return r; };
const hmac = async (k, d) => new Uint8Array(await crypto.subtle.sign('HMAC', await crypto.subtle.importKey('raw', k, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']), d));
const expand = async (prk, info, n) => (await hmac(prk, concat(info, new Uint8Array([1])))).slice(0, n);
const u16 = (v) => new Uint8Array([v >> 8, v & 255]);

async function subscription(barkKey) {
  const ua = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const jwk = await crypto.subtle.exportKey('jwk', ua.privateKey);
  const pub = new Uint8Array(await crypto.subtle.exportKey('raw', ua.publicKey));
  const d = Uint8Array.from(Buffer.from(jwk.d, 'base64url'));
  const auth = crypto.getRandomValues(new Uint8Array(16));
  return { pub, auth, token: base64urlEncode(concat(d, pub, auth, enc.encode(barkKey))) };
}

async function senderSecret(sub) {
  const as = await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
  const asPub = new Uint8Array(await crypto.subtle.exportKey('raw', as.publicKey));
  const uaKey = await crypto.subtle.importKey('raw', sub.pub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey }, as.privateKey, 256));
  return { asPub, ecdh };
}

async function aesgcm(key, iv, data) {
  return new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await crypto.subtle.importKey('raw', key, 'AES-GCM', false, ['encrypt']), data));
}

async function encryptAes128gcm(sub, text) {
  const { asPub, ecdh } = await senderSecret(sub);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const ikm = await expand(await hmac(sub.auth, ecdh), concat(enc.encode('WebPush: info\0'), sub.pub, asPub), 32);
  const prk = await hmac(salt, ikm);
  const cek = await expand(prk, enc.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await expand(prk, enc.encode('Content-Encoding: nonce\0'), 12);
  const ct = await aesgcm(cek, nonce, concat(enc.encode(text), new Uint8Array([2, 0, 0])));
  return { body: concat(salt, new Uint8Array([0, 0, 16, 0]), new Uint8Array([65]), asPub, ct), headers: { 'content-encoding': 'aes128gcm' } };
}

async function encryptAesgcm(sub, text) {
  const { asPub, ecdh } = await senderSecret(sub);
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await expand(await hmac(sub.auth, ecdh), enc.encode('Content-Encoding: auth\0'), 32);
  const ctx = concat(enc.encode('P-256\0'), u16(65), sub.pub, u16(65), asPub);
  const sp = await hmac(salt, prk);
  const cek = await expand(sp, concat(enc.encode('Content-Encoding: aesgcm\0'), ctx), 16);
  const nonce = await expand(sp, concat(enc.encode('Content-Encoding: nonce\0'), ctx), 12);
  const ct = await aesgcm(cek, nonce, concat(u16(3), new Uint8Array(3), enc.encode(text)));
  return { body: ct, headers: { 'content-encoding': 'aesgcm', encryption: 'salt=' + base64urlEncode(salt), 'crypto-key': 'dh=' + base64urlEncode(asPub) } };
}

const sent = [];
let refuseJson = false;
globalThis.fetch = async (url, init) => {
  if (init && init.body) {
    sent.push({ url, body: JSON.parse(init.body) });
    return refuseJson ? new Response('{"code":400,"message":"failed to get device token"}', { status: 400 }) : new Response('{}');
  }
  sent.push({ url });
  return new Response('{"code":200}');
};

for (const encrypt of [encryptAes128gcm, encryptAesgcm]) {
  sent.length = 0;
  const sub = await subscription('BARKKEY123');
  const payload = JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Alice', 'привет'], custom: { msg_id: '5', from_id: '7' } });
  const { body, headers } = await encrypt(sub, payload);
  const response = await worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body, headers }), env);
  assert.equal(response.status, 201);
  assert.equal(sent.length, 1, encrypt.name);
  assert.equal(sent[0].body.device_key, 'BARKKEY123');
  assert.equal(sent[0].body.title, 'Alice');
  assert.equal(sent[0].body.body, 'привет');
  assert.equal(sent[0].body.url, 'ayugram://chat?user=7&msg=5', 'A tap opens the message itself');
  assert.equal(sent[0].body.ttl, 86400, 'Bark deletes relayed notifications after a day');
  assert.equal(sent[0].body.id, 'user7m5', 'The same message from two sessions replaces one notification');
}
assert.deepEqual(describe({ title: 'Bob', description: 'hi' }), { title: 'Bob', text: 'hi' });
assert.deepEqual(describe({}), { title: 'AyuGram', text: 'New message' });
assert.deepEqual(describe({ loc_key: 'CHAT_MESSAGE_TEXT', loc_args: ['Alice', 'Friends', 'hi all'] }), { title: 'Friends', text: 'Alice: hi all' });
const target = chatTarget({ from_id: '7' }, 'даша');
assert.equal(target.link, 'ayugram://chat?user=7');
assert.ok(target.icon.startsWith('https://ui-avatars.com/api/?name=%D0%94&') && target.icon.includes('background=e17076'), target.icon);
assert.equal(chatTarget({ chat_id: '12', from_id: '7' }, 'Team').link, 'ayugram://chat?chat=12');
assert.equal(chatTarget({ channel_id: '99' }, 'News').link, 'ayugram://chat?channel=99');
assert.deepEqual(chatTarget(undefined, 'x'), {});
assert.equal(chatTarget({ channel_id: '99', msg_id: '42' }, 'News').id, 'channel99m42');
assert.equal(chatTarget({ channel_id: '99', msg_id: '42' }, 'News').link, 'ayugram://chat?channel=99&msg=42');
assert.equal(chatTarget({ chat_id: '12', from_id: '7' }, 'Team').group, 'Team');
assert.equal(chatTarget({ chat_id: '12' }, ' ').group, 'chat12');
assert.equal(chatTarget({ from_id: '7' }, 'x').id, undefined);
assert.deepEqual(describe({ loc_key: 'CHANNEL_MESSAGE_PHOTO', loc_args: ['News'] }), { title: 'News', text: '📷 Photo' });
assert.deepEqual(describe({ loc_key: 'MESSAGE_AUDIO', loc_args: ['Bob'] }), { title: 'Bob', text: '🎤 Voice message' });
assert.deepEqual(describe({ loc_key: 'MESSAGE_STICKER', loc_args: ['Bob', '😀'] }), { title: 'Bob', text: '😀 Sticker' });
assert.deepEqual(describe({ loc_key: 'CHAT_MESSAGE_POLL', loc_args: ['Bob', 'Team', 'Lunch?'] }), { title: 'Team', text: 'Bob: 📊 Poll: Lunch?' });
assert.deepEqual(describe({ loc_key: 'PINNED_TEXT', loc_args: ['Bob', 'rules'] }), { title: 'Bob', text: '📌 rules' });
assert.equal(describe({ loc_key: 'READ_HISTORY', loc_args: [] }), null);
assert.equal(describe({ loc_key: '', custom: {} }), null);
assert.equal(describe({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'нет'], custom: { from_id: '7', msg_id: '9', schedule: 1 } }), null);
assert.equal(describe({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'нет'], custom: { from_id: '7', msg_id: '9', schedule: '1' } }), null);
assert.equal(describe({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'да'], custom: { from_id: '7', msg_id: '9', schedule: 0 } }).text, 'да');
sent.length = 0;
refuseJson = true;
const fallback = await sendToBark('KEY1234567', 'Ann', 'hi / there');
assert.ok(fallback.ok, 'The path API is tried when the JSON API refuses');
assert.equal(sent.length, 2);
assert.ok(sent[1].url.startsWith('https://api.day.app/KEY1234567/Ann/hi%20%2F%20there?'), sent[1].url);
sent.length = 0;
await sendToBark('KEY1234567', 'Ann', 'hi', { id: 'user7m5' });
assert.ok(new URL(sent[1].url).searchParams.get('id') === 'user7m5', sent[1].url);
assert.equal(new URL(sent[1].url).searchParams.get('group'), 'AyuGram');
sent.length = 0;
await sendToBark('KEY1234567', 'Ann', 'hi', { id: 'user7m6', group: 'user7' });
assert.equal(new URL(sent[1].url).searchParams.get('group'), 'user7');
assert.equal(sent[0].body.group, 'user7');
refuseJson = false;
sent.length = 0;
const test = await worker.fetch(new Request('https://relay.example/test/KEY1234567'));
assert.equal(test.status, 200);
assert.equal(sent[0].body.device_key, 'KEY1234567');
const bad = await worker.fetch(new Request('https://relay.example/p/xx', { method: 'POST', body: 'x' }));
assert.equal(bad.status, 400);
assert.deepEqual(seenUpdate({ loc_key: 'READ_HISTORY', custom: { from_id: '7', max_id: '12' } }), { chat: 'user7', maxId: 12 });
assert.deepEqual(seenUpdate({ loc_key: 'MESSAGE_DELETED', custom: { channel_id: '99', messages: '4, 5' } }), { chat: 'channel99', deleted: ['4', '5'] });
assert.equal(seenUpdate({ loc_key: 'MESSAGE_TEXT', custom: { from_id: '7', msg_id: '3' } }), null);
{
  const sub = await subscription('SEENKEY123');
  const post = async (payload) => {
    const { body, headers } = await encryptAes128gcm(sub, JSON.stringify(payload));
    return worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body, headers }), env);
  };
  sent.length = 0;
  await post({ loc_key: 'READ_HISTORY', loc_args: [], custom: { from_id: '7', max_id: '20' } });
  assert.equal(sent.length, 0, 'A read sync is not a notification');
  await post({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'old'], custom: { from_id: '7', msg_id: '20' } });
  assert.equal(sent.length, 0, 'A message already read in another client is not shown');
  await post({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'new'], custom: { from_id: '7', msg_id: '21' } });
  assert.equal(sent.length, 1, 'A newer message is shown');
  await post({ loc_key: 'MESSAGE_DELETED', loc_args: [], custom: { from_id: '8', messages: '30' } });
  await post({ loc_key: 'MESSAGE_TEXT', loc_args: ['Bob', 'gone'], custom: { from_id: '8', msg_id: '30' } });
  assert.equal(sent.length, 1, 'A deleted message is not shown');
  assert.equal(await alreadySeen('SEENKEY123', { from_id: '7', msg_id: '19' }), true);
  assert.equal(await alreadySeen('OTHERKEY12', { from_id: '7', msg_id: '19' }), false, 'Read state is kept per Bark key');
  let waited = null;
  sent.length = 0;
  const { body, headers } = await encryptAes128gcm(sub, JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'later'], custom: { from_id: '7', msg_id: '40' } }));
  const response = await worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body, headers }), { NOTIFY_DELAY_MS: '5' }, { waitUntil(promise) { waited = promise; } });
  assert.equal(response.status, 201);
  assert.equal(sent.length, 0, 'Telegram gets its answer before the delay');
  await waited;
  assert.equal(sent.length, 1, 'The notification goes out after the delay');
}
{
  const objects = new Map();
  const PRESENCE = {
    idFromName(name) { return name; },
    get(id) {
      if (!objects.has(id)) {
        const data = new Map();
        objects.set(id, new Presence({ storage: {
          async get(k) { return data.get(k); },
          async put(k, v) { data.set(k, v); },
          async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
          async list({ prefix, limit }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort().slice(0, limit || Infinity)); },
        } }));
      }
      const object = objects.get(id);
      return { fetch: (url, init) => object.fetch(new Request(url, init)) };
    },
  };
  const activeEnv = { NOTIFY_DELAY_MS: '0', PRESENCE };
  const sub = await subscription('ACTIVEKEY1');
  const id = await activityId('ACTIVEKEY1');
  const push = async (msgId) => {
    const { body, headers } = await encryptAes128gcm(sub, JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'hi'], custom: { from_id: '70', msg_id: msgId } }));
    return worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body, headers }), activeEnv);
  };
  sent.length = 0;
  assert.equal((await worker.fetch(new Request('https://relay.example/active/' + id, { method: 'POST', body: '90' }), activeEnv)).status, 200);
  await push('1');
  assert.equal(sent.length, 0, 'Nothing is relayed while AyuGram is open');
  await worker.fetch(new Request('https://relay.example/active/' + id, { method: 'POST', body: '0' }), activeEnv);
  await push('2');
  assert.equal(sent.length, 1, 'Relaying resumes once AyuGram is closed');
  {
    const before = sent.splice(0);
    const sub2 = await subscription('ACTIVEKEY2');
    const id2 = await activityId('ACTIVEKEY2');
    const pushTo = async (msgId, account) => {
      const { body, headers } = await encryptAes128gcm(sub2, JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Bob', 'yo'], custom: { from_id: '71', msg_id: msgId } }));
      return worker.fetch(new Request('https://relay.example/p/' + sub2.token + (account ? '?a=' + account : ''), { method: 'POST', body, headers }), activeEnv);
    };
    await worker.fetch(new Request('https://relay.example/active/' + id2, { method: 'POST', body: '90|aaaaaaaaaaaa' }), activeEnv);
    await pushTo('10', 'aaaaaaaaaaaa');
    assert.equal(sent.length, 0, 'The account open in AyuGram gets no push');
    await pushTo('11', '');
    assert.equal(sent.length, 0, 'A push from an untagged subscription is held while AyuGram is open, as before');
    await pushTo('12', 'bbbbbbbbbbbb');
    assert.equal(sent.length, 1, 'Another account still gets its push while AyuGram is open');
    assert.ok(JSON.stringify(sent[0]).includes('acct=bbbbbbbbbbbb'), 'The push opens the right account');
    await pushTo('13', 'NOT-A-TAG');
    assert.equal(sent.length, 1, 'A malformed account is treated as unknown');
    await worker.fetch(new Request('https://relay.example/active/' + id2, { method: 'POST', body: '0' }), activeEnv);
    await pushTo('14', 'aaaaaaaaaaaa');
    assert.equal(sent.length, 2, 'Once AyuGram closes every account gets pushes again');
    sent.splice(0, sent.length, ...before);
  }
  const other = await subscription('ACTIVEKEY1');
  const { body, headers } = await encryptAes128gcm(other, JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'hi'], custom: { from_id: '70', msg_id: '2' } }));
  await worker.fetch(new Request('https://relay.example/p/' + other.token, { method: 'POST', body, headers }), activeEnv);
  assert.equal(sent.length, 1, 'The same message from a second subscription is not shown twice');
  await push('3');
  assert.equal(sent.length, 2, 'The next message is shown');
  sent.length = 0;
  const shown = (key) => worker.fetch(new Request('https://relay.example/shown/' + id, { method: 'POST', body: JSON.stringify({ barkKey: key }) }), activeEnv);
  assert.deepEqual(await (await shown('ACTIVEKEY1')).json(), [{ chat: 'user70', maxId: 3 }], 'The app learns which chats still have notifications');
  assert.equal((await shown('WRONGKEY12')).status, 400);
  assert.equal((await worker.fetch(new Request('https://relay.example/seen/' + id, { method: 'POST', body: JSON.stringify({ barkKey: 'ACTIVEKEY1', chat: 'user70' }) }), activeEnv)).status, 200);
  assert.deepEqual(sent.map((s) => s.body.id).sort(), ['user70m2', 'user70m3'], 'Opening the chat removes its notifications from Bark');
  assert.ok(sent.every((s) => s.body.delete === '1' && s.body.device_key === 'ACTIVEKEY1'));
  sent.length = 0;
  await worker.fetch(new Request('https://relay.example/seen/' + id, { method: 'POST', body: JSON.stringify({ barkKey: 'ACTIVEKEY1', chat: 'user70' }) }), activeEnv);
  assert.equal(sent.length, 0, 'Removed notifications are forgotten');
  assert.deepEqual(await (await shown('ACTIVEKEY1')).json(), [], 'Cleared chats are no longer listed');
  assert.equal((await worker.fetch(new Request('https://relay.example/seen/' + id, { method: 'POST', body: JSON.stringify({ barkKey: 'WRONGKEY12', chat: 'user70' }) }), activeEnv)).status, 400);
  await push('4');
  await push('5');
  sent.length = 0;
  const read = await encryptAes128gcm(sub, JSON.stringify({ loc_key: 'READ_HISTORY', loc_args: [], custom: { from_id: '70', max_id: '4' } }));
  await worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body: read.body, headers: read.headers }), activeEnv);
  assert.deepEqual(sent.map((s) => s.body.id), ['user70m4'], 'A read in Telegram removes the read notifications');
  assert.equal((await worker.fetch(new Request('https://relay.example/active/bad', { method: 'POST', body: '90' }), activeEnv)).status, 400);
  await worker.fetch(new Request('https://relay.example/active/' + id, { method: 'POST', body: '0' }), activeEnv);
  const collect = async (ack) => (await worker.fetch(new Request('https://relay.example/deleted/' + id, { method: 'POST', body: JSON.stringify({ barkKey: 'ACTIVEKEY1', ack }) }), activeEnv)).json();
  const sendPush = async (payload) => {
    const encrypted = await encryptAes128gcm(sub, JSON.stringify(payload));
    await worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body: encrypted.body, headers: encrypted.headers }), activeEnv);
  };
  await sendPush({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'secret plan'], custom: { from_id: '71', msg_id: '9' } });
  await sendPush({ loc_key: 'CHAT_MESSAGE_PHOTO', loc_args: ['Bob', 'Team'], custom: { chat_id: '12', from_id: '72', msg_id: '30' } });
  await sendPush({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'stays'], custom: { from_id: '71', msg_id: '10' } });
  assert.deepEqual(await collect([]), [], 'Nothing is offered before a deletion');
  await sendPush({ loc_key: 'MESSAGE_DELETED', loc_args: [], custom: { from_id: '71', messages: '9' } });
  await sendPush({ loc_key: 'MESSAGE_DELETED', loc_args: [], custom: { chat_id: '12', messages: '30,31' } });
  const deleted = await collect([]);
  assert.deepEqual(deleted.map((e) => e.id).sort(), ['chat12m30', 'user71m9'], 'Deleted stashed messages are offered, others are not');
  const auth = Buffer.from(sub.token, 'base64url').subarray(97, 113);
  const key = await crypto.subtle.importKey('raw', await crypto.subtle.digest('SHA-256', Buffer.concat([Buffer.from('ayugram-stash|'), auth])), 'AES-GCM', false, ['decrypt']);
  const open = async (entry) => JSON.parse(new TextDecoder().decode(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: Buffer.from(entry.iv, 'base64url') }, key, Buffer.from(entry.data, 'base64url'))));
  const dm = await open(deleted.find((e) => e.id === 'user71m9'));
  assert.equal(dm.text, 'secret plan');
  assert.equal(dm.chat, 'user71');
  assert.equal(dm.msg, 9);
  assert.equal(dm.from, '71');
  const group = await open(deleted.find((e) => e.id === 'chat12m30'));
  assert.equal(group.text, '📷 Photo', 'The author prefix is not part of the kept text');
  assert.equal(group.author, 'Bob');
  assert.ok(deleted.every((e) => !e.data.includes('secret')), 'Stashed text is encrypted');
  assert.deepEqual((await collect(['user71m9', 'chat12m30'])), [], 'Acknowledged messages are not offered again');
  assert.equal((await worker.fetch(new Request('https://relay.example/deleted/' + id, { method: 'POST', body: JSON.stringify({ barkKey: 'WRONGKEY12' }) }), activeEnv)).status, 400);
}
assert.equal(stashRecord({ loc_key: 'PINNED_MESSAGE_TEXT', loc_args: ['A', 'x'], custom: { from_id: '1', msg_id: '2' } }, { text: 'x' }), null, 'Pin notices are not stashed');
assert.equal(stashRecord({ loc_key: 'MESSAGE_TEXT', loc_args: ['A', 'x'], custom: { from_id: '1' } }, { text: 'x' }), null, 'A push without a message id is not stashed');
{
  const data = new Map();
  const storage = {
    async get(k) { return Array.isArray(k) ? new Map(k.filter((key) => data.has(key)).map((key) => [key, data.get(key)])) : data.get(k); },
    async put(k, v) { if (typeof k === 'object') { for (const [key, value] of Object.entries(k)) data.set(key, value); } else { data.set(k, v); } },
    async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
    async list({ prefix }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort()); },
  };
  const object = new Stats({ storage });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const statsEnv = { STATS, STATS_TOKEN: 'secret-token' };
  const ping = (body, country) => {
    const request = new Request('https://relay.example/stats/ping', { method: 'POST', body: JSON.stringify(body) });
    Object.defineProperty(request, 'cf', { value: { country } });
    return worker.fetch(request, statsEnv);
  };
  const base = { build: 207601, variant: 'standard', source: 'sideload', status: 'official', team: 'OWN1234567', teamName: 'Me', bundle: 'ph.telegra.Telegraph.OWN1234567', os: '26.1', device: 'iPhone17,1' };
  assert.equal((await ping({ ...base, id: 'install-0001' }, 'UA')).status, 200);
  for (let i = 0; i < 3; i += 1) {
    assert.equal((await ping({ ...base, id: 'scam-000' + i, source: 'testflight', status: 'modified', team: 'SCAM123456', teamName: 'Evil LLC', cert: 'Apple Distribution: Evil LLC (SCAM123456)\u0000' }, 'KZ')).status, 200);
  }
  assert.equal((await ping({ ...base, id: 'install-0001' }, 'UA')).status, 200, 'A repeated ping updates the same install');
  assert.equal((await ping({ ...base, id: 'bad id!' }, 'UA')).status, 400);
  assert.equal((await worker.fetch(new Request('https://relay.example/stats/ping', { method: 'POST', body: 'x'.repeat(5000) }), statsEnv)).status, 400, 'Oversized bodies are refused');
  const report = (text) => worker.fetch(new Request('https://relay.example/stats/report', { method: 'POST', body: JSON.stringify({ ...base, id: 'scam-0000', team: 'SCAM123456', text }) }), statsEnv);
  const sent = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => { sent.push({ url: String(url), body: JSON.parse(init.body) }); return new Response('{"ok":true}'); };
  try {
    assert.equal((await report('@scammer gave me an Apple ID')).status, 200);
    assert.equal(sent.length, 0, 'Without a bot token nothing is sent to Telegram');
    statsEnv.REPORT_BOT_TOKEN = '123:abc';
    statsEnv.REPORT_CHAT_ID = '42';
    for (let i = 0; i < 4; i += 1) await report('again ' + i);
    assert.equal(sent.length, 4, 'Every accepted report reaches the owner in Telegram');
    assert.equal(sent[0].url, 'https://api.telegram.org/bot123:abc/sendMessage');
    assert.equal(sent[0].body.chat_id, '42');
    assert.ok(sent[0].body.text.includes('again 0') && sent[0].body.text.includes('SCAM123456') && sent[0].body.text.includes('Сборка 207601'));
    assert.equal((await report('too many')).status, 429, 'Reports are limited per install and day');
    assert.equal(sent.length, 4, 'Refused reports are not sent');
  } finally {
    globalThis.fetch = realFetch;
  }
  assert.equal((await worker.fetch(new Request('https://relay.example/stats/summary'), statsEnv)).status, 403);
  assert.equal((await worker.fetch(new Request('https://relay.example/stats/summary', { headers: { authorization: 'Bearer wrong-token1' } }), statsEnv)).status, 403);
  const summary = await (await worker.fetch(new Request('https://relay.example/stats/summary', { headers: { authorization: 'Bearer secret-token' } }), statsEnv)).json();
  assert.equal(summary.total, 4);
  assert.equal(summary.teams[0].team, 'SCAM123456', 'The team with most installs comes first');
  assert.equal(summary.teams[0].installs, 3);
  assert.deepEqual(summary.teams[0].countries, { KZ: 3 });
  assert.deepEqual(summary.teams[0].sources, { testflight: 3 });
  assert.equal(summary.teams[0].certs[0], 'Apple Distribution: Evil LLC (SCAM123456)', 'Control characters are stripped');
  assert.equal(summary.reports.length, 5);
  assert.ok(summary.reports.some((r) => r.text === '@scammer gave me an Apple ID' && r.team === 'SCAM123456'));
  assert.equal(summary.byCountry.UA, 1);
  assert.ok(!JSON.stringify(summary).includes('install-0001'), 'Install ids never leave the worker');
  assert.equal((await worker.fetch(new Request('https://relay.example/stats/ping', { method: 'POST', body: '{}' }), {})).status, 503);

  const scammerHash = await accountHash('555');
  assert.equal(scammerHash, (await import('node:crypto')).createHash('sha256').update('ayugram-account|555').digest('hex').slice(0, 32), 'The app and the worker hash account ids the same way');
  assert.equal((await ping({ ...base, id: 'scammer-001', accounts: [scammerHash, 'not-a-hash'] }, 'RU')).status, 200);
  const botEnv = { STATS, STATS_TOKEN: 'secret-token', REPORT_BOT_TOKEN: '123:abc', REPORT_CHAT_ID: '1272887902', REPORT_WEBHOOK_SECRET: 'hook-secret' };
  const calls = [];
  const realFetch2 = globalThis.fetch;
  let failMethod = '';
  globalThis.fetch = async (url, init) => {
    const method = String(url).split('/').pop();
    const body = init.body instanceof FormData
      ? Object.fromEntries([...init.body].map(([k, v]) => [k, typeof v === 'string' ? v : { size: v.size, type: v.type, name: v.name }]))
      : JSON.parse(init.body);
    calls.push({ method, body });
    if (method === failMethod) {
      return new Response('{"ok":false}', { status: 400 });
    }
    return Response.json({ ok: true, result: { message_id: 77 } });
  };
  const status = async (accounts) => (await worker.fetch(new Request('https://relay.example/stats/status', { method: 'POST', body: JSON.stringify({ id: 'install-0001', accounts }) }), botEnv)).json();
  const hook = (update, secret = 'hook-secret') => worker.fetch(new Request('https://relay.example/tg/hook', { method: 'POST', headers: { 'x-telegram-bot-api-secret-token': secret }, body: JSON.stringify(update) }), botEnv);
  const press = (data, from = 1272887902) => hook({ callback_query: { id: 'q1', from: { id: from }, data, message: { message_id: 7, chat: { id: from } } } });
  const sendText = (text, from = 1272887902) => hook({ message: { from: { id: from }, chat: { id: from }, text } });
  try {
    const sendReport = (body) => worker.fetch(new Request('https://relay.example/stats/report', { method: 'POST', body: JSON.stringify({ ...base, id: 'victim-0001', ...body }) }), botEnv);
    assert.equal((await sendReport({ text: '@scam sold me AyuGram', target: '555', targetName: '@scam Scam' })).status, 200);
    const notice = calls.pop();
    assert.equal(notice.method, 'sendMessage');
    assert.equal(notice.body.chat_id, '1272887902');
    assert.ok(notice.body.text.includes('На кого: @scam Scam (ID 555)'));
    assert.ok(/Жалобщик: #[0-9A-F]{6}/.test(notice.body.text), 'A report carries a stable reporter tag');
    const rid = notice.body.reply_markup.inline_keyboard[0][0].callback_data.slice(2);
    assert.match(rid, /^[0-9a-f]{12}$/);
    assert.equal((await hook({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/start' } }, 'wrong-secret')).status, 403, 'Updates without the webhook secret are refused');
    assert.equal((await press('v:' + rid, 999)).status, 200);
    assert.equal((await hook({ message: { from: { id: 999 }, chat: { id: 999 }, text: '/start' } })).status, 200);
    assert.equal(calls.length, 0, 'The bot ignores everyone but the owner');
    await press('v:' + rid);
    let edit = calls.find((call) => call.method === 'editMessageText');
    assert.ok(edit.body.text.includes('AyuGram: ✅ установлен (1 устр.)'), 'The review checks whether the scammer has AyuGram');
    assert.deepEqual(edit.body.reply_markup.inline_keyboard.flat().map((b) => b.callback_data), ['w:' + rid, 'b:' + rid, 'd:' + rid, 'm:' + rid]);
    assert.deepEqual(await status([scammerHash]), { banned: false, warning: null, blocked: false, banReason: null, blockReason: null });
    calls.length = 0;
    await press('w:' + rid);
    const warned = await status([scammerHash]);
    assert.equal(warned.banned, false);
    assert.ok(warned.warning.startsWith(rid), 'A warning reaches the scammer install');
    assert.deepEqual(await status([await accountHash('556')]), { banned: false, warning: null, blocked: false, banReason: null, blockReason: null }, 'Other accounts are not affected');
    calls.length = 0;
    await press('b:' + rid);
    edit = calls.find((call) => call.method === 'editMessageText');
    assert.equal(edit.body.reply_markup.inline_keyboard[0][0].callback_data, 'B:' + rid + ':scam', 'A ban asks for a reason');
    assert.deepEqual(edit.body.reply_markup.inline_keyboard.flat().map((b) => b.callback_data).slice(-1), ['v:' + rid], 'The reason picker can be cancelled');
    assert.equal((await status([scammerHash])).banned, false);
    calls.length = 0;
    await press('B:' + rid + ':scam');
    const bannedStatus = await status(['0'.repeat(32), scammerHash]);
    assert.equal(bannedStatus.banned, true, 'The ban reaches the scammer install');
    assert.equal(bannedStatus.banReason, 'scam', 'The ban carries its reason to the app');
    edit = calls.find((call) => call.method === 'editMessageText');
    assert.ok(edit.body.text.includes('⛔ забанен') && edit.body.text.includes('причина: Мошенничество'), 'The review shows the ban reason');
    assert.equal(edit.body.reply_markup.inline_keyboard[0][1].callback_data, 'u:' + rid);
    calls.length = 0;
    await press('d:' + rid);
    const details = calls.find((call) => call.method === 'sendMessage');
    assert.ok(details.body.text.includes('ID: 555') && details.body.text.includes('установлен на 1 устр.') && details.body.text.includes('Установка: ✅ найдена') === false);
    assert.ok(details.body.text.includes('Установка: ❌ не найдена'), 'A report from an install that never pinged is marked');
    assert.ok(!details.body.text.includes('scammer-001') && !details.body.text.includes(scammerHash), 'Install ids and hashes stay inside the worker');
    calls.length = 0;
    await press('u:' + rid);
    assert.equal((await status([scammerHash])).banned, false, 'Unban lifts it');
    calls.length = 0;
    const other = await worker.fetch(new Request('https://relay.example/stats/report', { method: 'POST', body: JSON.stringify({ ...base, id: 'install-0001', text: 'no username here' }) }), botEnv);
    assert.equal(other.status, 200);
    const plainRid = calls.pop().body.reply_markup.inline_keyboard[0][0].callback_data.slice(2);
    calls.length = 0;
    await press('w:' + plainRid);
    const refused = calls.find((call) => call.method === 'answerCallbackQuery');
    assert.ok(refused.body.show_alert && refused.body.text.startsWith('Не на кого'), 'Without a scammer there is nobody to warn');
    calls.length = 0;
    await press('d:' + plainRid);
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('Установка: ✅ найдена'), 'A report from a real install is marked');
    calls.length = 0;
    const withMedia = await worker.fetch(new Request('https://relay.example/stats/report', { method: 'POST', body: JSON.stringify({ ...base, id: 'media-00001', text: '@scam screenshots', target: '555', targetName: '@scam Scam', attachments: 9 }) }), botEnv);
    const ticket = await withMedia.json();
    assert.match(ticket.token, /^[0-9a-f]{32}$/);
    assert.ok(calls.pop().body.text.includes('Вложений: 5'), 'The notice says attachments follow, capped at five');
    const attach = (body, type, token = ticket.token, rid = ticket.rid) => worker.fetch(new Request('https://relay.example/stats/attach/' + rid, { method: 'POST', headers: { 'content-type': type, 'x-ayugram-token': token }, body }), botEnv);
    assert.equal((await attach(new Uint8Array([1, 2, 3]), 'image/jpeg', 'f'.repeat(32))).status, 403, 'Attachments need the ticket token');
    assert.equal((await attach(new Uint8Array([1, 2, 3]), 'application/zip')).status, 400, 'Only photos and videos are taken');
    assert.equal((await attach(new Uint8Array(0), 'image/jpeg')).status, 413);
    assert.equal(calls.length, 0);
    assert.equal((await attach(new Uint8Array([1, 2, 3]), 'image/jpeg')).status, 200);
    let sentMedia = calls.pop();
    assert.equal(sentMedia.method, 'sendPhoto');
    assert.equal(sentMedia.body.chat_id, '1272887902');
    assert.equal(JSON.parse(sentMedia.body.reply_parameters).message_id, 77, 'Attachments reply to the report message');
    assert.ok(sentMedia.body.caption.includes('@scam Scam'));
    assert.deepEqual(sentMedia.body.photo, { size: 3, type: 'image/jpeg', name: 'attachment-1.jpg' });
    assert.equal((await attach(new Uint8Array([4, 5]), 'video/quicktime')).status, 200);
    assert.equal(calls.pop().method, 'sendVideo');
    failMethod = 'sendPhoto';
    assert.equal((await attach(new Uint8Array([6]), 'image/png')).status, 200);
    assert.deepEqual(calls.splice(0).map((call) => call.method), ['sendPhoto', 'sendDocument'], 'A photo Telegram refuses goes as a file');
    failMethod = '';
    await attach(new Uint8Array([7]), 'image/jpeg');
    await attach(new Uint8Array([8]), 'image/jpeg');
    assert.equal((await attach(new Uint8Array([9]), 'image/jpeg')).status, 429, 'At most five attachments per report');
    calls.length = 0;
    await press('d:' + ticket.rid);
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('Вложений: 5 из 5'));
    const noBot = await worker.fetch(new Request('https://relay.example/stats/attach/' + ticket.rid, { method: 'POST', headers: { 'content-type': 'image/jpeg', 'x-ayugram-token': ticket.token }, body: new Uint8Array([1]) }), { STATS });
    assert.equal(noBot.status, 503, 'Without the bot attachments are refused rather than lost');
    calls.length = 0;
    await press('v:ffffffffffff');
    assert.ok(calls.find((call) => call.method === 'answerCallbackQuery').body.text === 'Жалоба не найдена');

    const sig = (value) => createHash('sha256').update('ayugram-sig|' + value).digest('hex').slice(0, 32);
    const check = async (body, country = 'KZ') => {
      const request = new Request('https://relay.example/stats/status', { method: 'POST', body: JSON.stringify({ id: 'install-0001', accounts: [], check: true, build: 208301, variant: 'standard', status: 'official', source: 'sideload', devices: 1, repo: 'mapix3/AyuGram-iOS', official: true, tsig: sig('OWN1234567'), bsig: sig('org.example.app'), ...body }) });
      Object.defineProperty(request, 'cf', { value: { country } });
      return (await worker.fetch(request, botEnv)).json();
    };
    calls.length = 0;
    assert.deepEqual(await check({}), { banned: false, warning: null, blocked: false, banReason: null, blockReason: null }, 'Our build signed for yourself is not a copy');
    assert.equal(calls.length, 0);
    const forkBody = { id: 'fork-000001', status: 'modified', repo: 'scammer/AyuGram-iOS', commit: 'abcdef123456', run: '99', official: false, tsig: sig('EVIL123456'), bsig: sig('com.evil.ayu'), team: 'EVIL123456', teamName: 'Evil LLC', cert: 'Apple Development: Evil', profile: 'Evil Profile', bundle: 'com.evil.ayu', devices: 50, device: 'iPhone17,1', os: '26.1' };
    assert.deepEqual(await check(forkBody), { banned: false, warning: null, blocked: false, banReason: null, blockReason: null }, 'A fork learns nothing from the reply');
    const forkNotice = calls.find((call) => call.method === 'sendMessage');
    assert.equal(forkNotice.body.chat_id, '1272887902', 'Forks reach the owner');
    assert.ok(forkNotice.body.text.startsWith('🍴 Форк AyuGram') && forkNotice.body.text.includes('github.com/scammer/AyuGram-iOS') && forkNotice.body.text.includes('EVIL123456 / Evil LLC') && forkNotice.body.text.includes('com.evil.ayu'));
    assert.ok(!forkNotice.body.text.includes('fork-000001'), 'Install ids stay inside the worker');
    assert.ok(forkNotice.body.text.includes('Где собрана: GitHub Actions') && forkNotice.body.text.includes('https://github.com/scammer/AyuGram-iOS/commit/abcdef123456') && forkNotice.body.text.includes('https://github.com/scammer/AyuGram-iOS/actions/runs/99'), 'A fork card links its repository, commit and CI run');
    const cid = forkNotice.body.reply_markup.inline_keyboard[0][0].callback_data.slice(2);
    assert.equal(forkNotice.body.reply_markup.inline_keyboard[0][0].callback_data, 'k:' + cid);
    calls.length = 0;
    await check({ ...forkBody, id: 'fork-000002' });
    assert.equal(calls.length, 0, 'A copy is announced once');
    await press('y:' + cid);
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('Установок: 2'), 'Refresh counts every install of the copy');
    calls.length = 0;
    await press('k:' + cid);
    assert.equal(calls.find((call) => call.method === 'editMessageText').body.reply_markup.inline_keyboard[0][0].callback_data, 'K:' + cid + ':testflight', 'A block asks for a reason');
    assert.equal((await check(forkBody)).blocked, false);
    calls.length = 0;
    await press('K:' + cid + ':fork', 999);
    assert.equal((await check(forkBody)).blocked, false, 'Only the owner blocks');
    await press('K:' + cid + ':fork');
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('заблокирована по сертификату, bundle id, репозиторию'));
    const blockedCheck = await check(forkBody);
    assert.equal(blockedCheck.blocked, true, 'The block reaches the copy');
    assert.equal(blockedCheck.blockReason, 'fork', 'The block carries its reason to the app');
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('Причина: Неофициальный форк'), 'The copy card shows the reason');
    assert.equal((await check({ ...forkBody, bsig: sig('com.other.bundle'), repo: 'other/repo' })).blocked, true, 'Changing the bundle id or repository does not escape the certificate');
    assert.equal((await check({ ...forkBody, tsig: sig('NEW1234567'), bsig: sig('com.other.bundle') })).blocked, true, 'A new certificate in the same repository stays blocked');
    assert.equal((await check({ ...forkBody, tsig: sig('NEW1234567'), repo: 'SCAMMER/ayugram-ios', bsig: sig('x.y') })).blocked, true, 'Repository names are compared case-insensitively');
    assert.equal((await check({})).blocked, false, 'Official installs stay open');
    assert.equal((await check({ status: 'modified', tsig: '', bsig: sig('org.example.app'), team: 'OURTEST001' })).blocked, false, 'Our own bundle id is never blocked');
    calls.length = 0;
    await press('x:' + cid);
    assert.equal((await check(forkBody)).blocked, false, 'Unblock lifts it');
    calls.length = 0;
    await check({ id: 'dist-000001', source: 'enterprise', tsig: sig('DIST123456'), official: false, bsig: sig('com.dist.app'), team: 'DIST123456', bundle: 'com.dist.app' });
    const distNotice = calls.find((call) => call.method === 'sendMessage');
    assert.ok(distNotice.body.text.startsWith('📤 Нашу сборку раздают'), 'Redistributed official builds reach the owner');
    assert.ok(distNotice.body.text.includes('Где собрана: GitHub Actions (наш репозиторий)'), 'Our own builds are marked as ours');
    calls.length = 0;
    await check({ id: 'gitlab-00001', repo: 'grp/sub/ayu', platform: 'gitlab', server: 'https://gitlab.example.com', commit: 'abcdef1', run: '5', official: false, tsig: sig('GLAB123456') });
    const glNotice = calls.find((call) => call.method === 'sendMessage');
    assert.ok(glNotice.body.text.includes('Где собрана: GitLab CI') && glNotice.body.text.includes('https://gitlab.example.com/grp/sub/ayu/-/pipelines/5') && glNotice.body.text.includes('https://gitlab.example.com/grp/sub/ayu/-/commit/abcdef1'), 'GitLab builds link their pipeline');
    calls.length = 0;
    await check({ id: 'local-000001', repo: '', platform: 'local', server: 'javascript:x', official: false, tsig: sig('LOCAL12345') });
    const localNotice = calls.find((call) => call.method === 'sendMessage');
    assert.ok(localNotice.body.text.includes('Где собрана: локально, не на CI') && !localNotice.body.text.includes('javascript'), 'Local builds say so and forged servers are dropped');
    calls.length = 0;
    await check({ id: 'mod-0000001', status: 'modified', official: true, tsig: '', bsig: sig('org.example.app'), plistBuild: 999999 });
    const modified = calls.find((call) => call.method === 'sendMessage');
    assert.ok(modified.body.text.startsWith('✂️ Изменённая сборка') && modified.body.text.includes('в Info.plist 999999') && modified.body.text.includes('Заблокировать нечем'));
    assert.deepEqual(modified.body.reply_markup.inline_keyboard.flat().map((b) => b.callback_data.slice(0, 2)), ['y:'], 'Nothing to block offers only a refresh');
    calls.length = 0;
    for (let i = 0; i < 25; i += 1) {
      await check({ id: 'spam-' + String(i).padStart(6, '0'), repo: 'spam' + i + '/x', tsig: sig('SPAM' + i), official: false });
    }
    assert.equal(calls.filter((call) => call.method === 'sendMessage').length, 11, 'New copies are announced at most twenty a day');
    calls.length = 0;
    await press('y:ffffffffffff');
    assert.equal(calls.find((call) => call.method === 'answerCallbackQuery').body.text, 'Копия не найдена');

    await press('b:' + rid);
    await press('B:' + rid);
    await press('k:' + cid);
    await press('K:' + cid);
    assert.equal((await status([scammerHash])).banned, true);
    assert.equal((await check(forkBody)).blocked, true);
    calls.length = 0;
    await sendText('/bans');
    const list = calls.find((call) => call.method === 'sendMessage');
    assert.ok(list.body.text.includes('Забаненные аккаунты (1)') && list.body.text.includes('@scam Scam'), 'The ban list names the banned account');
    assert.ok(list.body.text.includes('Заблокированные копии (1)') && list.body.text.includes('scammer/AyuGram-iOS'), 'The ban list names the blocked copy');
    const buttons = list.body.reply_markup.inline_keyboard.flat().map((b) => b.callback_data);
    assert.ok(buttons.includes('V:555') && buttons.includes('X:' + cid) && buttons.includes('L:x'), 'The list offers unban by id and unblock');
    assert.equal((await sendText('/bans', 999)).status, 200);
    assert.equal(calls.filter((call) => call.method === 'sendMessage').length, 1, 'Only the owner lists bans');
    calls.length = 0;
    await press('V:555');
    assert.equal((await status([scammerHash])).banned, false, 'Unban from the list lifts the ban');
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('Забаненные аккаунты (0)'), 'The list refreshes in place');
    calls.length = 0;
    await press('X:' + cid);
    assert.equal((await check(forkBody)).blocked, false, 'Unblock from the list lifts the block');
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('Заблокированные копии (0)'));

    const hash777 = await accountHash('777');
    calls.length = 0;
    await sendText('/ban 777');
    const picker = calls.find((call) => call.method === 'sendMessage');
    assert.ok(picker.body.text.includes('Выбери причину'), 'A ban by id asks for a reason');
    assert.ok(picker.body.reply_markup.inline_keyboard.flat().some((b) => b.callback_data === 'Z:777:resale'));
    assert.equal((await status([hash777])).banned, false, 'Nothing is banned before a reason is picked');
    calls.length = 0;
    await press('Z:777:resale');
    const banned777 = calls.find((call) => call.method === 'editMessageText');
    assert.ok(banned777.body.text.includes('⛔ Забанен ID 777') && banned777.body.text.includes('Продажа AyuGram'), 'The owner can ban by id with a reason');
    const status777 = await status([hash777]);
    assert.equal(status777.banned, true, 'A ban by id reaches that account');
    assert.equal(status777.banReason, 'resale');
    calls.length = 0;
    await sendText('/bans');
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('ID 777 · ') && calls.find((call) => call.method === 'sendMessage').body.text.includes('Продажа AyuGram'), 'The ban list shows reasons');
    calls.length = 0;
    await sendText('/unban 777');
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('✅ Разбанен ID 777'));
    assert.equal((await status([hash777])).banned, false, 'Unban by id lifts it');
    await press('Z:777:scam', 999);
    assert.equal((await status([hash777])).banned, false, 'Only the owner bans by id');
    calls.length = 0;
    await sendText('/ban nonsense');
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('числовой ID'), 'A non-numeric id is rejected');
    await press('Z:777:bogus');
    assert.equal((await status([hash777])).banReason, null, 'An unknown reason is stored as none');
    calls.length = 0;
    assert.equal((await ping({ ...base, id: 'target-7777', accounts: [hash777] }, 'RU')).status, 200);
    await press('Z:777:abuse');
    assert.ok(calls.find((call) => call.method === 'editMessageText').body.text.includes('✅ найден (1 устр.)'), 'A direct ban reports whether AyuGram is installed');
    await sendText('/unban 777');
    calls.length = 0;
    await press('Z:777:custom');
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('Напиши причину'), 'A custom reason is asked for as text');
    assert.equal((await status([hash777])).banned, false, 'Nothing is banned before the custom reason arrives');
    calls.length = 0;
    await sendText('слив  исходников\nв паблик');
    const custom777 = await status([hash777]);
    assert.equal(custom777.banned, true, 'The custom reason applies the ban');
    assert.equal(custom777.banReason, 'слив исходников в паблик', 'The custom reason reaches the app as text');
    calls.length = 0;
    await sendText('/bans');
    assert.ok(calls.find((call) => call.method === 'sendMessage').body.text.includes('слив исходников в паблик'), 'The ban list shows the custom reason');
    await sendText('просто текст');
    assert.equal((await status([hash777])).banReason, 'слив исходников в паблик', 'Text without a pending question changes nothing');
    await sendText('/unban 777');
    await press('Z:777:custom');
    await sendText('/cancel');
    await sendText('поздно');
    assert.equal((await status([hash777])).banned, false, 'A cancelled custom reason bans nobody');
  } finally {
    globalThis.fetch = realFetch2;
  }
}
console.log('push relay: aes128gcm and aesgcm pushes reach Bark');

await testBadges();
async function testBadges() {
  const data = new Map();
  const storage = {
    async get(k) { return Array.isArray(k) ? new Map(k.filter((key) => data.has(key)).map((key) => [key, data.get(key)])) : data.get(k); },
    async put(k, v) { if (typeof k === 'object') { for (const [key, value] of Object.entries(k)) data.set(key, value); } else { data.set(k, v); } },
    async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
    async list({ prefix }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort()); },
  };
  const object = new Stats({ storage });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const env = { STATS, REPORT_BOT_TOKEN: '1:a', REPORT_CHAT_ID: '1272887902', REPORT_WEBHOOK_SECRET: 'h' };
  const sent = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => { sent.push(JSON.parse(init.body)); return new Response('{"ok":true}'); };
  try {
    const post = (path, body) => worker.fetch(new Request('https://relay.example' + path, { method: 'POST', body: JSON.stringify(body) }), env);
    const list = async () => (await (await worker.fetch(new Request('https://relay.example/badges'), env)).json()).items;
    const hook = (update) => worker.fetch(new Request('https://relay.example/tg/hook', { method: 'POST', headers: { 'x-telegram-bot-api-secret-token': 'h' }, body: JSON.stringify(update) }), env);
    const secret = 'a'.repeat(32);
    const thief = 'b'.repeat(32);
    assert.equal((await post('/badges/set', { id: '500', secret, badge: { symbol: 'crown.fill' } })).status, 403, 'Nobody sets a badge before it is granted');
    assert.deepEqual(await list(), [], 'No supporters yet');
    const requested = await (await post('/badges/request', { id: '500', secret, name: 'Payer' })).json();
    assert.match(requested.code, /^[A-Z0-9]{6}$/, 'A request gets a code');
    assert.ok(sent[0].text.includes(requested.code) && sent[0].reply_markup.inline_keyboard[0][0].callback_data === 'G:' + requested.code, 'The owner is asked to grant');
    assert.equal((await (await post('/badges/request', { id: '500', secret })).json()).code, requested.code, 'Asking again keeps the code');
    assert.equal((await (await post('/badges/status', { id: '500', secret })).json()).granted, false);
    await hook({ callback_query: { id: 'q', from: { id: 999 }, data: 'G:' + requested.code, message: { message_id: 1, chat: { id: 999 } } } });
    assert.deepEqual(await list(), [], 'Only the owner grants');
    await hook({ callback_query: { id: 'q', from: { id: 1272887902 }, data: 'G:' + requested.code, message: { message_id: 1, chat: { id: 1272887902 } } } });
    assert.equal((await list()).length, 1, 'A granted supporter is listed');
    assert.equal((await post('/badges/set', { id: '500', secret: thief, badge: { symbol: 'crown.fill' } })).status, 403, 'Another install cannot change the badge');
    assert.equal((await (await post('/badges/status', { id: '500', secret: thief })).json()).granted, false, 'Another install is not the owner of the badge');
    assert.equal((await post('/badges/set', { id: '500', secret, badge: { symbol: 'crown.fill', emoji: '<b>', shape: 9, top: 'zzzzzz', bottom: 'ff0000', darkGlyph: true } })).status, 200);
    assert.deepEqual((await list())[0], { id: '500', b: { symbol: 'crown.fill', emoji: '', shape: 0, top: '8E61F2', bottom: 'FF0000', darkGlyph: true } }, 'The stored badge is sanitized');
    await hook({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/unbadge 500' } });
    assert.deepEqual(await list(), [], 'The owner can take a badge back');
    await hook({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/badge 501' } });
    assert.equal((await post('/badges/set', { id: '501', secret, badge: {} })).status, 200, 'A badge granted by id is claimed by the first install');
    assert.equal((await post('/badges/set', { id: '501', secret: thief, badge: {} })).status, 403, 'and locked to it afterwards');
    console.log('push relay: supporter badges are granted by the owner and locked to the paying install');
  } finally {
    globalThis.fetch = real;
  }
}
await testBadgePayments();
async function testBadgePayments() {
  const data = new Map();
  const storage = {
    async get(k) { return data.get(k); },
    async put(k, v) { data.set(k, v); },
    async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
    async list({ prefix }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort()); },
  };
  const object = new Stats({ storage });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const env = { STATS, REPORT_BOT_TOKEN: '1:a', REPORT_CHAT_ID: '1272887902', REPORT_WEBHOOK_SECRET: 'h', CRYPTOPAY_TOKEN: '1234:test' };
  const invoices = new Map();
  let nextInvoice = 70;
  let tonList = [];
  const rocketInvoices = new Map();
  const owner = [];
  const real = globalThis.fetch;
  const realNow = Date.now;
  let shift = 0;
  Date.now = () => realNow() + shift;
  globalThis.fetch = async (url, init) => {
    const link = String(url);
    const body = init && init.body ? JSON.parse(init.body) : {};
    if (link.startsWith('https://pay.crypt.bot/api/')) {
      assert.equal(init.headers['Crypto-Pay-API-Token'], '1234:test');
      const method = link.slice(26);
      if (method === 'createInvoice') {
        assert.equal(body.fiat, 'USD');
        assert.equal(body.amount, '3');
        const invoice = { invoice_id: nextInvoice++, status: 'active', payload: body.payload, bot_invoice_url: 'https://t.me/CryptoBot?start=IV' + nextInvoice, amount: '3', fiat: 'USD' };
        invoices.set(invoice.invoice_id, invoice);
        return Response.json({ ok: true, result: invoice });
      }
      if (method === 'getInvoices') {
        const ids = body.invoice_ids ? body.invoice_ids.split(',').map(Number) : [...invoices.keys()];
        return Response.json({ ok: true, result: { items: ids.map((id) => invoices.get(id)).filter((item) => item && (!body.status || item.status === body.status)) } });
      }
      if (method === 'getMe') {
        return Response.json({ ok: true, result: { app_id: 1, name: 'AyuGram badges' } });
      }
      if (method === 'getExchangeRates') {
        return Response.json({ ok: true, result: [{ is_valid: true, source: 'TON', target: 'USD', rate: '2.5' }] });
      }
    }
    if (link.startsWith('https://pay.xrocket.tg/')) {
      assert.equal(init.headers['Rocket-Pay-Key'], 'rocket-test');
      if (link === 'https://pay.xrocket.tg/app/info') {
        return Response.json({ success: true, data: { name: 'AyuGram rocket' } });
      }
      if (init.method === 'POST' && link === 'https://pay.xrocket.tg/tg-invoices') {
        assert.deepEqual([body.amount, body.currency, body.numPayments], [3, 'USDT', 1]);
        const invoice = { id: 900 + rocketInvoices.size, amount: body.amount, currency: body.currency, payload: body.payload, status: 'active', link: 'https://t.me/xrocket?start=inv_test' + rocketInvoices.size };
        rocketInvoices.set(String(invoice.id), invoice);
        return Response.json({ success: true, data: invoice });
      }
      const invoice = rocketInvoices.get(link.split('/').pop());
      return invoice ? Response.json({ success: true, data: invoice }) : Response.json({ success: false }, { status: 404 });
    }
    if (link.startsWith('https://toncenter.com/api/v2/getTransactions')) {
      assert.ok(link.includes('UQCvj3aWiCCzawOO5OeRM9C3Ts5n4hc1tep1ZZ7aBYG33Glp'));
      return Response.json({ ok: true, result: tonList });
    }
    if (link.startsWith('https://api.telegram.org/')) {
      owner.push(body);
      return Response.json({ ok: true });
    }
    throw new Error('unexpected fetch ' + link);
  };
  try {
    const post = (path, body) => worker.fetch(new Request('https://relay.example' + path, { method: 'POST', body: JSON.stringify(body) }), env);
    const list = async () => (await (await worker.fetch(new Request('https://relay.example/badges'), env)).json()).items.map((item) => item.id);
    const secret = 'c'.repeat(32);
    const first = await (await post('/badges/request', { id: '600', secret, name: 'Crypto' })).json();
    assert.match(first.code, /^[A-Z0-9]{6}$/);
    assert.ok(first.pay.cryptobot.startsWith('https://t.me/CryptoBot?start=IV'), 'A request gets its own Crypto Bot invoice');
    assert.deepEqual([first.pay.ton.amount, first.pay.ton.nano, first.pay.ton.comment], ['1.2', '1200000000', first.code], 'and a TON quote with the code as the comment');
    assert.ok(first.pay.ton.url.startsWith('ton://transfer/UQCvj3aWiCCzawOO5OeRM9C3Ts5n4hc1tep1ZZ7aBYG33Glp?amount=1200000000&text=' + first.code));
    assert.equal(invoices.size, 1);
    shift += 10000;
    const again = await (await post('/badges/status', { id: '600', secret })).json();
    assert.equal(again.granted, false, 'An unpaid invoice grants nothing');
    assert.equal(again.pay.cryptobot, first.pay.cryptobot, 'The invoice is reused');
    assert.equal(invoices.size, 1);
    const invoice = invoices.get(70);
    invoice.status = 'paid';
    invoice.paid_amount = '3';
    invoice.paid_asset = 'USDT';
    const update = JSON.stringify({ update_id: 1, update_type: 'invoice_paid', request_date: new Date().toISOString(), payload: invoice });
    const key = await crypto.subtle.importKey('raw', await crypto.subtle.digest('SHA-256', new TextEncoder().encode('1234:test')), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = Buffer.from(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(update))).toString('hex');
    const hook = (sig) => worker.fetch(new Request('https://relay.example/pay/cryptobot', { method: 'POST', headers: { 'crypto-pay-api-signature': sig }, body: update }), env);
    assert.equal((await hook('0'.repeat(64))).status, 403, 'A forged webhook is refused');
    assert.deepEqual(await list(), [], 'and grants nothing');
    assert.equal((await hook(signature)).status, 200);
    assert.deepEqual(await list(), ['600'], 'A signed invoice_paid webhook grants the badge');
    assert.ok(owner.at(-1).text.includes('автоматически') && owner.at(-1).text.includes('3 USDT') && owner.at(-1).reply_markup.inline_keyboard[0][0].callback_data === 'R:600', 'The owner is told and can take it back');
    assert.equal((await (await post('/badges/status', { id: '600', secret })).json()).granted, true, 'The payer sees the badge');
    assert.equal((await post('/badges/set', { id: '600', secret, badge: { symbol: 'star.fill' } })).status, 200, 'and can edit it');
    assert.equal((await hook(signature)).status, 200, 'A repeated webhook is harmless');

    const tonSecret = 'd'.repeat(32);
    const ton = await (await post('/badges/request', { id: '601', secret: tonSecret, name: 'Ton' })).json();
    tonList = [{ utime: Math.floor(Date.now() / 1000), transaction_id: { lt: '1', hash: 'h1' }, in_msg: { source: 'EQsender', value: '1000000000', message: ton.code } }];
    shift += 10000;
    assert.equal((await (await post('/badges/status', { id: '601', secret: tonSecret })).json()).granted, false, 'Too little TON grants nothing');
    tonList.push({ utime: Math.floor(Date.now() / 1000), transaction_id: { lt: '2', hash: 'h2' }, in_msg: { source: 'EQsender', value: '1190000000', message: ' ' + ton.code.toLowerCase() + ' ' } });
    shift += 4000;
    assert.equal((await (await post('/badges/status', { id: '601', secret: tonSecret })).json()).granted, false, 'Checks are throttled');
    shift += 6000;
    const paidTon = await (await post('/badges/status', { id: '601', secret: tonSecret })).json();
    assert.equal(paidTon.granted, true, 'A TON transfer with the code in the comment grants the badge');
    assert.ok(owner.at(-1).text.includes('1.19 TON'));
    assert.deepEqual((await list()).sort(), ['600', '601']);

    const cronSecret = 'e'.repeat(32);
    const cron = await (await post('/badges/request', { id: '602', secret: cronSecret, name: 'Cron' })).json();
    tonList.push({ utime: Math.floor(Date.now() / 1000), transaction_id: { lt: '3', hash: 'h2' }, in_msg: { source: 'EQsender', value: '5000000000', message: cron.code } });
    assert.equal(await checkBadgePayments(env), 0, 'A reused TON transaction grants nothing');
    const cronInvoice = [...invoices.values()].find((item) => item.payload === cron.code);
    cronInvoice.status = 'paid';
    assert.equal(await checkBadgePayments(env), 1, 'The scheduled check grants a paid invoice when the app is closed');
    assert.deepEqual((await list()).sort(), ['600', '601', '602']);
    assert.equal(await checkBadgePayments(env), 0, 'Nothing is left to check');
    const rocketEnv = { ...env, XROCKET_TOKEN: 'rocket-test', XROCKET_WEBHOOK_TOKEN: 'hook-test' };
    const rocketPost = (path, body) => worker.fetch(new Request('https://relay.example' + path, { method: 'POST', body: JSON.stringify(body) }), rocketEnv);
    const rocketSecret = 'g'.repeat(32);
    const rocket = await (await rocketPost('/badges/request', { id: '604', secret: rocketSecret, name: 'Rocket' })).json();
    assert.ok(rocket.pay.xrocket.startsWith('https://t.me/xrocket?start=inv_test'), 'A request gets its own xRocket invoice');
    const rocketInvoice = [...rocketInvoices.values()].find((item) => item.payload === rocket.code);
    const rocketBody = JSON.stringify({ type: 'invoicePay', data: { id: rocketInvoice.id, payload: rocket.code, status: 'paid' } });
    const rocketKey = await crypto.subtle.importKey('raw', new TextEncoder().encode('hook-test'), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const rocketSignature = Buffer.from(await crypto.subtle.sign('HMAC', rocketKey, new TextEncoder().encode(rocketBody))).toString('hex');
    const rocketHook = (sig) => worker.fetch(new Request('https://relay.example/pay/xrocket', { method: 'POST', headers: { 'rocket-pay-signature': sig === undefined ? rocketSignature : sig }, body: rocketBody }), rocketEnv);
    rocketInvoice.status = 'paid';
    assert.equal((await rocketHook('f'.repeat(64))).status, 403, 'An xRocket webhook with a wrong signature is refused');
    assert.ok(!(await list()).includes('604'), 'and grants nothing');
    rocketInvoice.status = 'active';
    assert.equal((await rocketHook()).status, 200);
    assert.ok(!(await list()).includes('604'), 'A webhook alone grants nothing while the invoice is unpaid');
    rocketInvoice.status = 'paid';
    assert.equal((await rocketHook()).status, 200);
    assert.ok((await list()).includes('604'), 'A paid xRocket invoice grants the badge');
    assert.ok(owner.at(-1).text.includes('xRocket') && owner.at(-1).text.includes('3 USDT'));
    const rocketCron = await (await rocketPost('/badges/request', { id: '605', secret: 'h'.repeat(32) })).json();
    [...rocketInvoices.values()].find((item) => item.payload === rocketCron.code).activatedCount = 1;
    assert.equal(await checkBadgePayments(rocketEnv), 1, 'The scheduled check finds paid xRocket invoices too');
    const healthEnv = { ...rocketEnv, STATS_TOKEN: 'stats-test' };
    assert.equal((await worker.fetch(new Request('https://relay.example/badges/health'), healthEnv)).status, 403, 'Payment health needs the stats token');
    const health = await (await worker.fetch(new Request('https://relay.example/badges/health', { headers: { authorization: 'Bearer stats-test' } }), healthEnv)).json();
    assert.deepEqual([health.cryptobot.ok, health.cryptobot.app, health.xrocket.ok, health.xrocket.webhookToken, health.ton.ok, health.ton.rate, health.ton.quote], [true, 'AyuGram badges', true, true, true, 2.5, '1.2'], 'Payment health reports every method');
    assert.ok(!JSON.stringify(health).includes('1234:test') && !JSON.stringify(health).includes('rocket-test') && !JSON.stringify(health).includes('hook-test'), 'and never leaks a token');
    await worker.fetch(new Request('https://relay.example/tg/hook', { method: 'POST', headers: { 'x-telegram-bot-api-secret-token': 'h' }, body: JSON.stringify({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/pay' } }) }), healthEnv);
    assert.ok(owner.at(-1).text.includes('Crypto Bot: ✅') && owner.at(-1).text.includes('xRocket: ✅') && owner.at(-1).text.includes('1.2 TON'), 'The owner checks payments with /pay');
    shift += 10000;
    const tonOnly = { ...env, CRYPTOPAY_TOKEN: '' };
    const plain = await (await worker.fetch(new Request('https://relay.example/badges/request', { method: 'POST', body: JSON.stringify({ id: '603', secret: 'f'.repeat(32) }) }), tonOnly)).json();
    assert.equal(plain.pay.cryptobot, '', 'Without a Crypto Pay token there is no invoice');
    assert.equal(plain.pay.xrocket, '', 'and without an xRocket token no xRocket invoice');
    console.log('push relay: supporter badges unlock by themselves after Crypto Bot, xRocket and TON payments');
  } finally {
    globalThis.fetch = real;
    Date.now = realNow;
  }
}
await testAbuseLimits();
async function testAbuseLimits() {
  const data = new Map();
  const storage = {
    async get(k) { return data.get(k); },
    async put(k, v) { data.set(k, v); },
    async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
    async list({ prefix }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort()); },
  };
  const object = new Stats({ storage });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const env = { STATS, STATS_TOKEN: 'secret-token', PRO_API_KEY: 'x', GROQ_API_KEY: 'gsk_x' };
  assert.equal((await worker.fetch(new Request('https://relay.example/ai/pro', { method: 'POST', body: '{}' }), env)).status, 404, 'The paid assistant is off unless enabled');
  assert.equal((await worker.fetch(new Request('https://relay.example/ai/search?q=x'), env)).status, 404, 'The search debug endpoint needs the stats token');
  const from = (path, body, ip) => worker.fetch(new Request('https://relay.example' + path, { method: 'POST', headers: { 'cf-connecting-ip': ip }, body: JSON.stringify(body) }), env);
  const base = { build: 207601, variant: 'standard', source: 'sideload', status: 'official', team: 'OWN1234567', teamName: 'Me', bundle: 'ph.telegra.Telegraph.OWN1234567', os: '26.1', device: 'iPhone17,1' };
  for (let i = 0; i < 12; i += 1) {
    assert.equal((await from('/stats/ping', { ...base, id: 'flood-' + String(i).padStart(4, '0') }, '203.0.113.7')).status, 200);
  }
  assert.equal((await from('/stats/ping', { ...base, id: 'flood-0099' }, '203.0.113.7')).status, 429, 'One address cannot invent installs without end');
  assert.equal((await from('/stats/ping', { ...base, id: 'flood-0001' }, '203.0.113.7')).status, 200, 'Known installs keep pinging');
  assert.equal((await from('/stats/ping', { ...base, id: 'other-0001' }, '203.0.113.8')).status, 200, 'Other addresses are not affected');
  const real = globalThis.fetch;
  globalThis.fetch = async () => new Response('{"ok":true}');
  try {
    let accepted = 0;
    for (let i = 0; i < 12; i += 1) {
      const response = await from('/stats/report', { ...base, id: 'spam-' + String(i).padStart(4, '0'), text: 'spam ' + i }, '198.51.100.9');
      accepted += response.status === 200 ? 1 : 0;
    }
    assert.equal(accepted, 8, 'Changing the install id does not lift the report limit of one address');
    assert.ok(![...data.keys()].some((key) => key.includes('198.51.100.9')), 'Addresses are stored only as salted hashes');
  } finally {
    globalThis.fetch = real;
  }
  console.log('push relay: abuse limits hold per address and the paid assistant is off');
}
await testModerationSignature();
async function testModerationSignature() {
  const data = new Map();
  const storage = {
    async get(k) { return Array.isArray(k) ? new Map(k.filter((key) => data.has(key)).map((key) => [key, data.get(key)])) : data.get(k); },
    async put(k, v) { if (typeof k === 'object') { for (const [key, value] of Object.entries(k)) data.set(key, value); } else { data.set(k, v); } },
    async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
    async list({ prefix }) { return new Map([...data].filter(([k]) => k.startsWith(prefix)).sort()); },
  };
  const object = new Stats({ storage });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const kp = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify']);
  const pkcs8 = Buffer.from(new Uint8Array(await crypto.subtle.exportKey('pkcs8', kp.privateKey))).toString('base64');
  const rawPub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
  const pub = await crypto.subtle.importKey('raw', rawPub, 'Ed25519', true, ['verify']);
  const env = { STATS, STATS_TOKEN: 'secret-token', REPORT_BOT_TOKEN: '1:a', REPORT_CHAT_ID: '1272887902', REPORT_WEBHOOK_SECRET: 'h', MODERATION_KEY: pkcs8 };
  const id = 'install-sign-01';
  const status = (accounts) => worker.fetch(new Request('https://relay.example/stats/status', { method: 'POST', body: JSON.stringify({ id, accounts }) }), env).then((r) => r.json());
  const verify = (body) => {
    const message = new TextEncoder().encode('ayugram-mod|' + id + '|' + (body.banned ? 1 : 0) + '|' + (body.blocked ? 1 : 0) + '|' + body.ts);
    return crypto.subtle.verify('Ed25519', pub, Uint8Array.from(atob(body.sig), (ch) => ch.charCodeAt(0)), message);
  };

  const clean = await status([]);
  assert.ok(typeof clean.ts === 'number' && typeof clean.sig === 'string', 'A signed relay stamps ts and sig');
  assert.equal(await verify(clean), true, 'The raw public key verifies the relay signature the way the app will');

  const scammer = await accountHash('42');
  await object.fetch(new Request('https://stats.ayugram.invalid/ban-id/ban/42?reason=scam', { method: 'POST' }));
  const banned = await status([scammer]);
  assert.equal(banned.banned, true, 'The ban reaches the account');
  assert.equal(await verify(banned), true, 'A ban is signed over its own banned flag');
  const forged = { ...banned, banned: false };
  assert.equal(await verify(forged), false, 'Flipping banned to false breaks the signature');

  const noKey = await worker.fetch(new Request('https://relay.example/stats/status', { method: 'POST', body: JSON.stringify({ id, accounts: [] }) }), { STATS, STATS_TOKEN: 'secret-token' }).then((r) => r.json());
  assert.equal(noKey.sig, undefined, 'Without a key the response stays unsigned (backward compatible)');
  console.log('push relay: moderation responses are Ed25519-signed and verify with the raw public key');
}

await testProfiles();
async function testProfiles() {
  const memory = () => {
    const data = new Map();
    return {
      data,
      async get(k) { return Array.isArray(k) ? new Map(k.filter((key) => data.has(key)).map((key) => [key, data.get(key)])) : data.get(k); },
      async put(k, v) { if (typeof k === 'object') { for (const [key, value] of Object.entries(k)) data.set(key, value); } else { data.set(k, v); } },
      async delete(keys) { for (const k of [].concat(keys)) data.delete(k); },
      async list({ prefix, startAfter, limit }) { const all = [...data].filter(([k]) => k.startsWith(prefix) && (!startAfter || k > startAfter)).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)); return new Map(limit ? all.slice(0, limit) : all); },
    };
  };
  const statsObject = new Stats({ storage: memory() });
  const STATS = { idFromName(name) { return name; }, get() { return { fetch: (url, init) => statsObject.fetch(new Request(url, init)) }; } };
  const objects = new Map();
  const PROFILES = { idFromName(name) { return name; }, get(name) { if (!objects.has(name)) objects.set(name, new Profiles({ storage: memory() })); const object = objects.get(name); return { fetch: (url, init) => object.fetch(new Request(url, init)) }; } };
  const env = { STATS, PROFILES, STATS_TOKEN: 'admin-token', REPORT_BOT_TOKEN: '1:a', REPORT_CHAT_ID: '1272887902', REPORT_WEBHOOK_SECRET: 'h' };
  const telegram = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    const body = init && init.body;
    const method = String(url).split('/').pop();
    telegram.push({ method, form: body instanceof FormData ? body : null, json: typeof body === 'string' ? JSON.parse(body) : null });
    if (method === 'getMe') {
      return new Response(JSON.stringify({ ok: true, result: { id: 1, is_bot: true, username: 'AyuRelayBot' } }));
    }
    return new Response('{"ok":true}');
  };
  cacheStore.clear();
  try {
    const secret = 'p'.repeat(32);
    const thief = 't'.repeat(32);
    const auth = (id, key) => ({ 'x-ayugram-id': id, 'x-ayugram-secret': key || secret, 'cf-connecting-ip': '203.0.113.' + (Number(id) % 200) });
    const call = (path, init, target) => worker.fetch(new Request('https://relay.example' + path, init), target || env);
    const put = (id, body, key) => call('/profile', { method: 'PUT', headers: { ...auth(id, key), 'content-type': 'application/json' }, body: JSON.stringify(body) });
    const read = (ids, headers) => call('/profile?ids=' + ids, { headers: headers || {} });
    const upload = (id, bytes, type, extra) => call('/profile/background', { method: 'PUT', headers: { ...auth(id), 'content-type': type, 'content-length': String(bytes.length), ...(extra || {}) }, body: bytes });
    const be32 = (n) => new Uint8Array([(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255]);
    const box = (type, ...parts) => { const payload = concat(...parts); return concat(be32(payload.length + 8), enc.encode(type), payload); };
    const jpeg = (width, height, pad) => concat(new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 16]), enc.encode('JFIF\0'), new Uint8Array(9), new Uint8Array([0xff, 0xc0, 0, 17, 8, height >> 8, height & 255, width >> 8, width & 255, 3]), new Uint8Array(9), new Uint8Array(pad || 0), new Uint8Array([0xff, 0xd9]));
    const png = (width, height) => concat(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), be32(13), enc.encode('IHDR'), be32(width), be32(height), new Uint8Array([8, 6, 0, 0, 0]), new Uint8Array(4));
    const mp4 = (seconds, pad, brand) => {
      const mvhd = box('mvhd', new Uint8Array(12), be32(1000), be32(Math.round(seconds * 1000)), new Uint8Array(80));
      const matrix = concat(be32(0), be32(0x00010000), be32(0), be32(0xffff0000), be32(0), be32(0), be32(0), be32(0), be32(0x40000000));
      const tkhd = box('tkhd', new Uint8Array([0, 0, 0, 3]), new Uint8Array(36), matrix, be32(1920 * 65536), be32(1080 * 65536));
      return concat(box('ftyp', enc.encode(brand || 'isom'), be32(512), enc.encode('isomavc1')), box('moov', mvhd, box('trak', tkhd)), box('mdat', crypto.getRandomValues(new Uint8Array(Math.min(pad || 64, 65536))), new Uint8Array(Math.max((pad || 64) - 65536, 0))));
    };

    const hook = (update) => call('/tg/hook', { method: 'POST', headers: { 'x-telegram-bot-api-secret-token': 'h' }, body: JSON.stringify(update) });
    const startVerify = async (id, key) => {
      const response = await call('/profile/verify/start', { method: 'POST', headers: auth(id, key) });
      return { status: response.status, body: await response.json() };
    };
    const openLink = async (nonce, user, extra) => {
      telegram.length = 0;
      await hook({ update_id: 1, message: { message_id: 10, from: { id: Number(user), is_bot: false, first_name: 'U', ...(extra || {}) }, chat: { id: Number(user), type: 'private' }, text: '/start pv_' + nonce } });
      return telegram.find((item) => item.method === 'sendMessage');
    };
    const confirmLink = async (nonce, user) => {
      telegram.length = 0;
      await hook({ update_id: 2, callback_query: { id: 'cq', from: { id: Number(user), is_bot: false }, data: 'pv:' + nonce, message: { message_id: 11, chat: { id: Number(user), type: 'private' } } } });
      return telegram.find((item) => item.method === 'editMessageText');
    };
    const verifiedStatus = async (id, key) => (await (await call('/profile/verify/status', { headers: auth(id, key) })).json()).verified;
    const verify = async (id, key, user) => {
      const started = await startVerify(id, key);
      assert.equal(started.status, 200, 'verify start for ' + id);
      await openLink(started.body.nonce, user || id);
      return confirmLink(started.body.nonce, user || id);
    };

    assert.equal((await call('/profile?ids=1', {}, { STATS })).status, 503, 'Without the PROFILES binding the feature answers unavailable');
    assert.equal((await (await call('/profile?ids=1', {}, { STATS })).json()).error, 'unavailable');
    assert.equal((await call('/profile', { method: 'PUT', body: '{}' })).status, 401, 'Writes need an id and a secret');
    assert.equal((await put('500', { bubbles: true }, 'short')).status, 401, 'A short secret is refused');
    assert.equal((await read('500')).status, 200);
    assert.deepEqual((await (await read('500')).json()).items, [], 'Nobody has extras yet');

    const early = await put('500', { bubbles: true });
    assert.equal(early.status, 403, 'Writes need a verified owner');
    assert.deepEqual(await early.json(), { error: 'unverified', verifyUrl: '/profile/verify/start' });
    const earlyUpload = await call('/profile/background', { method: 'PUT', headers: { ...auth('500'), 'content-type': 'image/png' }, body: png(20, 20) });
    assert.equal((await earlyUpload.json()).error, 'unverified', 'and so do uploads');
    assert.equal((await call('/profile', { method: 'DELETE', headers: auth('500') })).status, 403, 'and deletes');
    const fresh = await (await call('/profile/me', { headers: auth('500') })).json();
    assert.equal(fresh.verified, false, '/profile/me tells the app it is not verified yet');
    assert.equal(fresh.claimed, false);
    assert.equal(await verifiedStatus('500'), false);
    assert.equal((await call('/profile/verify/start', { method: 'GET', headers: auth('500') })).status, 405);
    assert.equal((await call('/profile/verify/start', { method: 'POST' })).status, 401, 'Starting needs the auth headers');

    const first = await startVerify('500');
    assert.equal(first.status, 200);
    assert.match(first.body.nonce, /^[0-9a-f]{32}$/);
    assert.match(first.body.code, /^[A-Z2-9]{4}$/);
    assert.equal(first.body.url, 'https://t.me/AyuRelayBot?start=pv_' + first.body.nonce, 'The link opens the relay bot with the nonce');
    assert.ok(first.body.expiresAt > Date.now() + 590000 && first.body.expiresAt <= Date.now() + 600000, 'Links live ten minutes');
    assert.equal(telegram.filter((item) => item.method === 'getMe').length, 1, 'The bot name comes from getMe');
    await startVerify('501');
    assert.equal(telegram.filter((item) => item.method === 'getMe').length, 1, 'and is cached');
    const storedNonce = objects.get('global').state.storage.data.get('n:' + first.body.nonce);
    assert.equal(storedNonce.lock, await lockOf(secret), 'The nonce is bound to the secret hash');
    assert.equal(storedNonce.id, '500', 'and to the claimed id');

    const other = await openLink(first.body.nonce, '501');
    assert.match(other.json.text, /created for another Telegram account/, 'Another account gets a clear refusal');
    assert.equal(other.json.text.includes('500'), false, 'without the claimed id');
    assert.equal(other.json.reply_markup, undefined);
    assert.equal(await verifiedStatus('500'), false);
    const afterWrong = await openLink(first.body.nonce, '500');
    assert.match(afterWrong.json.text, /expired or was already used/, 'A link used by the wrong account is gone');

    const botTry = await startVerify('500');
    assert.match((await openLink(botTry.body.nonce, '500', { is_bot: true })).json.text, /another Telegram account/, 'Bots never verify');

    const stale = await startVerify('500');
    objects.get('global').state.storage.data.get('n:' + stale.body.nonce).expires = Date.now() - 1;
    assert.match((await openLink(stale.body.nonce, '500')).json.text, /expired/, 'Expired links are refused');
    assert.equal(objects.get('global').state.storage.data.has('n:' + stale.body.nonce), false, 'and deleted');
    assert.match((await openLink('f'.repeat(32), '500')).json.text, /expired/, 'Unknown links are refused');
    assert.match((await openLink('../x', '500')).json.text, /expired/, 'Malformed links are refused');

    const good = await startVerify('500');
    const ready = await openLink(good.body.nonce, '500');
    assert.ok(ready.json.text.includes(good.body.code), 'The bot shows the code from the app');
    assert.equal(ready.json.reply_markup.inline_keyboard[0][0].callback_data, 'pv:' + good.body.nonce, 'and asks to confirm');
    assert.equal(ready.json.chat_id, 500);
    assert.equal(await verifiedStatus('500'), false, 'Opening the link alone does not verify');
    const strangerTap = await confirmLink(good.body.nonce, '502');
    assert.match(strangerTap.json.text, /another Telegram account/, 'Only the claimed account can confirm');
    const good2 = await startVerify('500');
    await openLink(good2.body.nonce, '500');
    const done = await confirmLink(good2.body.nonce, '500');
    assert.match(done.json.text, /Done/, 'The owner confirms');
    assert.ok(telegram.some((item) => item.method === 'answerCallbackQuery'));
    assert.equal(await verifiedStatus('500'), true, 'and is verified');
    assert.equal(await verifiedStatus('500', thief), false, 'only for that secret');
    assert.match((await openLink(good2.body.nonce, '500')).json.text, /already used/, 'A used link cannot be reused');
    assert.match((await confirmLink(good2.body.nonce, '500')).json.text, /already used/, 'not even by tapping the old button');
    assert.equal((await (await call('/profile/me', { headers: auth('500') })).json()).verified, true);

    telegram.length = 0;
    await hook({ message: { message_id: 5, from: { id: 501 }, chat: { id: 501, type: 'private' }, text: '/bans' } });
    await hook({ message: { message_id: 6, from: { id: 501 }, chat: { id: 501, type: 'private' }, text: '/start' } });
    assert.equal(telegram.length, 0, 'Other messages from strangers are still ignored');

    let verifyLimited = 0;
    for (let i = 0; i < 12; i += 1) {
      verifyLimited += (await startVerify('520')).status === 429 ? 1 : 0;
    }
    assert.equal(verifyLimited, 2, 'Verification links are limited per account');
    let ipLimited = 0;
    for (let i = 0; i < 31; i += 1) {
      const response = await call('/profile/verify/start', { method: 'POST', headers: { ...auth(String(2000 + i)), 'cf-connecting-ip': '198.51.100.7' } });
      ipLimited += response.status === 429 ? 1 : 0;
    }
    assert.equal(ipLimited, 1, 'and per IP');

    let squatterLimited = 0;
    for (let i = 0; i < 11; i += 1) {
      squatterLimited += (await startVerify('530', thief)).status === 429 ? 1 : 0;
    }
    assert.equal(squatterLimited, 1, 'Another install burns only its own verification budget');
    assert.equal((await startVerify('530')).status, 200, 'so it cannot lock the real owner out of verifying');

    assert.equal(network('2001:db8:1:2:aaaa::1'), '2001:db8:1:2::/64');
    assert.equal(network('2001:0db8:0001:0002:ffff:0:0:9'), '2001:db8:1:2::/64', 'IPv6 addresses are grouped by /64');
    assert.equal(network('::ffff:198.51.100.9'), '198.51.100.9', 'IPv4-mapped addresses keep the IPv4 address');
    assert.equal(network('198.51.100.9'), '198.51.100.9');
    let v6Limited = 0;
    for (let i = 0; i < 31; i += 1) {
      const response = await call('/profile/verify/start', { method: 'POST', headers: { ...auth(String(3000 + i)), 'cf-connecting-ip': '2001:db8:77:1:' + (i + 1).toString(16) + '::1' } });
      v6Limited += response.status === 429 ? 1 : 0;
    }
    assert.equal(v6Limited, 1, 'Rotating addresses inside one IPv6 /64 does not escape the IP limit');

    const globalStore = objects.get('global').state.storage.data;
    const today = Math.floor(Date.now() / 86400000);
    globalStore.set('lim:va:all:' + today, 20000);
    assert.equal((await startVerify('540')).status, 429, 'A global daily cap bounds stored verification links');
    globalStore.delete('lim:va:all:' + today);

    const pendingSpam = await startVerify('550');
    globalStore.set('lim:vu:550:' + today, 40);
    assert.equal(await openLink(pendingSpam.body.nonce, '550'), undefined, 'A Telegram account over its daily attempt limit gets no replies');
    telegram.length = 0;
    await hook({ update_id: 3, callback_query: { id: 'cq', from: { id: 550, is_bot: false }, data: 'pv:' + pendingSpam.body.nonce, message: { message_id: 11, chat: { id: 550, type: 'private' } } } });
    assert.match(telegram.find((item) => item.method === 'answerCallbackQuery').json.text, /Too many attempts/, 'and a tap is answered with a short alert');
    assert.equal(telegram.some((item) => item.method === 'editMessageText'), false);
    assert.equal(await verifiedStatus('550'), false, 'without verifying');
    globalStore.delete('lim:vu:550:' + today);

    const sideways = await startVerify('560');
    telegram.length = 0;
    await hook({ update_id: 4, message: { message_id: 12, from: { id: 560, is_bot: false }, chat: { id: 560, type: 'private' }, forward_origin: { type: 'user', sender_user: { id: 1 } }, forward_date: 1, text: '/start pv_' + sideways.body.nonce } });
    await hook({ update_id: 5, message: { message_id: 13, from: { id: 560, is_bot: false }, chat: { id: -100123, type: 'private' }, text: '/start pv_' + sideways.body.nonce } });
    await hook({ update_id: 6, message: { message_id: 14, from: { id: 560, is_bot: false }, chat: { id: -100123, type: 'supergroup' }, text: '/start@AyuRelayBot pv_' + sideways.body.nonce } });
    assert.equal(telegram.length, 0, 'Forwarded links and links in groups are ignored');
    await hook({ update_id: 7, callback_query: { id: 'cq', from: { id: 560, is_bot: false }, data: 'pv:' + sideways.body.nonce, message: { message_id: 15, chat: { id: -100123, type: 'supergroup' } } } });
    await hook({ update_id: 8, callback_query: { id: 'cq', from: { id: 560, is_bot: false }, data: 'pv:' + sideways.body.nonce, inline_message_id: 'abc' } });
    assert.equal(await verifiedStatus('560'), false, 'A confirm tap outside the private chat with the bot never verifies');
    assert.ok(telegram.filter((item) => item.method === 'answerCallbackQuery').every((item) => /expired/.test(item.json.text)));
    assert.equal(globalStore.has('n:' + sideways.body.nonce), true, 'and does not spend the link');
    await openLink(sideways.body.nonce, '560');
    assert.match((await confirmLink(sideways.body.nonce, '560')).json.text, /Done/, 'which still works from the private chat');

    const racer = await startVerify('570');
    const racer2 = await startVerify('570', thief);
    await openLink(racer.body.nonce, '570');
    await openLink(racer2.body.nonce, '570');
    telegram.length = 0;
    await Promise.all([
      hook({ update_id: 9, callback_query: { id: 'a', from: { id: 570, is_bot: false }, data: 'pv:' + racer.body.nonce, message: { message_id: 16, chat: { id: 570, type: 'private' } } } }),
      hook({ update_id: 10, callback_query: { id: 'b', from: { id: 570, is_bot: false }, data: 'pv:' + racer.body.nonce, message: { message_id: 16, chat: { id: 570, type: 'private' } } } }),
    ]);
    assert.equal(telegram.filter((item) => item.method === 'editMessageText' && /Done/.test(item.json.text)).length, 1, 'Two taps on the same link verify once');
    assert.equal(await verifiedStatus('570'), true);
    assert.equal(await verifiedStatus('570', thief), false, 'and an unconfirmed second link changes nothing');

    for (let i = 0; i < 2100; i += 1) {
      globalStore.set('lim:old:' + i + ':' + (today - 1), 1);
    }
    for (let i = 0; i < 300; i += 1) {
      globalStore.set('n:' + i.toString(16).padStart(32, '0'), { id: '1', lock: 'x', code: 'AAAA', expires: Date.now() - 1, time: 0 });
    }
    const liveNonce = (await startVerify('580')).body.nonce;
    globalStore.set('limday', today - 1);
    await startVerify('581');
    assert.ok([...globalStore.keys()].some((key) => key.startsWith('lim:old:')), 'The daily cleanup works in bounded steps');
    assert.ok(globalStore.get('sweep'), 'and remembers where it stopped');
    await startVerify('582');
    await startVerify('583');
    assert.equal([...globalStore.keys()].filter((key) => key.startsWith('lim:old:')).length, 0, 'Old counters are swept');
    assert.equal([...globalStore.keys()].filter((key) => /^n:0{20}/.test(key)).length, 0, 'and expired links too');
    assert.equal(globalStore.has('n:' + liveNonce), true, 'Live links survive the sweep');
    assert.equal(globalStore.get('limday'), today);
    assert.equal(globalStore.has('sweep'), false);

    const nfts = [
      { slug: 'PlushPepe-1', pinned: true },
      { collection: ' Durov’s <Cap>‮ ', model: 'Gold\u0000', backdrop: 'Midnight Blue', pattern: 'Stars', number: 77, pinned: true, colors: { center: 'aabbcc', edge: '112233', text: 'zz' } },
      { slug: 'plushpepe-1', pinned: false },
      ...Array.from({ length: 6 }, (_, i) => ({ slug: 'SnoopDogg-' + (i + 1), pinned: true })),
    ];
    const saved = await put('500', { nfts, usernames: ['@Cool_Name', 'cool_name', 'abcd'], bubbles: true });
    assert.equal(saved.status, 200);
    const own = await saved.json();
    assert.equal(own.fake, true);
    assert.equal(own.claimed, true);
    assert.equal(own.nfts.length, 8, 'Duplicate slugs are dropped');
    assert.deepEqual(own.nfts[0], { slug: 'PlushPepe-1', pinned: true });
    assert.deepEqual(own.nfts[1], { collection: 'Durov’s Cap', model: 'Gold', backdrop: 'Midnight Blue', pattern: 'Stars', number: 77, pinned: true, colors: { center: 'AABBCC', edge: '112233' } }, 'Labels are sanitized');
    assert.equal(own.nfts.filter((nft) => nft.pinned).length, 6, 'At most six NFTs stay pinned');
    assert.deepEqual(own.usernames, ['cool_name', 'abcd'], 'Usernames are stored lowercase without duplicates');
    assert.equal(own.bubbles, true);
    assert.equal(own.limits.nfts, 30);

    const refusals = [
      [{ usernames: ['abc'] }, 'bad_username'],
      [{ usernames: ['bad-name'] }, 'bad_username'],
      [{ usernames: ['real_telegram_team'] }, 'reserved_username'],
      [{ usernames: ['Durov'] }, 'reserved_username'],
      [{ usernames: Array.from({ length: 11 }, (_, i) => 'name_' + i) }, 'too_many_usernames'],
      [{ nfts: Array.from({ length: 31 }, (_, i) => ({ slug: 'PlushPepe-' + (i + 1) })) }, 'too_many_nfts'],
      [{ nfts: [{ slug: 'Plush Pepe-1' }] }, 'bad_nft'],
      [{ nfts: [{ collection: 'Cap', number: 0 }] }, 'bad_nft'],
      [{ bubbles: 'yes' }, 'bad_bubbles'],
      [{ background: { url: 'https://evil.example/x.mp4' } }, 'bad_background'],
      [{ other: 1 }, 'bad_request'],
    ];
    for (const [body, code] of refusals) {
      const response = await put('500', body);
      assert.equal(response.status, 400, code);
      assert.equal((await response.json()).error, code);
    }
    const big = await call('/profile', { method: 'PUT', headers: auth('500'), body: JSON.stringify({ nfts: [], pad: 'x'.repeat(17000) }) });
    assert.equal(big.status, 413, 'Large JSON bodies are refused');

    const stolen = await put('500', { usernames: ['stolen_name'] }, thief);
    assert.equal(stolen.status, 403, 'Another install cannot change a verified profile');
    assert.equal((await stolen.json()).error, 'unverified');
    const thiefMe = await (await call('/profile/me', { headers: auth('500', thief) })).json();
    assert.deepEqual([thiefMe.claimed, thiefMe.verified, thiefMe.usernames], [false, false, []], 'and never sees the owner data');

    const listed = await read('500,501,500');
    assert.equal(listed.headers.get('cache-control'), 'public, max-age=60');
    const items = (await listed.json()).items;
    assert.equal(items.length, 1, 'Only people with extras are listed');
    assert.equal(items[0].id, '500');
    assert.equal(items[0].fake, true, 'Every public entry is marked fake');
    assert.equal(items[0].lock, undefined, 'The lock never leaves the relay');
    const etag = (await read('500,501')).headers.get('etag');
    assert.equal((await read('500,501', { 'if-none-match': etag })).status, 304, 'Unchanged batches answer 304');
    assert.equal((await put('500', { usernames: ['fresh_name'] })).status, 200);
    assert.deepEqual((await (await read('500')).json()).items[0].usernames, ['fresh_name'], 'A write clears the cached entry');
    assert.equal((await read(Array.from({ length: 51 }, (_, i) => String(i + 1)).join(','))).status, 400, 'At most 50 ids per request');
    assert.equal((await (await read('0,abc')).json()).error, 'bad_ids');

    const photo = jpeg(1170, 2532, 1000);
    telegram.length = 0;
    const uploaded = await upload('500', photo, 'image/jpeg');
    assert.equal(uploaded.status, 200);
    const withPhoto = await uploaded.json();
    assert.equal(withPhoto.background.type, 'photo');
    assert.equal(withPhoto.background.width, 1170, 'Photo size comes from the file');
    assert.equal(withPhoto.background.height, 2532);
    assert.equal(withPhoto.background.mime, 'image/jpeg');
    assert.match(withPhoto.background.url, /^https:\/\/relay\.example\/profile\/media\/500\/[0-9a-f]{16}\.jpg$/);
    assert.equal(telegram[0].method, 'sendPhoto', 'The owner sees every new background');
    assert.ok(telegram[0].form.get('reply_markup').includes('P:500'), 'with a button to delete it');
    const mediaPath = new URL(withPhoto.background.url).pathname;
    const served = await call(mediaPath, {});
    assert.equal(served.status, 200);
    assert.equal(served.headers.get('content-type'), 'image/jpeg');
    assert.equal(served.headers.get('cache-control'), 'public, max-age=31536000, immutable');
    assert.deepEqual(new Uint8Array(await served.arrayBuffer()), photo, 'The stored photo is served byte for byte');
    const cached = await call(mediaPath, {});
    assert.deepEqual(new Uint8Array(await cached.arrayBuffer()), photo, 'and again from the edge cache');
    const part = await call(mediaPath, { headers: { range: 'bytes=0-1' } });
    assert.equal(part.status, 206, 'Byte ranges work for players');
    assert.equal(part.headers.get('content-range'), 'bytes 0-1/' + photo.length);
    assert.deepEqual(new Uint8Array(await part.arrayBuffer()), photo.slice(0, 2));
    assert.equal((await call(mediaPath, { headers: { range: 'bytes=99999-' } })).status, 416);
    assert.equal((await call(mediaPath, { headers: { 'if-none-match': served.headers.get('etag') } })).status, 304);
    assert.equal((await call(mediaPath, { method: 'HEAD' })).headers.get('content-length'), String(photo.length));
    assert.equal((await (await read('500')).json()).items[0].background.url, withPhoto.background.url, 'Everyone sees the background');

    assert.equal((await upload('500', photo, 'text/plain')).status, 415, 'Unknown types are refused');
    assert.equal((await upload('500', photo, 'video/mp4')).status, 415, 'A photo cannot pose as a video');
    assert.equal((await upload('500', enc.encode('<html><script>x</script></html>'), 'image/png')).status, 415, 'Content is sniffed, not trusted');
    assert.equal((await upload('500', jpeg(10, 10, 1572864), 'image/jpeg')).status, 413, 'Photos stop at 1.5 MB');
    assert.equal((await call('/profile/background', { method: 'PUT', headers: { ...auth('500'), 'content-type': 'video/mp4', 'content-length': String(9 * 1024 * 1024) }, body: new Uint8Array(16) })).status, 413, 'A declared oversize video is refused before reading');
    const pngShot = await (await upload('500', png(640, 480), 'image/png')).json();
    assert.equal(pngShot.background.width, 640);
    assert.equal(pngShot.background.mime, 'image/png');
    assert.equal((await call(mediaPath, {})).status, 404, 'A replaced background is gone');

    const longClip = await upload('500', mp4(20, 256), 'video/mp4');
    assert.equal(longClip.status, 422, 'Videos longer than 15 seconds are refused');
    assert.equal((await longClip.json()).error, 'too_long');
    const clip = mp4(10, 3 * 1024 * 1024 + 5);
    const video = await (await upload('500', clip, 'video/mp4')).json();
    assert.equal(video.background.type, 'video');
    assert.equal(video.background.duration, 10);
    assert.deepEqual([video.background.width, video.background.height], [1080, 1920], 'Rotated video size is reported upright');
    const clipVersion = /\/([0-9a-f]{16})\.mp4$/.exec(video.background.url)[1];
    assert.equal(objects.get('media-500').state.storage.data.get('m:' + clipVersion).chunks, 4, 'Large media is split into chunks');
    assert.equal([...objects.get('media-500').state.storage.data.keys()].filter((key) => key.startsWith('m:')).length, 1, 'Replaced versions are deleted');
    assert.equal(objects.get('global').state.storage.data.get('bytes'), clip.length, 'Stored media bytes are counted');
    const clipServed = new Uint8Array(await (await call(new URL(video.background.url).pathname, {})).arrayBuffer());
    assert.equal(createHash('sha256').update(clipServed).digest('hex'), createHash('sha256').update(clip).digest('hex'), 'The chunked video comes back intact');
    const mov = await (await upload('500', mp4(5, 64, 'qt  '), 'video/quicktime')).json();
    assert.match(mov.background.url, /\.mov$/);
    assert.equal((await upload('500', mp4(5, 8 * 1024 * 1024), 'video/mp4')).status, 413, 'Videos stop at 8 MB');

    const removed = await call('/profile/background', { method: 'DELETE', headers: auth('500') });
    assert.equal((await removed.json()).background, null);
    assert.equal((await call(new URL(mov.background.url).pathname, {})).status, 404, 'A deleted background is no longer served');
    assert.equal(objects.get('media-500').state.storage.data.size, 0, 'and its bytes are deleted');
    assert.equal(objects.get('global').state.storage.data.get('bytes'), 0, 'and uncounted');

    const served2 = await call(new URL((await (await upload('500', png(32, 32), 'image/png')).json()).background.url).pathname, {});
    assert.equal(served2.headers.get('x-content-type-options'), 'nosniff');
    assert.match(served2.headers.get('content-security-policy'), /sandbox/, 'Media can never run as a page');
    const fragmented = concat(mp4(5, 64), box('moof', new Uint8Array(8)));
    assert.equal((await upload('500', fragmented, 'video/mp4')).status, 422, 'Fragmented videos cannot hide their length');
    const hiddenLength = concat(box('ftyp', enc.encode('isom'), be32(512)), box('moov', box('mvhd', new Uint8Array(12), be32(1000), be32(5000), new Uint8Array(80)), box('trak', box('mdia', box('mdhd', new Uint8Array(12), be32(600), be32(600 * 60), new Uint8Array(4))))), box('mdat', new Uint8Array(64)));
    assert.equal(inspectMedia(hiddenLength, 'video', {}).error, 'too_long', 'A track longer than the movie header is caught');
    assert.equal(inspectMedia(concat(box('ftyp', enc.encode('isom'), be32(512)), box('mdat', new Uint8Array(64))), 'video', {}).error, 'bad_media', 'A video without a duration is refused');
    const streamed = await call('/profile/background', { method: 'PUT', duplex: 'half', headers: { ...auth('500'), 'content-type': 'image/png' }, body: new ReadableStream({ start(controller) { for (let i = 0; i < 4; i += 1) controller.enqueue(new Uint8Array(512 * 1024)); controller.close(); } }) });
    assert.equal(streamed.status, 413, 'A body without a length still stops at the limit');
    const thiefUpload = await call('/profile/background', { method: 'PUT', headers: { ...auth('500', thief), 'content-type': 'image/png' }, body: png(20, 20) });
    assert.equal((await thiefUpload.json()).error, 'unverified', 'Another install cannot upload a background');
    const budgetBefore = objects.get('global').state.storage.data.get('bytes');
    objects.get('global').state.storage.data.set('bytes', 3221225472);
    const full = await upload('500', jpeg(24, 24, 4096), 'image/jpeg');
    assert.equal(full.status, 507, 'Uploads stop when the media budget is spent');
    assert.equal((await full.json()).error, 'storage_full');
    objects.get('global').state.storage.data.set('bytes', budgetBefore);

    let limited = 0;
    for (let i = 0; i < 5; i += 1) {
      limited += (await upload('500', png(10 + i, 10), 'image/png')).status === 429 ? 1 : 0;
    }
    assert.equal(limited, 2, 'Uploads are limited to eight per account per day');

    const thiefLock = await lockOf(thief);
    const second = 's'.repeat(32);
    await statsObject.fetch(new Request('https://stats.ayugram.invalid/badge-grant-id/600', { method: 'POST' }));
    await call('/badges/set', { method: 'POST', body: JSON.stringify({ id: '600', secret, badge: {} }) });
    assert.equal((await put('600', { bubbles: true }, thief)).status, 403, 'A supporter id cannot be claimed by another install');
    assert.equal((await put('600', { bubbles: true })).status, 403, 'The badge key alone is not ownership');
    await verify('600', second);
    assert.equal((await put('600', { bubbles: true }, second)).status, 200, 'The verified owner always wins over the badge lock');
    assert.equal((await put('600', { bubbles: true })).status, 403);

    const globalData = objects.get('global').state.storage.data;
    globalData.set('p:700', { lock: thiefLock, nfts: [], usernames: ['squatter'], bubbles: true, background: null, updatedAt: 1, claimedAt: 1 });
    assert.deepEqual((await (await read('700')).json()).items, [], 'Unverified leftovers are never shown');
    assert.equal((await put('700', { usernames: ['squatter_two'] }, thief)).status, 403, 'and the squatter cannot touch them');
    await verify('700');
    assert.equal(globalData.get('p:700'), undefined, 'Verifying wipes a squatter');
    const reclaimed = await (await put('700', { bubbles: true })).json();
    assert.deepEqual(reclaimed.usernames, [], 'and the owner starts clean');
    assert.equal((await put('700', { bubbles: false }, thief)).status, 403);

    globalData.set('v:750', { lock: thiefLock, time: 1 });
    const squat = await call('/profile/background', { method: 'PUT', headers: { ...auth('750', thief), 'content-type': 'image/png' }, body: png(50, 50) });
    const squatUrl = (await squat.json()).background.url;
    globalData.delete('v:750');
    const bytesBeforeSquatWipe = globalData.get('bytes');
    await verify('750');
    assert.deepEqual((await (await read('750')).json()).items, [], 'The verified owner replaces a squatter with a background');
    assert.equal((await call(new URL(squatUrl).pathname, {})).status, 404, 'and the squatter media is gone');
    assert.equal(objects.get('media-750').state.storage.data.size, 0);
    assert.equal(globalData.get('bytes'), bytesBeforeSquatWipe - png(50, 50).length, 'and uncounted');
    assert.equal((await call('/profile/background', { method: 'DELETE', headers: auth('750') })).status, 200);

    await verify('760');
    await put('760', { usernames: ['moving_name'] });
    await verify('760', second);
    assert.deepEqual((await (await put('760', { bubbles: true }, second)).json()).usernames, ['moving_name'], 'Verifying a new install of the same account keeps the extras');
    assert.equal((await put('760', { bubbles: false })).status, 403, 'and the old install loses write access');
    assert.deepEqual((await (await read('760')).json()).items[0].usernames, ['moving_name']);
    await call('/profile', { method: 'DELETE', headers: auth('760', second) });

    await statsObject.fetch(new Request('https://stats.ayugram.invalid/ban-id/ban/800?reason=scam', { method: 'POST' }));
    const banned = await put('800', { bubbles: true });
    assert.equal(banned.status, 403);
    assert.equal((await banned.json()).error, 'banned', 'Banned accounts cannot set extras');

    assert.equal((await call('/profile/admin/500', { method: 'DELETE' })).status, 403, 'Admin calls need the token');
    assert.equal((await put('500', { bubbles: true })).status, 200);
    const wiped = await call('/profile/admin/500', { method: 'DELETE', headers: { authorization: 'Bearer admin-token' } });
    assert.equal((await wiped.json()).existed, true);
    assert.deepEqual((await (await read('500')).json()).items, [], 'The admin wipe removes the extras');
    assert.equal((await put('500', { bubbles: true }, thief)).status, 403, 'A wipe does not free the id for others');
    assert.equal((await put('500', { bubbles: true })).status, 200, 'The verified owner can start again');
    await hook({ callback_query: { id: 'q', from: { id: 1272887902 }, data: 'J:500', message: { message_id: 3, chat: { id: 1272887902 } } } });
    assert.deepEqual((await (await read('500')).json()).items, [], 'The bot button wipes the profile');
    const blocked = await put('500', { bubbles: true }, thief);
    assert.equal((await blocked.json()).error, 'blocked', 'and blocks new extras');
    await hook({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/reprofile 500' } });
    assert.equal((await put('500', { bubbles: true })).status, 200, '/reprofile lifts the block');
    await hook({ message: { from: { id: 1272887902 }, chat: { id: 1272887902 }, text: '/unprofile 500' } });
    assert.equal((await put('500', { bubbles: true })).status, 403, '/unprofile blocks again');

    assert.equal((await call('/profile', { method: 'DELETE', headers: auth('700') })).status, 200);
    assert.deepEqual((await (await read('700')).json()).items, [], 'Owners can delete their own extras');
    const me = await (await call('/profile/me', { headers: auth('700') })).json();
    assert.equal(me.claimed, true, 'and keep the claim');

    assert.equal(objects.get('global').state.storage.data.get('bytes'), 0, 'Every removal path returns its bytes to the budget');
    const noStats = { PROFILES };
    await verify('900');
    await verify('910');
    assert.equal((await call('/profile', { method: 'PUT', headers: auth('900'), body: JSON.stringify({ bubbles: true }) }, noStats)).status, 200, 'Profiles work without the stats object');
    await Promise.all([upload('910', png(40, 40), 'image/png'), upload('910', jpeg(40, 40, 64), 'image/jpeg'), upload('910', png(41, 41), 'image/png')]);
    const raced = (await (await read('910')).json()).items[0].background;
    assert.equal((await call(new URL(raced.url).pathname, {})).status, 200, 'Concurrent uploads never leave a background pointing at deleted bytes');
    assert.equal([...objects.get('media-910').state.storage.data.keys()].filter((key) => key.startsWith('m:')).length, 1, 'and keep only the winning version');
    assert.equal(cleanNfts([{ slug: 'A-1' }]).error, 'bad_nft');
    assert.equal(cleanUsernames(['ok_name']).value[0], 'ok_name');
    assert.equal(inspectMedia(mp4(14.9), 'video', {}).duration, 14.9);
    assert.equal(inspectMedia(jpeg(100, 200), 'photo', { width: '200', height: '100' }).width, 200, 'EXIF-rotated photos keep the size the app reports');
    console.log('push relay: profile extras need Telegram-verified ownership, are validated, served to everyone and moderated');
  } finally {
    globalThis.fetch = real;
  }
}
