// node push-relay/test.mjs — encrypts Web Push payloads like a push service and checks the relay.
import assert from 'node:assert/strict';
import { webcrypto as crypto } from 'node:crypto';
import worker, { base64urlEncode, describe, sendToBark } from './worker.js';

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
  const response = await worker.fetch(new Request('https://relay.example/p/' + sub.token, { method: 'POST', body, headers }));
  assert.equal(response.status, 201);
  assert.equal(sent.length, 1, encrypt.name);
  assert.equal(sent[0].body.device_key, 'BARKKEY123');
  assert.equal(sent[0].body.title, 'Alice');
  assert.equal(sent[0].body.body, 'привет');
}
assert.deepEqual(describe({ title: 'Bob', description: 'hi' }), { title: 'Bob', text: 'hi' });
assert.deepEqual(describe({}), { title: 'AyuGram', text: 'New message' });
assert.deepEqual(describe({ loc_key: 'CHAT_MESSAGE_TEXT', loc_args: ['Alice', 'Friends', 'hi all'] }), { title: 'Friends', text: 'Alice: hi all' });
assert.deepEqual(describe({ loc_key: 'CHANNEL_MESSAGE_PHOTO', loc_args: ['News'] }), { title: 'News', text: '📷 Photo' });
assert.deepEqual(describe({ loc_key: 'MESSAGE_AUDIO', loc_args: ['Bob'] }), { title: 'Bob', text: '🎤 Voice message' });
assert.deepEqual(describe({ loc_key: 'MESSAGE_STICKER', loc_args: ['Bob', '😀'] }), { title: 'Bob', text: '😀 Sticker' });
assert.deepEqual(describe({ loc_key: 'CHAT_MESSAGE_POLL', loc_args: ['Bob', 'Team', 'Lunch?'] }), { title: 'Team', text: 'Bob: 📊 Poll: Lunch?' });
assert.deepEqual(describe({ loc_key: 'PINNED_TEXT', loc_args: ['Bob', 'rules'] }), { title: 'Bob', text: '📌 rules' });
assert.equal(describe({ loc_key: 'READ_HISTORY', loc_args: [] }), null);
assert.equal(describe({ loc_key: '', custom: {} }), null);
sent.length = 0;
refuseJson = true;
const fallback = await sendToBark('KEY1234567', 'Ann', 'hi / there');
assert.ok(fallback.ok, 'The path API is tried when the JSON API refuses');
assert.equal(sent.length, 2);
assert.ok(sent[1].url.startsWith('https://api.day.app/KEY1234567/Ann/hi%20%2F%20there?'), sent[1].url);
refuseJson = false;
sent.length = 0;
const test = await worker.fetch(new Request('https://relay.example/test/KEY1234567'));
assert.equal(test.status, 200);
assert.equal(sent[0].body.device_key, 'KEY1234567');
const bad = await worker.fetch(new Request('https://relay.example/p/xx', { method: 'POST', body: 'x' }));
assert.equal(bad.status, 400);
console.log('push relay: aes128gcm and aesgcm pushes reach Bark');
