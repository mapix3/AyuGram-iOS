import { inspectMedia, marketIdentity, sniffMedia, network } from './profile.js';
import { ipTag } from './stats.js';
import { PLUGIN_PERMISSIONS, aiReview, compareVersions, scanPlugin, scanSummary, unpackPlugin } from './scan.js';

export const MARKET_HOST = 'marketplace.mapixdev.com';
export const MARKET_LIMITS = { file: 2097152, photo: 5242880, video: 20971520, media: 4, body: 27262976, name: 60, description: 300, about: 4000, changelog: 1000 };

const INTERNAL = 'https://market.ayugram.invalid';
const CHUNK = 1048576;
const BUDGET = 4294967296;
const SUBMITS_PER_ID = 6;
const SUBMITS_PER_IP = 12;
const LIVE_PER_AUTHOR = 30;
const REJECTED_TTL = 7 * 86400000;
const SCANS_PER_MINUTE = 20;
const SID = /^[0-9a-f]{16}$/;
const BID = /^[0-9a-f]{16}$/;
const SLUG = /^[a-z0-9][a-z0-9._-]{0,46}[a-z0-9]$/;
const USERNAME = /^[A-Za-z][A-Za-z0-9_]{3,31}$/;
const MEDIA_EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/heic': 'heic', 'video/mp4': 'mp4', 'video/quicktime': 'mov' };
const REJECT_REASONS = [['malware', 'Вредоносный или опасный код'], ['broken', 'Не работает'], ['spam', 'Спам или реклама'], ['dup', 'Дубликат'], ['media', 'Нет нормальной демонстрации'], ['rules', 'Нарушает правила']];
const REASON_TEXT = {
  malware: ['The plugin contains dangerous code', 'В плагине найден опасный код'],
  broken: ['The plugin does not work', 'Плагин не работает'],
  spam: ['Spam or advertising', 'Спам или реклама'],
  dup: ['A duplicate of an existing plugin', 'Дубликат существующего плагина'],
  media: ['The photos or videos do not show the plugin working', 'Фото или видео не показывают работу плагина'],
  rules: ['The plugin breaks the marketplace rules', 'Плагин нарушает правила маркетплейса'],
  auto: ['The automatic check found dangerous code', 'Автопроверка нашла опасный код'],
};
const PERMISSION_TEXT = {
  'messages.read': ['Read messages', 'Читать сообщения'],
  'messages.send': ['Send messages', 'Отправлять сообщения'],
  'messages.intercept': ['Change or block outgoing messages', 'Менять и блокировать исходящие'],
  'account.basic': ['See your name and ID', 'Видеть ваше имя и ID'],
  'ui.inject': ['Add menu items and dialogs', 'Добавлять пункты меню и окна'],
  'network.client': ['Access the internet', 'Ходить в интернет'],
  notifications: ['Show notifications', 'Показывать уведомления'],
};
const scanBuckets = new Map();
const downloadSeen = new Map();

function fail(error, status, extra) {
  return Response.json({ error, ...(extra || {}) }, { status, headers: { 'cache-control': 'no-store' } });
}

function ok(value) {
  return Response.json(value, { headers: { 'cache-control': 'no-store' } });
}

function randomHex(size) {
  return [...crypto.getRandomValues(new Uint8Array(size))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

async function sha256(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map((byte) => byte.toString(16).padStart(2, '0')).join('');
}

function day(now) {
  return Math.floor(now / 86400000);
}

function clean(value, limit) {
  return typeof value === 'string' ? value.replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f‪-‮⁦-⁩]/g, '').trim().slice(0, limit) : '';
}

function line(value, limit) {
  return clean(value, limit).replace(/\s+/g, ' ');
}

export function marketStub(env) {
  return env && env.MARKET ? env.MARKET.get(env.MARKET.idFromName('market')) : null;
}

function call(stub, path, body) {
  return stub.fetch(INTERNAL + path, { method: 'POST', body: JSON.stringify(body || {}) });
}

async function callJson(stub, path, body) {
  const response = await call(stub, path, body);
  const data = await response.json().catch(() => ({}));
  return { status: response.status, ok: response.ok, data };
}

export class Market {
  constructor(state) {
    this.state = state;
    this.queue = Promise.resolve();
  }

  serial(work) {
    const run = this.queue.then(work);
    this.queue = run.catch(() => null);
    return run;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const storage = this.state.storage;
    if (url.pathname === '/blob-put') {
      const id = request.headers.get('x-id') || '';
      const mime = request.headers.get('x-mime') || '';
      const bytes = new Uint8Array(await request.arrayBuffer());
      if (!BID.test(id) || !mime || !bytes.length || bytes.length > MARKET_LIMITS.video) {
        return fail('bad_request', 400);
      }
      return this.serial(async () => {
        const total = (await storage.get('bytes')) || 0;
        if (total + bytes.length > BUDGET) {
          return fail('storage_full', 507);
        }
        const chunks = Math.ceil(bytes.length / CHUNK);
        for (let index = 0; index < chunks; index += 1) {
          await storage.put('bc:' + id + ':' + index, bytes.slice(index * CHUNK, (index + 1) * CHUNK).buffer);
        }
        await storage.put({ ['bm:' + id]: { mime, size: bytes.length, chunks, time: Date.now() }, bytes: total + bytes.length });
        return ok({ ok: true });
      });
    }
    if (url.pathname === '/blob-get') {
      const id = url.searchParams.get('id') || '';
      const meta = BID.test(id) ? await storage.get('bm:' + id) : null;
      if (!meta) {
        return fail('not_found', 404);
      }
      const keys = Array.from({ length: meta.chunks }, (_, index) => 'bc:' + id + ':' + index);
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
      return new Response(out, { headers: { 'content-type': meta.mime } });
    }
    const input = await request.json().catch(() => ({}));
    if (['/list', '/plugin', '/author', '/mine', '/submission', '/pending'].includes(url.pathname)) {
      return this.read(url.pathname, input, Date.now());
    }
    return this.serial(() => this.write(url.pathname, input, Date.now()));
  }

  async dropBlobs(ids) {
    const storage = this.state.storage;
    let freed = 0;
    for (const id of new Set(ids.filter((value) => BID.test(value)))) {
      const meta = await storage.get('bm:' + id);
      if (!meta) {
        continue;
      }
      await storage.delete(Array.from({ length: meta.chunks }, (_, index) => 'bc:' + id + ':' + index).concat('bm:' + id));
      freed += meta.size;
    }
    if (freed) {
      await storage.put('bytes', Math.max(0, ((await storage.get('bytes')) || 0) - freed));
    }
  }

  blobsOf(sub) {
    return [sub.file && sub.file.bid, ...(sub.media || []).map((item) => item.bid)].filter(Boolean);
  }

  async liveBlobs(slug) {
    const plugin = await this.state.storage.get('p:' + slug);
    const set = new Set();
    if (plugin && plugin.current) {
      set.add(plugin.current.file.bid);
    }
    for (const item of (plugin && plugin.media) || []) {
      set.add(item.bid);
    }
    return set;
  }

  async releaseSubmission(sub) {
    const keep = await this.liveBlobs(sub.slug);
    await this.dropBlobs(this.blobsOf(sub).filter((id) => !keep.has(id)));
  }

  async allow(keys, now) {
    const storage = this.state.storage;
    const today = day(now);
    const names = keys.map(([scope, key]) => 'rl:' + today + ':' + scope + ':' + key);
    const found = await storage.get(names);
    for (let i = 0; i < keys.length; i += 1) {
      if ((found.get(names[i]) || 0) >= keys[i][2]) {
        return false;
      }
    }
    await storage.put(Object.fromEntries(names.map((name) => [name, (found.get(name) || 0) + 1])));
    const stale = [...(await storage.list({ prefix: 'rl:', limit: 200 })).keys()].filter((name) => Number(name.split(':')[1]) < today);
    if (stale.length) {
      await storage.delete(stale);
    }
    return true;
  }

  async read(path, input, now) {
    const storage = this.state.storage;
    if (path === '/list') {
      const all = [...(await storage.list({ prefix: 'p:' })).values()].filter((plugin) => plugin.status === 'live' && plugin.current);
      const query = line(input.q, 80).toLowerCase();
      const filtered = query ? all.filter((plugin) => [plugin.name, plugin.description, plugin.slug, plugin.author && plugin.author.name, plugin.author && plugin.author.username].some((value) => String(value || '').toLowerCase().includes(query))) : all;
      const sort = input.sort === 'new' ? (a, b) => b.createdAt - a.createdAt : input.sort === 'updated' ? (a, b) => b.updatedAt - a.updatedAt : (a, b) => b.downloads - a.downloads || b.updatedAt - a.updatedAt;
      filtered.sort(sort);
      return ok({ items: filtered.slice(0, 200) });
    }
    if (path === '/plugin') {
      const plugin = SLUG.test(input.slug || '') ? await storage.get('p:' + input.slug) : null;
      return plugin ? ok({ plugin }) : fail('not_found', 404);
    }
    if (path === '/author') {
      const author = await storage.get('u:' + input.id);
      const plugins = [...(await storage.list({ prefix: 'p:' })).values()].filter((plugin) => plugin.authorId === String(input.id) && plugin.status === 'live' && plugin.current);
      return author || plugins.length ? ok({ author: author || { id: String(input.id) }, plugins }) : fail('not_found', 404);
    }
    if (path === '/mine') {
      const plugins = [...(await storage.list({ prefix: 'p:' })).values()].filter((plugin) => plugin.authorId === String(input.id));
      const subs = [...(await storage.list({ prefix: 's:' })).values()].filter((sub) => sub.authorId === String(input.id)).sort((a, b) => b.createdAt - a.createdAt).slice(0, 30);
      return ok({ plugins, submissions: subs });
    }
    if (path === '/submission') {
      const sub = SID.test(input.sid || '') ? await storage.get('s:' + input.sid) : null;
      return sub ? ok({ submission: sub, plugin: (await storage.get('p:' + sub.slug)) || null }) : fail('not_found', 404);
    }
    if (path === '/pending') {
      const subs = [...(await storage.list({ prefix: 's:' })).values()].filter((sub) => sub.status === 'pending').sort((a, b) => a.createdAt - b.createdAt);
      return ok({ submissions: subs.slice(0, 30) });
    }
    return fail('not_found', 404);
  }

  async write(path, input, now) {
    const storage = this.state.storage;
    if (path === '/submit-check') {
      const plugin = await storage.get('p:' + input.slug);
      if (plugin && plugin.authorId !== String(input.authorId)) {
        return fail('slug_taken', 409);
      }
      if (plugin && plugin.status === 'banned') {
        return fail('plugin_blocked', 403);
      }
      if ((await storage.get('ban:' + input.authorId))) {
        return fail('author_blocked', 403);
      }
      if (plugin && plugin.current && compareVersions(input.version, plugin.current.version) <= 0) {
        return fail('version_not_newer', 409, { current: plugin.current.version });
      }
      if (!plugin || !plugin.current) {
        const live = [...(await storage.list({ prefix: 'p:' })).values()].filter((item) => item.authorId === String(input.authorId)).length;
        if (live >= LIVE_PER_AUTHOR) {
          return fail('too_many_plugins', 429, { max: LIVE_PER_AUTHOR });
        }
      }
      if (!(await this.allow([['id', input.authorId, SUBMITS_PER_ID], ['ip', input.ip || 'none', SUBMITS_PER_IP]], now))) {
        return fail('rate_limited', 429);
      }
      return ok({ kind: plugin && plugin.current ? 'update' : 'new', hasMedia: Boolean(plugin && plugin.media && plugin.media.length) });
    }
    if (path === '/submit') {
      const sub = input.sub;
      let plugin = await storage.get('p:' + sub.slug);
      if (plugin && plugin.authorId !== sub.authorId) {
        return fail('slug_taken', 409);
      }
      if (!plugin) {
        plugin = { slug: sub.slug, authorId: sub.authorId, name: sub.name, description: sub.description, about: sub.about, status: 'draft', current: null, media: [], downloads: 0, createdAt: now, updatedAt: now, pendingSid: null, author: sub.author };
      }
      const replaced = [];
      if (plugin.pendingSid) {
        const previous = await storage.get('s:' + plugin.pendingSid);
        if (previous && previous.status === 'pending') {
          previous.status = 'superseded';
          previous.decidedAt = now;
          await storage.put('s:' + previous.sid, previous);
          replaced.push(previous);
        }
      }
      const oldRejected = [...(await storage.list({ prefix: 's:' })).values()].filter((item) => item.slug === sub.slug && item.status === 'rejected' && item.blobsKept);
      for (const item of oldRejected) {
        item.blobsKept = false;
        await storage.put('s:' + item.sid, item);
        replaced.push(item);
      }
      sub.status = sub.scan.verdict === 'danger' ? 'rejected' : 'pending';
      sub.reason = sub.status === 'rejected' ? 'auto' : '';
      sub.blobsKept = true;
      sub.createdAt = now;
      sub.decidedAt = sub.status === 'rejected' ? now : 0;
      plugin.pendingSid = sub.status === 'pending' ? sub.sid : null;
      plugin.author = sub.author;
      await storage.put({ ['s:' + sub.sid]: sub, ['p:' + sub.slug]: plugin, ['u:' + sub.authorId]: { ...sub.author, updatedAt: now } });
      for (const item of replaced) {
        await this.releaseSubmission(item);
      }
      return ok({ submission: sub, plugin, replaced: replaced.map((item) => item.sid) });
    }
    if (path === '/ai') {
      const sub = await storage.get('s:' + input.sid);
      if (!sub) {
        return fail('not_found', 404);
      }
      sub.scan.ai = input.ai;
      let autoRejected = false;
      if (sub.status === 'pending' && input.ai && input.ai.verdict === 'malicious' && input.ai.confidence >= 0.8) {
        sub.scan.verdict = 'danger';
        sub.status = 'rejected';
        sub.reason = 'auto';
        sub.decidedAt = now;
        autoRejected = true;
        const plugin = await storage.get('p:' + sub.slug);
        if (plugin && plugin.pendingSid === sub.sid) {
          plugin.pendingSid = null;
          await storage.put('p:' + sub.slug, plugin);
        }
      }
      await storage.put('s:' + sub.sid, sub);
      return ok({ submission: sub, autoRejected });
    }
    if (path === '/decide') {
      const sub = SID.test(input.sid || '') ? await storage.get('s:' + input.sid) : null;
      if (!sub) {
        return fail('not_found', 404);
      }
      const plugin = await storage.get('p:' + sub.slug);
      if (!plugin) {
        return fail('not_found', 404);
      }
      if (input.action === 'approve') {
        if (sub.status === 'approved') {
          return fail('already_done', 409);
        }
        if (sub.status === 'superseded' || (sub.status === 'rejected' && !sub.blobsKept)) {
          return fail('gone', 410);
        }
        if (plugin.current && compareVersions(sub.version, plugin.current.version) <= 0) {
          return fail('version_not_newer', 409);
        }
        const drop = [];
        if (plugin.current) {
          drop.push(plugin.current.file.bid);
        }
        if (sub.media && sub.media.length) {
          drop.push(...plugin.media.map((item) => item.bid));
          plugin.media = sub.media;
        }
        const history = (plugin.history || []).concat(plugin.current ? [{ version: plugin.current.version, changelog: plugin.current.changelog, approvedAt: plugin.current.approvedAt }] : []).slice(-20);
        plugin.history = history;
        plugin.current = { version: sub.version, file: sub.file, scan: sub.scan, permissions: sub.permissions, domains: sub.domains, changelog: sub.changelog, approvedAt: now, sid: sub.sid };
        plugin.name = sub.name;
        plugin.description = sub.description;
        plugin.about = sub.about;
        plugin.author = sub.author;
        plugin.status = 'live';
        plugin.updatedAt = now;
        if (plugin.pendingSid === sub.sid) {
          plugin.pendingSid = null;
        }
        sub.status = 'approved';
        sub.reason = '';
        sub.decidedAt = now;
        sub.blobsKept = false;
        await storage.put({ ['s:' + sub.sid]: sub, ['p:' + sub.slug]: plugin });
        const keep = new Set([plugin.current.file.bid, ...plugin.media.map((item) => item.bid)]);
        await this.dropBlobs(drop.filter((id) => !keep.has(id)));
        return ok({ submission: sub, plugin });
      }
      if (input.action === 'reject') {
        if (sub.status !== 'pending' && !(sub.status === 'rejected' && sub.reason === 'auto')) {
          return fail('already_done', 409);
        }
        sub.status = 'rejected';
        sub.reason = String(input.reason || 'rules').slice(0, 220);
        sub.decidedAt = now;
        sub.blobsKept = false;
        if (plugin.pendingSid === sub.sid) {
          plugin.pendingSid = null;
        }
        await storage.put({ ['s:' + sub.sid]: sub, ['p:' + sub.slug]: plugin });
        await this.releaseSubmission(sub);
        return ok({ submission: sub, plugin });
      }
      return fail('bad_request', 400);
    }
    if (path === '/unpublish' || path === '/restore' || path === '/delete') {
      const plugin = SLUG.test(input.slug || '') ? await storage.get('p:' + input.slug) : null;
      if (!plugin) {
        return fail('not_found', 404);
      }
      if (input.authorId && plugin.authorId !== String(input.authorId)) {
        return fail('forbidden', 403);
      }
      if (path === '/delete') {
        const subs = [...(await storage.list({ prefix: 's:' })).values()].filter((item) => item.slug === plugin.slug);
        const ids = [plugin.current && plugin.current.file.bid, ...plugin.media.map((item) => item.bid), ...subs.flatMap((item) => this.blobsOf(item))].filter(Boolean);
        await storage.delete(['p:' + plugin.slug, ...subs.map((item) => 's:' + item.sid)]);
        await this.dropBlobs(ids);
        return ok({ ok: true, plugin });
      }
      if (path === '/restore' && !plugin.current) {
        return fail('nothing_published', 409);
      }
      plugin.status = path === '/unpublish' ? (input.ban ? 'banned' : 'hidden') : 'live';
      plugin.updatedAt = now;
      await storage.put('p:' + plugin.slug, plugin);
      return ok({ plugin });
    }
    if (path === '/download') {
      const plugin = SLUG.test(input.slug || '') ? await storage.get('p:' + input.slug) : null;
      if (!plugin || plugin.status !== 'live' || !plugin.current) {
        return fail('not_found', 404);
      }
      const key = plugin.slug + '|' + (input.ip || '') + '|' + day(now);
      if (input.ip && !downloadSeen.has(key)) {
        if (downloadSeen.size > 20000) {
          downloadSeen.clear();
        }
        downloadSeen.set(key, true);
        plugin.downloads = (plugin.downloads || 0) + 1;
        await storage.put('p:' + plugin.slug, plugin);
      }
      return ok({ file: plugin.current.file, version: plugin.current.version });
    }
    if (path === '/ban-author' || path === '/unban-author') {
      if (path === '/ban-author') {
        await storage.put('ban:' + input.id, { time: now });
        for (const plugin of [...(await storage.list({ prefix: 'p:' })).values()].filter((item) => item.authorId === String(input.id))) {
          plugin.status = plugin.current ? 'hidden' : plugin.status;
          plugin.pendingSid = null;
          await storage.put('p:' + plugin.slug, plugin);
        }
      } else {
        await storage.delete('ban:' + input.id);
      }
      return ok({ ok: true });
    }
    if (path === '/delete-blobs') {
      const ids = Array.isArray(input.ids) ? input.ids.filter((id) => typeof id === 'string' && BID.test(id)) : [];
      const referenced = new Set();
      for (const plugin of (await storage.list({ prefix: 'p:' })).values()) {
        if (plugin.current) {
          referenced.add(plugin.current.file.bid);
        }
        for (const item of plugin.media || []) {
          referenced.add(item.bid);
        }
      }
      for (const sub of (await storage.list({ prefix: 's:' })).values()) {
        if (sub.status === 'pending' || sub.blobsKept) {
          for (const id of this.blobsOf(sub)) {
            referenced.add(id);
          }
        }
      }
      await this.dropBlobs(ids.filter((id) => !referenced.has(id)));
      return ok({ ok: true });
    }
    if (path === '/sweep') {
      const subs = [...(await storage.list({ prefix: 's:' })).values()].filter((item) => item.status === 'rejected' && item.blobsKept && now - item.decidedAt > REJECTED_TTL);
      for (const item of subs) {
        item.blobsKept = false;
        await storage.put('s:' + item.sid, item);
        await this.releaseSubmission(item);
      }
      return ok({ swept: subs.length });
    }
    return fail('not_found', 404);
  }
}

function lang(request) {
  return /^(ru|uk|be|kk)/i.test(request.headers.get('accept-language') || '') ? 1 : 0;
}

function mediaUrl(origin, item) {
  return origin + '/m/' + item.bid + '.' + (MEDIA_EXT[item.mime] || 'bin');
}

function presentAuthor(author) {
  return author ? { id: String(author.id || ''), name: author.name || '', username: author.username || '' } : null;
}

function presentScan(scan) {
  if (!scan) {
    return null;
  }
  return { verdict: scan.verdict, danger: scan.danger, warn: scan.warn, findings: (scan.findings || []).filter((item) => item.level !== 'info').map((item) => ({ level: item.level, code: item.code, text: item.text })).slice(0, 20), ai: scan.ai ? { verdict: scan.ai.verdict, summary: scan.ai.summary } : null };
}

function presentPlugin(plugin, origin, full) {
  const current = plugin.current;
  const value = {
    slug: plugin.slug,
    name: plugin.name,
    description: plugin.description,
    version: current ? current.version : '',
    author: presentAuthor(plugin.author),
    permissions: current ? current.permissions : [],
    domains: current ? current.domains : [],
    downloads: plugin.downloads || 0,
    createdAt: plugin.createdAt,
    updatedAt: plugin.updatedAt,
    status: plugin.status,
    media: (plugin.media || []).map((item) => ({ url: mediaUrl(origin, item), kind: item.kind, mime: item.mime, width: item.width || 0, height: item.height || 0 })),
    file: current ? { name: current.file.name, size: current.file.size, sha256: current.file.sha256, ext: current.file.ext } : null,
    downloadUrl: current ? origin + '/api/plugins/' + plugin.slug + '/download' : '',
    pageUrl: origin + '/p/' + plugin.slug,
    scan: current ? presentScan(current.scan) : null,
  };
  if (full) {
    value.about = plugin.about || '';
    value.changelog = current ? current.changelog || '' : '';
    value.history = (plugin.history || []).slice().reverse();
  }
  return value;
}

function presentSubmission(sub) {
  return { sid: sub.sid, slug: sub.slug, kind: sub.kind, name: sub.name, version: sub.version, status: sub.status, reason: sub.reason ? reasonText(sub.reason, 1) : '', reasonEn: sub.reason ? reasonText(sub.reason, 0) : '', createdAt: sub.createdAt, decidedAt: sub.decidedAt || 0, scan: presentScan(sub.scan) };
}

function reasonText(reason, ru) {
  const known = REASON_TEXT[reason];
  return known ? known[ru] : reason;
}

async function telegram(env, method, body) {
  if (!env || !env.REPORT_BOT_TOKEN) {
    return null;
  }
  const init = body instanceof FormData ? { method: 'POST', body } : { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) };
  const response = await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/' + method, init).catch(() => null);
  if (response && !response.ok) {
    console.log('market telegram ' + method + ' failed: ' + response.status);
  }
  return response;
}

function adminButtons(sub) {
  if (sub.status === 'pending') {
    return { inline_keyboard: [[{ text: '✅ Опубликовать', callback_data: 'MA:' + sub.sid }, { text: '❌ Отклонить', callback_data: 'MR:' + sub.sid }], [{ text: '⛔ Забанить автора', callback_data: 'MB:' + sub.sid }]] };
  }
  if (sub.status === 'rejected' && sub.reason === 'auto' && sub.blobsKept) {
    return { inline_keyboard: [[{ text: '✅ Всё равно опубликовать', callback_data: 'MA:' + sub.sid }], [{ text: '⛔ Забанить автора', callback_data: 'MB:' + sub.sid }]] };
  }
  if (sub.status === 'approved') {
    return { inline_keyboard: [[{ text: '🙈 Скрыть с маркетплейса', callback_data: 'MH:' + sub.slug }], [{ text: '🗑 Удалить совсем', callback_data: 'MX:' + sub.slug }]] };
  }
  return { inline_keyboard: [] };
}

function statusLine(sub) {
  if (sub.status === 'approved') {
    return '✅ Опубликовано';
  }
  if (sub.status === 'rejected') {
    return (sub.reason === 'auto' ? '🤖 Автоматически отклонено' : '❌ Отклонено') + ': ' + reasonText(sub.reason, 1);
  }
  if (sub.status === 'superseded') {
    return '♻️ Заменено новой заявкой';
  }
  return '⏳ Ждёт проверки';
}

function adminText(sub, plugin) {
  const author = sub.author || {};
  const lines = [
    (sub.kind === 'update' ? '🔄 Обновление плагина' : '🧩 Новый плагин') + ' · заявка ' + sub.sid,
    sub.name + ' v' + sub.version + ' (' + sub.slug + ')' + (sub.kind === 'update' && plugin && plugin.current ? ' ← было v' + plugin.current.version : ''),
    'Автор: ' + (author.name || '-') + (author.username ? ' @' + author.username : '') + ' · ID ' + sub.authorId,
    'Разрешения: ' + (sub.permissions.length ? sub.permissions.join(', ') : 'нет'),
    'Домены: ' + (sub.domains.length ? sub.domains.join(', ') : 'нет'),
    'Файл: ' + sub.file.name + ' · ' + Math.max(1, Math.round(sub.file.size / 1024)) + ' КБ · sha256 ' + sub.file.sha256.slice(0, 16),
    'Медиа: ' + (sub.media.length ? sub.media.length : sub.kind === 'update' ? 'старые' : 'нет'),
    '',
    'Описание: ' + sub.description,
  ];
  if (sub.about) {
    lines.push('', 'О плагине: ' + sub.about.slice(0, 900));
  }
  if (sub.changelog) {
    lines.push('', 'Что нового: ' + sub.changelog.slice(0, 500));
  }
  lines.push('', scanSummary(sub.scan), '', statusLine(sub));
  const text = lines.join('\n');
  return text.length > 4000 ? text.slice(0, 3990) + '…' : text;
}

async function sendBlob(env, method, field, bytes, mime, name, extra) {
  const form = new FormData();
  form.append('chat_id', String(env.REPORT_CHAT_ID));
  for (const [key, value] of Object.entries(extra || {})) {
    form.append(key, typeof value === 'string' ? value : JSON.stringify(value));
  }
  form.append(field, new Blob([bytes], { type: mime }), name);
  const response = await telegram(env, method, form);
  return Boolean(response && response.ok);
}

async function notifyAdmin(env, sub, plugin, fileBytes, mediaItems) {
  if (!env || !env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
    return;
  }
  if (mediaItems.length > 1) {
    const form = new FormData();
    form.append('chat_id', String(env.REPORT_CHAT_ID));
    form.append('media', JSON.stringify(mediaItems.map((item, index) => ({ type: item.kind === 'video' ? 'video' : 'photo', media: 'attach://m' + index }))));
    mediaItems.forEach((item, index) => form.append('m' + index, new Blob([item.bytes], { type: item.mime }), 'media' + index + '.' + (MEDIA_EXT[item.mime] || 'bin')));
    const response = await telegram(env, 'sendMediaGroup', form);
    if (!response || !response.ok) {
      for (const item of mediaItems) {
        await sendBlob(env, 'sendDocument', 'document', item.bytes, item.mime, 'media.' + (MEDIA_EXT[item.mime] || 'bin'));
      }
    }
  } else if (mediaItems.length === 1) {
    const item = mediaItems[0];
    const direct = item.mime === 'image/jpeg' || item.mime === 'image/png' ? ['sendPhoto', 'photo'] : item.kind === 'video' ? ['sendVideo', 'video'] : ['sendDocument', 'document'];
    if (!(await sendBlob(env, direct[0], direct[1], item.bytes, item.mime, 'media.' + (MEDIA_EXT[item.mime] || 'bin')))) {
      await sendBlob(env, 'sendDocument', 'document', item.bytes, item.mime, 'media.' + (MEDIA_EXT[item.mime] || 'bin'));
    }
  }
  await sendBlob(env, 'sendDocument', 'document', fileBytes, 'application/octet-stream', sub.file.name, { caption: sub.name + ' v' + sub.version });
  await telegram(env, 'sendMessage', { chat_id: env.REPORT_CHAT_ID, text: adminText(sub, plugin), link_preview_options: { is_disabled: true }, reply_markup: adminButtons(sub) });
}

async function notifyAuthor(env, sub) {
  if (!env || !env.REPORT_BOT_TOKEN || !sub.authorId) {
    return;
  }
  const title = sub.name + ' v' + sub.version;
  let text;
  if (sub.status === 'approved') {
    text = '✅ ' + title + ' is published in the AyuGram plugin marketplace.\nhttps://' + MARKET_HOST + '/p/' + sub.slug + '\n\n✅ ' + title + ' опубликован в маркетплейсе плагинов AyuGram.';
  } else if (sub.status === 'rejected') {
    text = '❌ ' + title + ' was not accepted: ' + reasonText(sub.reason, 0) + '.\n\n❌ ' + title + ' не принят: ' + reasonText(sub.reason, 1) + '.';
  } else {
    return;
  }
  await telegram(env, 'sendMessage', { chat_id: sub.authorId, text, link_preview_options: { is_disabled: true } });
}

async function later(ctx, work) {
  const guarded = work.catch((error) => console.log('market task failed: ' + error));
  if (ctx && typeof ctx.waitUntil === 'function') {
    ctx.waitUntil(guarded);
  } else {
    await guarded;
  }
}

async function putBlob(stub, bytes, mime) {
  const id = randomHex(8);
  const response = await stub.fetch(INTERNAL + '/blob-put', { method: 'POST', headers: { 'x-id': id, 'x-mime': mime }, body: bytes });
  if (!response.ok) {
    const data = await response.json().catch(() => ({}));
    throw Object.assign(new Error(data.error || 'store_failed'), { status: response.status });
  }
  return id;
}

async function dropBlobsDirect(stub, ids) {
  if (ids.length) {
    await call(stub, '/delete-blobs', { ids }).catch(() => null);
  }
}

async function submit(request, env, url, ctx, stub, origin) {
  const declared = Number(request.headers.get('content-length') || 0);
  if (!declared) {
    return fail('length_required', 411);
  }
  if (declared > MARKET_LIMITS.body) {
    return fail('too_large', 413, { max: MARKET_LIMITS.body });
  }
  const who = await marketIdentity(request, env);
  if (who.error) {
    return who.error;
  }
  if (!who.verified) {
    return fail('unverified', 403);
  }
  let form;
  try {
    form = await request.formData();
  } catch {
    return fail('bad_request', 400);
  }
  let meta = {};
  try {
    meta = JSON.parse(String(form.get('meta') || '{}'));
  } catch {
    return fail('bad_request', 400);
  }
  if (!meta || typeof meta !== 'object' || Array.isArray(meta)) {
    return fail('bad_request', 400);
  }
  const file = form.get('file');
  if (!file || typeof file === 'string') {
    return fail('no_file', 400);
  }
  if (file.size > MARKET_LIMITS.file) {
    return fail('file_too_large', 413, { max: MARKET_LIMITS.file });
  }
  const fileBytes = new Uint8Array(await file.arrayBuffer());
  const fileName = line(file.name || 'plugin.js', 80) || 'plugin.js';
  const unpacked = await unpackPlugin(fileBytes, fileName);
  if (unpacked.error) {
    return fail('bad_plugin', 422, { reason: unpacked.error });
  }
  const info = unpacked.info;
  if (!info.id || info.id.length < 2 || !SLUG.test(info.id)) {
    return fail('bad_plugin_id', 422);
  }
  const mediaFiles = form.getAll('media').filter((item) => item && typeof item !== 'string');
  if (mediaFiles.length > MARKET_LIMITS.media) {
    return fail('too_many_media', 400, { max: MARKET_LIMITS.media });
  }
  const mediaItems = [];
  for (const item of mediaFiles) {
    const bytes = new Uint8Array(await item.arrayBuffer());
    const mime = sniffMedia(bytes);
    if (!mime || !MEDIA_EXT[mime]) {
      return fail('unsupported_media', 415);
    }
    const kind = mime.startsWith('video/') ? 'video' : 'photo';
    if (bytes.length > (kind === 'video' ? MARKET_LIMITS.video : MARKET_LIMITS.photo)) {
      return fail('media_too_large', 413, { max: kind === 'video' ? MARKET_LIMITS.video : MARKET_LIMITS.photo });
    }
    const inspected = inspectMedia(bytes, kind, {});
    if (inspected.error) {
      return fail('bad_media', 422);
    }
    mediaItems.push({ bytes, mime: inspected.mime, kind, width: inspected.width, height: inspected.height });
  }
  const name = line(meta.name, MARKET_LIMITS.name) || info.name;
  const description = clean(meta.description, MARKET_LIMITS.description) || info.description;
  if (name.length < 2) {
    return fail('bad_name', 400);
  }
  if (description.length < 10) {
    return fail('bad_description', 400);
  }
  const authorName = line(meta.author && meta.author.name, 64);
  const username = line(meta.author && meta.author.username, 32).replace(/^@/, '');
  const ip = network(request.headers.get('cf-connecting-ip') || '');
  const checked = await callJson(stub, '/submit-check', { slug: info.id, authorId: who.id, version: info.version, ip: ip ? await ipTag(ip) : '' });
  if (!checked.ok) {
    return fail(checked.data.error || 'unavailable', checked.status, checked.data);
  }
  if (checked.data.kind === 'new' && !mediaItems.length && !checked.data.hasMedia) {
    return fail('media_required', 400);
  }
  const scan = scanPlugin(unpacked);
  const stored = [];
  try {
    const fileBid = await putBlob(stub, fileBytes, 'application/octet-stream');
    stored.push(fileBid);
    const media = [];
    for (const item of mediaItems) {
      const bid = await putBlob(stub, item.bytes, item.mime);
      stored.push(bid);
      media.push({ bid, mime: item.mime, kind: item.kind, width: item.width, height: item.height, size: item.bytes.length });
    }
    const sub = {
      sid: randomHex(8),
      slug: info.id,
      kind: checked.data.kind,
      authorId: who.id,
      author: { id: who.id, name: authorName, username: USERNAME.test(username) ? username : '' },
      name,
      description,
      about: clean(meta.about, MARKET_LIMITS.about),
      changelog: clean(meta.changelog, MARKET_LIMITS.changelog),
      version: info.version,
      permissions: info.permissions,
      domains: info.domains,
      file: { bid: fileBid, name: fileName, size: fileBytes.length, sha256: await sha256(fileBytes), ext: unpacked.ext },
      media,
      scan,
    };
    const saved = await callJson(stub, '/submit', { sub });
    if (!saved.ok) {
      throw Object.assign(new Error(saved.data.error || 'store_failed'), { status: saved.status });
    }
    const record = saved.data.submission;
    await later(ctx, (async () => {
      let current = record;
      const ai = await aiReview(env, unpacked);
      if (ai) {
        const updated = await callJson(stub, '/ai', { sid: record.sid, ai });
        if (updated.ok) {
          current = updated.data.submission;
        }
      }
      await notifyAdmin(env, current, saved.data.plugin, fileBytes, mediaItems);
      if (current.status === 'rejected') {
        await notifyAuthor(env, current);
      }
    })());
    return ok({ submission: presentSubmission(record), pageUrl: origin + '/p/' + record.slug });
  } catch (error) {
    await dropBlobsDirect(stub, stored);
    return fail(error.message || 'store_failed', error.status || 502);
  }
}

async function serveBlob(request, stub, id, ext, extraHeaders) {
  const response = await stub.fetch(INTERNAL + '/blob-get?id=' + id);
  if (!response.ok) {
    return fail('not_found', 404);
  }
  const mime = (response.headers.get('content-type') || '').split(';')[0];
  if (ext && MEDIA_EXT[mime] !== ext) {
    return fail('not_found', 404);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  const base = { etag: '"' + id + '"', 'accept-ranges': 'bytes', 'cache-control': 'public, max-age=31536000, immutable', 'x-content-type-options': 'nosniff', 'content-security-policy': "default-src 'none'; sandbox", 'cross-origin-resource-policy': 'cross-origin', ...(extraHeaders || {}) };
  if (request.headers.get('if-none-match') === base.etag) {
    return new Response(null, { status: 304, headers: base });
  }
  const size = bytes.length;
  const match = /^bytes=(\d*)-(\d*)$/.exec(request.headers.get('range') || '');
  if (match && (match[1] || match[2])) {
    const start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
    const end = match[1] && match[2] ? Math.min(Number(match[2]), size - 1) : size - 1;
    if (start >= size || start > end) {
      return new Response(null, { status: 416, headers: { ...base, 'content-range': 'bytes */' + size } });
    }
    const part = bytes.subarray(start, end + 1);
    return new Response(request.method === 'HEAD' ? null : part, { status: 206, headers: { ...base, 'content-type': mime, 'content-length': String(part.length), 'content-range': 'bytes ' + start + '-' + end + '/' + size } });
  }
  return new Response(request.method === 'HEAD' ? null : bytes, { headers: { ...base, 'content-type': mime, 'content-length': String(size) } });
}

function scanAllowed(ip) {
  const now = Date.now();
  const bucket = scanBuckets.get(ip) || { start: now, count: 0 };
  if (now - bucket.start > 60000) {
    bucket.start = now;
    bucket.count = 0;
  }
  bucket.count += 1;
  if (scanBuckets.size > 5000) {
    scanBuckets.clear();
  }
  scanBuckets.set(ip, bucket);
  return bucket.count <= SCANS_PER_MINUTE;
}

async function scanOnly(request) {
  const ip = network(request.headers.get('cf-connecting-ip') || '') || 'local';
  if (!scanAllowed(ip)) {
    return fail('rate_limited', 429);
  }
  if (Number(request.headers.get('content-length') || 0) > MARKET_LIMITS.file) {
    return fail('file_too_large', 413, { max: MARKET_LIMITS.file });
  }
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (!bytes.length || bytes.length > MARKET_LIMITS.file) {
    return fail(bytes.length ? 'file_too_large' : 'empty', bytes.length ? 413 : 400);
  }
  const name = line(new URL(request.url).searchParams.get('name') || 'plugin.js', 80);
  const unpacked = await unpackPlugin(bytes, name);
  if (unpacked.error) {
    return fail('bad_plugin', 422, { reason: unpacked.error });
  }
  const scan = scanPlugin(unpacked);
  return ok({ info: unpacked.info, scan: { ...presentScan(scan), findings: scan.findings.map((item) => ({ level: item.level, code: item.code, text: item.text, file: item.file, line: item.line })) } });
}

const esc = (value) => String(value === undefined || value === null ? '' : value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const T = {
  title: ['AyuGram plugins', 'Плагины AyuGram'],
  subtitle: ['Plugins for AyuGram for iOS. Every plugin and every update is checked by hand and by an automatic scanner before it appears here.', 'Плагины для AyuGram на iOS. Каждый плагин и каждое обновление проверяются вручную и автоматическим сканером, прежде чем появиться здесь.'],
  search: ['Search', 'Поиск'],
  popular: ['Popular', 'Популярные'],
  fresh: ['New', 'Новые'],
  updated: ['Updated', 'Обновлённые'],
  empty: ['Nothing here yet.', 'Пока ничего нет.'],
  by: ['by', 'автор'],
  downloads: ['downloads', 'загрузок'],
  download: ['Download', 'Скачать'],
  open: ['Open in AyuGram', 'Открыть в AyuGram'],
  permissions: ['Permissions', 'Разрешения'],
  domains: ['Internet access', 'Доступ в интернет'],
  none: ['none', 'нет'],
  about: ['About', 'О плагине'],
  changes: ['What’s new', 'Что нового'],
  check: ['Automatic check', 'Автопроверка'],
  clean: ['nothing suspicious found', 'ничего подозрительного'],
  warn: ['passed with notes', 'пройдена с замечаниями'],
  danger: ['dangerous code found', 'найден опасный код'],
  version: ['Version', 'Версия'],
  plugins: ['Plugins', 'Плагины'],
  notFound: ['Plugin not found', 'Плагин не найден'],
  submit: ['Want to publish your plugin? Open AyuGram → Settings → AyuGram → Plugins → Marketplace → Submit.', 'Хотите опубликовать плагин? Откройте AyuGram → Настройки → AyuGram → Плагины → Маркетплейс → Отправить.'],
  history: ['Earlier versions', 'Прошлые версии'],
};

function page(ru, title, body) {
  return new Response('<!doctype html><html lang="' + (ru ? 'ru' : 'en') + '"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"><title>' + esc(title) + '</title><style>' + CSS + '</style></head><body><header><a class="brand" href="/">' + esc(T.title[ru]) + '</a></header><main>' + body + '</main><footer>' + esc(T.submit[ru]) + '</footer></body></html>', {
    headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'public, max-age=60', 'content-security-policy': "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'", 'x-content-type-options': 'nosniff', 'referrer-policy': 'no-referrer' },
  });
}

const CSS = ':root{--bg:#0f1115;--card:#181b22;--text:#eef0f4;--muted:#9aa3b2;--line:#262a33;--accent:#7c9cff;--ok:#3ecf8e;--warn:#f5b041;--bad:#ff5d5d}@media (prefers-color-scheme:light){:root{--bg:#f5f6f8;--card:#fff;--text:#14161a;--muted:#5d6676;--line:#e3e6eb;--accent:#3f63e0}}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}header{padding:18px 16px;border-bottom:1px solid var(--line)}.brand{color:var(--text);font-weight:700;font-size:20px;text-decoration:none}main{max-width:960px;margin:0 auto;padding:16px}footer{max-width:960px;margin:0 auto;padding:24px 16px;color:var(--muted);font-size:14px}a{color:var(--accent)}h1{font-size:26px;margin:8px 0}p.muted,.muted{color:var(--muted)}form.search{display:flex;gap:8px;margin:16px 0}form.search input{flex:1;min-width:0;padding:10px 12px;border-radius:10px;border:1px solid var(--line);background:var(--card);color:var(--text);font-size:16px}form.search button,.button{padding:10px 16px;border-radius:10px;border:0;background:var(--accent);color:#fff;font-weight:600;text-decoration:none;display:inline-block;font-size:16px}.tabs{display:flex;gap:12px;flex-wrap:wrap;margin-bottom:12px}.tabs a{color:var(--muted);text-decoration:none}.tabs a.on{color:var(--text);font-weight:600}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px}.card{background:var(--card);border:1px solid var(--line);border-radius:14px;overflow:hidden;color:var(--text);text-decoration:none;display:flex;flex-direction:column}.card img,.card .ph{width:100%;aspect-ratio:16/9;object-fit:cover;background:var(--line);display:block}.card .body{padding:12px 14px}.card h3{margin:0 0 4px;font-size:17px}.card p{margin:0;color:var(--muted);font-size:14px}.meta{display:flex;gap:10px;flex-wrap:wrap;color:var(--muted);font-size:13px;margin-top:8px}.badge{border-radius:999px;padding:1px 8px;font-size:12px;font-weight:600}.clean{background:color-mix(in srgb,var(--ok) 20%,transparent);color:var(--ok)}.warn{background:color-mix(in srgb,var(--warn) 20%,transparent);color:var(--warn)}.danger{background:color-mix(in srgb,var(--bad) 20%,transparent);color:var(--bad)}.gallery{display:flex;gap:10px;overflow-x:auto;margin:16px 0;scroll-snap-type:x mandatory}.gallery img,.gallery video{height:360px;max-width:90vw;border-radius:12px;background:var(--line);scroll-snap-align:start}.section{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 16px;margin:14px 0}.section h2{font-size:17px;margin:0 0 8px}.pre{white-space:pre-wrap;word-break:break-word}ul{margin:0;padding-left:20px}.actions{display:flex;gap:10px;flex-wrap:wrap;margin:14px 0}.button.alt{background:var(--card);color:var(--text);border:1px solid var(--line)}@media (max-width:480px){.gallery img,.gallery video{height:260px}}';

function verdictBadge(scan, ru) {
  if (!scan) {
    return '';
  }
  return '<span class="badge ' + esc(scan.verdict) + '">' + esc(T.check[ru] + ': ' + T[scan.verdict][ru]) + '</span>';
}

function cardHtml(plugin, origin, ru) {
  const value = presentPlugin(plugin, origin, false);
  const cover = value.media.find((item) => item.kind === 'photo');
  return '<a class="card" href="/p/' + esc(value.slug) + '">' + (cover ? '<img loading="lazy" src="' + esc(new URL(cover.url).pathname) + '" alt="">' : '<div class="ph"></div>') + '<div class="body"><h3>' + esc(value.name) + '</h3><p>' + esc(value.description) + '</p><div class="meta"><span>v' + esc(value.version) + '</span><span>' + esc(T.by[ru] + ' ' + ((value.author && value.author.name) || (value.author && value.author.username) || '—')) + '</span><span>' + esc(value.downloads + ' ' + T.downloads[ru]) + '</span>' + verdictBadge(value.scan, ru) + '</div></div></a>';
}

async function siteIndex(request, stub, url, origin) {
  const ru = lang(request);
  const sort = ['new', 'updated'].includes(url.searchParams.get('sort')) ? url.searchParams.get('sort') : 'popular';
  const q = line(url.searchParams.get('q'), 80);
  const listed = await callJson(stub, '/list', { q, sort });
  const items = listed.ok ? listed.data.items : [];
  const tab = (key, label) => '<a class="' + (sort === key ? 'on' : '') + '" href="/?sort=' + key + (q ? '&q=' + encodeURIComponent(q) : '') + '">' + esc(label) + '</a>';
  const body = '<h1>' + esc(T.title[ru]) + '</h1><p class="muted">' + esc(T.subtitle[ru]) + '</p><form class="search" method="get" action="/"><input type="search" name="q" value="' + esc(q) + '" placeholder="' + esc(T.search[ru]) + '"><input type="hidden" name="sort" value="' + esc(sort) + '"><button type="submit">' + esc(T.search[ru]) + '</button></form><nav class="tabs">' + tab('popular', T.popular[ru]) + tab('new', T.fresh[ru]) + tab('updated', T.updated[ru]) + '</nav>' + (items.length ? '<div class="grid">' + items.map((plugin) => cardHtml(plugin, origin, ru)).join('') + '</div>' : '<p class="muted">' + esc(T.empty[ru]) + '</p>');
  return page(ru, T.title[ru], body);
}

async function sitePlugin(request, stub, slug, origin) {
  const ru = lang(request);
  const found = await callJson(stub, '/plugin', { slug });
  const plugin = found.ok ? found.data.plugin : null;
  if (!plugin || plugin.status !== 'live' || !plugin.current) {
    const response = page(ru, T.notFound[ru], '<h1>' + esc(T.notFound[ru]) + '</h1><p><a href="/">' + esc(T.title[ru]) + '</a></p>');
    return new Response(response.body, { status: 404, headers: response.headers });
  }
  const value = presentPlugin(plugin, origin, true);
  const author = value.author || {};
  const gallery = value.media.length ? '<div class="gallery">' + value.media.map((item) => item.kind === 'video' ? '<video controls playsinline preload="metadata" src="' + esc(new URL(item.url).pathname) + '"></video>' : '<img src="' + esc(new URL(item.url).pathname) + '" alt="">').join('') + '</div>' : '';
  const permissions = value.permissions.length ? '<ul>' + value.permissions.map((item) => '<li>' + esc((PERMISSION_TEXT[item] || [item, item])[ru]) + '</li>').join('') + '</ul>' : '<p class="muted">' + esc(T.none[ru]) + '</p>';
  const scanList = value.scan && value.scan.findings.length ? '<ul>' + value.scan.findings.map((item) => '<li>' + esc(item.text) + '</li>').join('') + '</ul>' : '';
  const history = value.history.length ? '<div class="section"><h2>' + esc(T.history[ru]) + '</h2>' + value.history.map((item) => '<p><b>v' + esc(item.version) + '</b>' + (item.changelog ? '<br><span class="pre muted">' + esc(item.changelog) + '</span>' : '') + '</p>').join('') + '</div>' : '';
  const body = '<h1>' + esc(value.name) + '</h1><p class="muted">' + esc(value.description) + '</p><div class="meta"><span>' + esc(T.version[ru] + ' ' + value.version) + '</span><span>' + esc(T.by[ru]) + ' <a href="/u/' + esc(author.id) + '">' + esc(author.name || author.username || author.id) + '</a>' + (author.username ? ' · <a href="https://t.me/' + esc(author.username) + '">@' + esc(author.username) + '</a>' : '') + '</span><span>' + esc(value.downloads + ' ' + T.downloads[ru]) + '</span>' + verdictBadge(value.scan, ru) + '</div><div class="actions"><a class="button" href="ayugram://market?slug=' + esc(encodeURIComponent(value.slug)) + '">' + esc(T.open[ru]) + '</a><a class="button alt" href="/api/plugins/' + esc(value.slug) + '/download">' + esc(T.download[ru]) + '</a></div>' + gallery + (value.about ? '<div class="section"><h2>' + esc(T.about[ru]) + '</h2><div class="pre">' + esc(value.about) + '</div></div>' : '') + (value.changelog ? '<div class="section"><h2>' + esc(T.changes[ru] + ' · v' + value.version) + '</h2><div class="pre">' + esc(value.changelog) + '</div></div>' : '') + '<div class="section"><h2>' + esc(T.permissions[ru]) + '</h2>' + permissions + '<h2 style="margin-top:12px">' + esc(T.domains[ru]) + '</h2><p class="muted">' + esc(value.domains.length ? value.domains.join(', ') : T.none[ru]) + '</p></div><div class="section"><h2>' + esc(T.check[ru]) + '</h2>' + verdictBadge(value.scan, ru) + scanList + '<p class="muted" style="font-size:13px">sha256 ' + esc(value.file.sha256) + '</p></div>' + history;
  return page(ru, value.name + ' — ' + T.title[ru], body);
}

async function siteAuthor(request, stub, id, origin) {
  const ru = lang(request);
  const found = await callJson(stub, '/author', { id });
  if (!found.ok) {
    const response = page(ru, T.notFound[ru], '<h1>' + esc(T.notFound[ru]) + '</h1>');
    return new Response(response.body, { status: 404, headers: response.headers });
  }
  const author = found.data.author;
  const body = '<h1>' + esc(author.name || author.username || author.id) + '</h1><p class="muted">' + (author.username ? '<a href="https://t.me/' + esc(author.username) + '">@' + esc(author.username) + '</a> · ' : '') + 'ID ' + esc(author.id) + '</p><h2>' + esc(T.plugins[ru]) + '</h2>' + (found.data.plugins.length ? '<div class="grid">' + found.data.plugins.map((plugin) => cardHtml(plugin, origin, ru)).join('') + '</div>' : '<p class="muted">' + esc(T.empty[ru]) + '</p>');
  return page(ru, (author.name || author.username || author.id) + ' — ' + T.title[ru], body);
}

export function isMarketRequest(url) {
  return url.hostname === MARKET_HOST || url.pathname === '/market' || url.pathname.startsWith('/market/');
}

export async function handleMarket(request, env, url, ctx) {
  const stub = marketStub(env);
  if (!stub) {
    return fail('unavailable', 503);
  }
  const onHost = url.hostname === MARKET_HOST;
  const path = (onHost ? url.pathname : url.pathname.slice('/market'.length)).replace(/\/+$/, '') || '/';
  const origin = onHost ? 'https://' + MARKET_HOST : url.origin + '/market';
  const method = request.method;
  const read = method === 'GET' || method === 'HEAD';
  let match;
  if ((match = /^\/m\/([0-9a-f]{16})\.(jpg|png|heic|mp4|mov)$/.exec(path))) {
    return read ? serveBlob(request, stub, match[1], match[2]) : fail('method_not_allowed', 405);
  }
  if (path === '/api/plugins') {
    if (!read) {
      return fail('method_not_allowed', 405);
    }
    const listed = await callJson(stub, '/list', { q: url.searchParams.get('q') || '', sort: url.searchParams.get('sort') || '' });
    return listed.ok ? ok({ items: listed.data.items.map((plugin) => presentPlugin(plugin, origin, false)) }) : fail('unavailable', 503);
  }
  if ((match = /^\/api\/plugins\/([a-z0-9][a-z0-9._-]{0,46}[a-z0-9])(\/download)?$/.exec(path))) {
    const slug = match[1];
    if (match[2]) {
      if (!read) {
        return fail('method_not_allowed', 405);
      }
      const ip = network(request.headers.get('cf-connecting-ip') || '');
      const found = await callJson(stub, '/download', { slug, ip: ip ? await ipTag(ip) : '' });
      if (!found.ok) {
        return fail('not_found', 404);
      }
      const name = found.data.file.name.replace(/[^A-Za-z0-9._-]+/g, '_') || slug + '.' + found.data.file.ext;
      return serveBlob(request, stub, found.data.file.bid, '', { 'content-type': 'application/octet-stream', 'content-disposition': 'attachment; filename="' + name + '"', 'cache-control': 'no-store', 'x-plugin-version': found.data.version, 'x-plugin-sha256': found.data.file.sha256 });
    }
    if (method === 'DELETE') {
      const who = await marketIdentity(request, env);
      if (who.error) {
        return who.error;
      }
      if (!who.verified) {
        return fail('unverified', 403);
      }
      const done = await callJson(stub, '/delete', { slug, authorId: who.id });
      return done.ok ? ok({ ok: true }) : fail(done.data.error || 'unavailable', done.status);
    }
    if (!read) {
      return fail('method_not_allowed', 405);
    }
    const found = await callJson(stub, '/plugin', { slug });
    if (!found.ok || found.data.plugin.status !== 'live' || !found.data.plugin.current) {
      return fail('not_found', 404);
    }
    return ok({ plugin: presentPlugin(found.data.plugin, origin, true) });
  }
  if ((match = /^\/api\/authors\/([1-9][0-9]{0,15})$/.exec(path))) {
    const found = await callJson(stub, '/author', { id: match[1] });
    return found.ok ? ok({ author: presentAuthor(found.data.author), plugins: found.data.plugins.map((plugin) => presentPlugin(plugin, origin, false)) }) : fail('not_found', 404);
  }
  if (path === '/api/scan') {
    return method === 'POST' ? scanOnly(request) : fail('method_not_allowed', 405);
  }
  if (path === '/api/submit') {
    return method === 'POST' ? submit(request, env, url, ctx, stub, origin) : fail('method_not_allowed', 405);
  }
  if (path === '/api/mine') {
    if (!read) {
      return fail('method_not_allowed', 405);
    }
    const who = await marketIdentity(request, env);
    if (who.error) {
      return who.error;
    }
    const found = await callJson(stub, '/mine', { id: who.id });
    if (!found.ok) {
      return fail('unavailable', 503);
    }
    return ok({ verified: who.verified, plugins: found.data.plugins.map((plugin) => ({ ...presentPlugin(plugin, origin, false), pending: Boolean(plugin.pendingSid) })), submissions: found.data.submissions.map(presentSubmission) });
  }
  if (path === '/api/limits') {
    return ok({ limits: MARKET_LIMITS, permissions: PLUGIN_PERMISSIONS });
  }
  if (!read) {
    return fail('method_not_allowed', 405);
  }
  if (path === '/') {
    return siteIndex(request, stub, url, origin);
  }
  if ((match = /^\/p\/([a-z0-9][a-z0-9._-]{0,46}[a-z0-9])$/.exec(path))) {
    return sitePlugin(request, stub, match[1], origin);
  }
  if ((match = /^\/u\/([1-9][0-9]{0,15})$/.exec(path))) {
    return siteAuthor(request, stub, match[1], origin);
  }
  if (path === '/robots.txt') {
    return new Response('User-agent: *\nAllow: /\n', { headers: { 'content-type': 'text/plain' } });
  }
  return fail('not_found', 404);
}

export async function marketSweep(env) {
  const stub = marketStub(env);
  if (stub) {
    await call(stub, '/sweep', {});
  }
}

function rejectMenu(sid) {
  return { inline_keyboard: [...REJECT_REASONS.map(([code, label]) => [{ text: '❌ ' + label, callback_data: 'MR:' + sid + ':' + code }]), [{ text: '✏️ Своя причина', callback_data: 'MR:' + sid + ':custom' }], [{ text: 'Отмена', callback_data: 'MV:' + sid }]] };
}

export async function marketCallback(env, query, action, rid, reason, note, answer, savePending) {
  const stub = marketStub(env);
  const message = query.message;
  if (!stub) {
    await answer('Маркетплейс недоступен', true);
    return;
  }
  const edit = (text, markup) => (message ? telegram(env, 'editMessageText', { chat_id: message.chat.id, message_id: message.message_id, text, link_preview_options: { is_disabled: true }, reply_markup: markup }) : null);
  if (action === 'MH' || action === 'MX' || action === 'MS') {
    const path = { MH: '/unpublish', MX: '/delete', MS: '/restore' }[action];
    const done = await callJson(stub, path, { slug: rid });
    if (!done.ok) {
      await answer('Не получилось: ' + (done.data.error || done.status), true);
      return;
    }
    if (message) {
      const markup = action === 'MH' ? { inline_keyboard: [[{ text: '👁 Вернуть на маркетплейс', callback_data: 'MS:' + rid }], [{ text: '🗑 Удалить совсем', callback_data: 'MX:' + rid }]] } : action === 'MS' ? { inline_keyboard: [[{ text: '🙈 Скрыть с маркетплейса', callback_data: 'MH:' + rid }], [{ text: '🗑 Удалить совсем', callback_data: 'MX:' + rid }]] } : { inline_keyboard: [] };
      await telegram(env, 'editMessageReplyMarkup', { chat_id: message.chat.id, message_id: message.message_id, reply_markup: markup });
    }
    await answer({ MH: '🙈 Скрыт', MX: '🗑 Удалён', MS: '👁 Снова виден' }[action], true);
    return;
  }
  const found = await callJson(stub, '/submission', { sid: rid });
  if (!found.ok) {
    await answer('Заявка не найдена', true);
    return;
  }
  const sub = found.data.submission;
  if (action === 'MV') {
    await edit(adminText(sub, found.data.plugin), adminButtons(sub));
    await answer();
    return;
  }
  if (action === 'MO') {
    await telegram(env, 'sendMessage', { chat_id: message ? message.chat.id : env.REPORT_CHAT_ID, text: adminText(sub, found.data.plugin), link_preview_options: { is_disabled: true }, reply_markup: adminButtons(sub) });
    await answer();
    return;
  }
  if (action === 'MR' && !reason) {
    await edit(adminText(sub, found.data.plugin), rejectMenu(rid));
    await answer('Выбери причину');
    return;
  }
  if (action === 'MR' && reason === 'custom' && !note) {
    await savePending('MR:' + rid + ':custom');
    await telegram(env, 'sendMessage', { chat_id: message.chat.id, text: 'Напиши причину отказа одним сообщением, до 200 символов. Её увидит автор. /cancel — отмена.', reply_parameters: { message_id: message.message_id } });
    await answer();
    return;
  }
  if (action === 'MB') {
    await callJson(stub, '/ban-author', { id: sub.authorId });
    if (sub.status === 'pending' || (sub.status === 'rejected' && sub.reason === 'auto')) {
      const done = await callJson(stub, '/decide', { sid: rid, action: 'reject', reason: 'rules' });
      if (done.ok) {
        await notifyAuthor(env, done.data.submission);
      }
    }
    const fresh = await callJson(stub, '/submission', { sid: rid });
    await edit(adminText(fresh.ok ? fresh.data.submission : sub, found.data.plugin) + '\n⛔ Автор забанен в маркетплейсе', { inline_keyboard: [[{ text: '✅ Разбанить автора', callback_data: 'MU:' + rid }]] });
    await answer('⛔ Автор забанен, его плагины скрыты', true);
    return;
  }
  if (action === 'MU') {
    await callJson(stub, '/unban-author', { id: sub.authorId });
    await edit(adminText(sub, found.data.plugin) + '\n✅ Автор разбанен', { inline_keyboard: [] });
    await answer('✅ Разбанен', true);
    return;
  }
  const decision = action === 'MA' ? { action: 'approve' } : action === 'MR' ? { action: 'reject', reason: reason === 'custom' ? note : reason } : null;
  if (!decision) {
    await answer();
    return;
  }
  const done = await callJson(stub, '/decide', { sid: rid, ...decision });
  if (!done.ok) {
    const texts = { already_done: 'Уже решено', gone: 'Файлы этой заявки уже удалены', version_not_newer: 'Уже опубликована такая же или более новая версия', not_found: 'Заявка не найдена' };
    await answer(texts[done.data.error] || 'Не получилось', true);
    return;
  }
  await edit(adminText(done.data.submission, done.data.plugin), adminButtons(done.data.submission));
  await notifyAuthor(env, done.data.submission);
  await answer(action === 'MA' ? '✅ Опубликовано' : '❌ Отклонено', true);
}

export async function marketPendingText(env) {
  const stub = marketStub(env);
  if (!stub) {
    return { text: 'Маркетплейс недоступен' };
  }
  const found = await callJson(stub, '/pending', {});
  const subs = found.ok ? found.data.submissions : [];
  if (!subs.length) {
    return { text: '🧩 Заявок на проверку нет.\nhttps://' + MARKET_HOST };
  }
  return { text: '🧩 Ждут проверки: ' + subs.length + '\n\n' + subs.map((sub) => (sub.kind === 'update' ? '🔄 ' : '🆕 ') + sub.name + ' v' + sub.version + ' · ' + ({ clean: '🟢', warn: '🟡', danger: '🔴' }[sub.scan.verdict] || '') + ' · ID ' + sub.authorId).join('\n'), markup: { inline_keyboard: subs.slice(0, 10).map((sub) => [{ text: '🔎 ' + sub.name + ' v' + sub.version, callback_data: 'MO:' + sub.sid }]) } };
}
