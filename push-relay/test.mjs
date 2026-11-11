// node push-relay/test.mjs — encrypts Web Push payloads like a push service and checks the relay.
import assert from 'node:assert/strict';
import { webcrypto as crypto, createHash } from 'node:crypto';
import { accountHash } from './stats.js';
import worker, { base64urlEncode, describe, sendToBark, chatTarget, seenUpdate, alreadySeen, Presence, activityId, Stats, stashRecord } from './worker.js';

const cacheStore = new Map();
globalThis.caches = { default: {
  async match(request) { return cacheStore.has(request.url) ? new Response(cacheStore.get(request.url)) : undefined; },
  async put(request, response) { cacheStore.set(request.url, await response.text()); },
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
  } finally {
    globalThis.fetch = realFetch2;
  }
}
console.log('push relay: aes128gcm and aesgcm pushes reach Bark');
