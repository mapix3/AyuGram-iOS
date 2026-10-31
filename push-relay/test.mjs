// node push-relay/test.mjs — encrypts Web Push payloads like a push service and checks the relay.
import assert from 'node:assert/strict';
import { webcrypto as crypto } from 'node:crypto';
import worker, { base64urlEncode, describe, sendToBark, chatTarget, seenUpdate, alreadySeen, Presence, activityId } from './worker.js';

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
  assert.equal(sent[0].body.url, 'ayugram://chat?user=7');
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
        objects.set(id, new Presence({ storage: { async get(k) { return data.get(k); }, async put(k, v) { data.set(k, v); } } }));
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
  const other = await subscription('ACTIVEKEY1');
  const { body, headers } = await encryptAes128gcm(other, JSON.stringify({ loc_key: 'MESSAGE_TEXT', loc_args: ['Ann', 'hi'], custom: { from_id: '70', msg_id: '2' } }));
  await worker.fetch(new Request('https://relay.example/p/' + other.token, { method: 'POST', body, headers }), activeEnv);
  assert.equal(sent.length, 1, 'The same message from a second subscription is not shown twice');
  await push('3');
  assert.equal(sent.length, 2, 'The next message is shown');
  assert.equal((await worker.fetch(new Request('https://relay.example/active/bad', { method: 'POST', body: '90' }), activeEnv)).status, 400);
}
console.log('push relay: aes128gcm and aesgcm pushes reach Bark');
