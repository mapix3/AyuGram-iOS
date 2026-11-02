const INSTALL_TTL_MS = 60 * 24 * 60 * 60 * 1000;
const REPORT_TTL_MS = 180 * 24 * 60 * 60 * 1000;
const REPORTS_PER_DAY = 5;
const MAX_BODY = 4096;
const MAX_ATTACHMENTS = 5;
const ATTACH_TTL_MS = 2 * 60 * 60 * 1000;
const ATTACH_TYPES = { 'image/jpeg': ['photo', 'jpg', 8 * 1024 * 1024], 'image/png': ['photo', 'png', 8 * 1024 * 1024], 'video/mp4': ['video', 'mp4', 21 * 1024 * 1024], 'video/quicktime': ['video', 'mov', 21 * 1024 * 1024] };

const SOURCES = new Set(['sideload', 'enterprise', 'testflight', 'appstore', 'unknown']);
const STATUSES = new Set(['official', 'modified', 'unknown', 'checking']);

function text(value, max) {
  if (typeof value !== 'string' && typeof value !== 'number') {
    return '';
  }
  return String(value).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);
}

export function cleanAccounts(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return [...new Set(value.filter((item) => typeof item === 'string' && /^[0-9a-f]{32}$/.test(item)))].slice(0, 8);
}

export async function accountHash(id) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('ayugram-account|' + id));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, '0')).join('').slice(0, 32);
}

export function cleanInstall(body, country, now) {
  if (!body || typeof body !== 'object') {
    return null;
  }
  const id = text(body.id, 64);
  if (!/^[A-Za-z0-9-]{8,64}$/.test(id)) {
    return null;
  }
  const source = text(body.source, 16);
  const status = text(body.status, 16);
  return {
    id,
    build: Number.parseInt(text(body.build, 12), 10) || 0,
    variant: text(body.variant, 16),
    source: SOURCES.has(source) ? source : 'unknown',
    status: STATUSES.has(status) ? status : 'unknown',
    team: text(body.team, 32),
    teamName: text(body.teamName, 120),
    cert: text(body.cert, 160),
    profile: text(body.profile, 120),
    bundle: text(body.bundle, 160),
    os: text(body.os, 40),
    device: text(body.device, 40),
    devices: Math.min(Math.max(Number.parseInt(text(body.devices, 6), 10) || 0, 0), 100000),
    accounts: cleanAccounts(body.accounts),
    country: text(country, 4) || '??',
    seen: now,
  };
}

export function cleanReport(body, country, now) {
  if (!body || typeof body !== 'object') {
    return null;
  }
  const id = text(body.id, 64);
  const message = text(body.text, 600);
  if (!/^[A-Za-z0-9-]{8,64}$/.test(id) || message.length < 2) {
    return null;
  }
  const install = cleanInstall(body, country, now);
  const target = text(body.target, 20);
  return {
    id,
    text: message,
    target: /^[1-9][0-9]{0,19}$/.test(target) ? target : '',
    targetName: text(body.targetName, 160),
    attachments: Math.min(Math.max(Number.parseInt(text(body.attachments, 2), 10) || 0, 0), MAX_ATTACHMENTS),
    build: install ? install.build : 0,
    source: install ? install.source : 'unknown',
    status: install ? install.status : 'unknown',
    team: install ? install.team : '',
    teamName: install ? install.teamName : '',
    country: text(country, 4) || '??',
    time: now,
  };
}

function bump(map, key) {
  const name = key === '' || key === undefined ? '-' : String(key);
  map[name] = (map[name] || 0) + 1;
}

function addUnique(list, value) {
  if (value && !list.includes(value) && list.length < 10) {
    list.push(value);
  }
}

export function summarize(installs, reports, now) {
  const summary = { total: 0, active7d: 0, bySource: {}, byStatus: {}, byBuild: {}, byCountry: {}, teams: [], reports: [] };
  const teams = new Map();
  for (const install of installs) {
    summary.total += 1;
    if (now - install.seen < 7 * 24 * 60 * 60 * 1000) {
      summary.active7d += 1;
    }
    bump(summary.bySource, install.source);
    bump(summary.byStatus, install.status);
    bump(summary.byBuild, install.build);
    bump(summary.byCountry, install.country);
    const key = install.team || '-';
    let team = teams.get(key);
    if (!team) {
      team = { team: key, installs: 0, devices: 0, names: [], certs: [], profiles: [], bundles: [], countries: {}, sources: {}, statuses: {}, builds: {}, lastSeen: 0 };
      teams.set(key, team);
    }
    team.installs += 1;
    team.devices = Math.max(team.devices, install.devices || 0);
    addUnique(team.names, install.teamName);
    addUnique(team.certs, install.cert);
    addUnique(team.profiles, install.profile);
    addUnique(team.bundles, install.bundle);
    bump(team.countries, install.country);
    bump(team.sources, install.source);
    bump(team.statuses, install.status);
    bump(team.builds, install.build);
    team.lastSeen = Math.max(team.lastSeen, install.seen);
  }
  summary.teams = [...teams.values()].sort((a, b) => b.installs - a.installs || b.lastSeen - a.lastSeen);
  summary.reports = [...reports].sort((a, b) => b.time - a.time).slice(0, 100).map((report) => ({
    time: new Date(report.time).toISOString(),
    text: report.text,
    team: report.team,
    teamName: report.teamName,
    source: report.source,
    status: report.status,
    build: report.build,
    country: report.country,
    targetName: report.targetName || '',
  }));
  return summary;
}

export class Stats {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const storage = this.state.storage;
    const now = Date.now();
    if (request.method === 'POST' && url.pathname === '/ping') {
      const install = await request.json();
      const previous = await storage.get('i:' + install.id);
      install.first = previous && previous.first ? previous.first : install.seen;
      await storage.put('i:' + install.id, install);
      return new Response('ok\n');
    }
    if (request.method === 'POST' && url.pathname === '/status') {
      const body = await request.json();
      let banned = false;
      let warning = null;
      for (const hash of cleanAccounts(body.accounts)) {
        if (await storage.get('ban:' + hash)) {
          banned = true;
        }
        const warn = await storage.get('warn:' + hash);
        if (warn && (!warning || warn.time > warning.time)) {
          warning = warn;
        }
      }
      return Response.json({ banned, warning: warning ? warning.id : null });
    }
    if (request.method === 'GET' && url.pathname.startsWith('/review/')) {
      const review = await this.review(url.pathname.slice(8));
      return review ? Response.json(review) : new Response('not found\n', { status: 404 });
    }
    if (request.method === 'POST' && url.pathname.startsWith('/moderate/')) {
      const [, , action, rid] = url.pathname.split('/');
      const review = await this.review(rid);
      if (!review) {
        return new Response('not found\n', { status: 404 });
      }
      if (!review.target) {
        return new Response('no target\n', { status: 409 });
      }
      const hash = review.target.hash;
      if (action === 'warn') {
        await storage.put('warn:' + hash, { id: rid + '-' + now, time: now, rid });
      } else if (action === 'ban') {
        await storage.put('ban:' + hash, { time: now, rid });
      } else if (action === 'unban') {
        await storage.delete('ban:' + hash);
      } else {
        return new Response('not found\n', { status: 404 });
      }
      return Response.json(await this.review(rid));
    }
    if (request.method === 'POST' && url.pathname === '/report') {
      const report = await request.json();
      const day = Math.floor(now / 86400000);
      const limitKey = 'l:' + report.id + ':' + day;
      const count = (await storage.get(limitKey)) || 0;
      if (count >= REPORTS_PER_DAY) {
        return new Response('limit\n', { status: 429 });
      }
      await storage.put(limitKey, count + 1);
      report.rid = crypto.randomUUID().replace(/-/g, '').slice(0, 12);
      const key = 'r:' + String(now).padStart(15, '0') + ':' + report.id + ':' + report.rid;
      await storage.put(key, report);
      await storage.put('q:' + report.rid, key);
      const token = crypto.randomUUID().replace(/-/g, '');
      await storage.put('t:' + report.rid, { token, used: 0, time: now });
      return Response.json({ ok: true, rid: report.rid, token });
    }
    if (request.method === 'POST' && url.pathname.startsWith('/notice/')) {
      const rid = url.pathname.slice(8);
      const body = await request.json();
      const ticket = await storage.get('t:' + rid);
      if (ticket) {
        ticket.notice = body.messageId;
        await storage.put('t:' + rid, ticket);
      }
      return new Response('ok\n');
    }
    if (request.method === 'POST' && url.pathname.startsWith('/attach/')) {
      const rid = url.pathname.slice(8);
      const ticket = await storage.get('t:' + rid);
      const token = request.headers.get('x-ayugram-token') || '';
      if (!ticket || !token || ticket.token !== token || now - ticket.time > ATTACH_TTL_MS) {
        return new Response('forbidden\n', { status: 403 });
      }
      if (ticket.used >= MAX_ATTACHMENTS) {
        return new Response('limit\n', { status: 429 });
      }
      ticket.used += 1;
      await storage.put('t:' + rid, ticket);
      const key = await storage.get('q:' + rid);
      const report = key ? await storage.get(key) : null;
      return Response.json({ notice: ticket.notice || 0, index: ticket.used, targetName: report ? report.targetName || '' : '' });
    }
    if (request.method === 'GET' && url.pathname === '/summary') {
      const installs = [];
      const stale = [];
      for (const [key, value] of await storage.list({ prefix: 'i:' })) {
        if (now - value.seen > INSTALL_TTL_MS) {
          stale.push(key);
        } else {
          installs.push(value);
        }
      }
      const reports = [];
      for (const [key, value] of await storage.list({ prefix: 'r:' })) {
        if (now - value.time > REPORT_TTL_MS) {
          stale.push(key);
          if (value.rid) {
            stale.push('q:' + value.rid, 't:' + value.rid);
          }
        } else {
          reports.push(value);
        }
      }
      for (const [key] of await storage.list({ prefix: 'l:' })) {
        if (Number(key.split(':').pop()) < Math.floor(now / 86400000) - 1) {
          stale.push(key);
        }
      }
      for (let index = 0; index < stale.length; index += 128) {
        await storage.delete(stale.slice(index, index + 128));
      }
      return Response.json(summarize(installs, reports, now));
    }
    return new Response('not found\n', { status: 404 });
  }

  async review(rid) {
    if (!/^[0-9a-f]{12}$/.test(rid || '')) {
      return null;
    }
    const storage = this.state.storage;
    const key = await storage.get('q:' + rid);
    const report = key ? await storage.get(key) : null;
    if (!report) {
      return null;
    }
    const reporter = (await storage.get('i:' + report.id)) || null;
    const ticket = await storage.get('t:' + rid);
    report.received = ticket ? ticket.used : 0;
    let target = null;
    if (report.target) {
      const hash = await accountHash(report.target);
      const installs = [];
      for (const [, value] of await storage.list({ prefix: 'i:' })) {
        if ((value.accounts || []).includes(hash)) {
          installs.push(value);
        }
      }
      installs.sort((a, b) => b.seen - a.seen);
      target = {
        id: report.target,
        name: report.targetName || '',
        hash,
        installs: installs.map(({ id, accounts, ...rest }) => rest),
        ban: (await storage.get('ban:' + hash)) || null,
        warning: (await storage.get('warn:' + hash)) || null,
      };
    }
    let reporterInstall = null;
    if (reporter) {
      const { id, accounts, ...rest } = reporter;
      reporterInstall = rest;
    }
    const { id, ...publicReport } = report;
    return { report: publicReport, reporter: reporterInstall, target };
  }
}

export function statsStub(env) {
  return env && env.STATS ? env.STATS.get(env.STATS.idFromName('global')) : null;
}

async function readBody(request) {
  const raw = await request.text();
  if (raw.length > MAX_BODY) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function sameToken(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length || !a) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return diff === 0;
}

export function reportMessage(report) {
  const lines = ['🚨 Жалоба на скам', '', report.text, ''];
  if (report.attachments) {
    lines.push('Вложений: ' + report.attachments + ' (придут ответом на это сообщение)');
  }
  if (report.target || report.targetName) {
    lines.push('На кого: ' + (report.targetName || '-') + (report.target ? ' (ID ' + report.target + ')' : ''));
  }
  lines.push(['Сборка ' + (report.build || '?'), report.status, report.source, report.country].join(' · '));
  if (report.team) {
    lines.push('Сертификат: ' + report.team + (report.teamName ? ' (' + report.teamName + ')' : ''));
  }
  return lines.join('\n');
}

export async function notifyReport(report, env) {
  if (!env || !env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
    return false;
  }
  const response = await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/sendMessage', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      chat_id: env.REPORT_CHAT_ID,
      text: reportMessage(report),
      link_preview_options: { is_disabled: true },
      reply_markup: report.rid ? { inline_keyboard: [[{ text: '🔎 Рассмотреть жалобу', callback_data: 'v:' + report.rid }]] } : undefined,
    }),
  });
  if (!response.ok) {
    console.log('report not sent to Telegram: ' + response.status);
    return false;
  }
  const sent = await response.json().catch(() => null);
  const stub = statsStub(env);
  if (stub && report.rid && sent && sent.result && sent.result.message_id) {
    await stub.fetch('https://stats.ayugram.invalid/notice/' + report.rid, { method: 'POST', body: JSON.stringify({ messageId: sent.result.message_id }) });
  }
  return true;
}

async function forwardAttachment(env, kind, extension, type, bytes, info) {
  const caption = '📎 Вложение ' + info.index + ' к жалобе' + (info.targetName ? ' на ' + info.targetName : '');
  const send = async (method, field) => {
    const form = new FormData();
    form.append('chat_id', String(env.REPORT_CHAT_ID));
    form.append('caption', caption);
    if (info.notice) {
      form.append('reply_parameters', JSON.stringify({ message_id: info.notice, allow_sending_without_reply: true }));
    }
    form.append(field, new Blob([bytes], { type }), 'attachment-' + info.index + '.' + extension);
    const response = await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/' + method, { method: 'POST', body: form });
    if (!response.ok) {
      console.log('attachment not sent with ' + method + ': ' + response.status);
    }
    return response.ok;
  };
  return (await send(kind === 'photo' ? 'sendPhoto' : 'sendVideo', kind)) || send('sendDocument', 'document');
}

export async function handleStats(request, env, url, ctx) {
  const stub = statsStub(env);
  if (!stub) {
    return new Response('stats unavailable\n', { status: 503 });
  }
  const country = request.cf && request.cf.country ? request.cf.country : '';
  const now = Date.now();
  if (request.method === 'POST' && url.pathname === '/stats/ping') {
    const install = cleanInstall(await readBody(request), country, now);
    if (!install) {
      return new Response('bad request\n', { status: 400 });
    }
    return stub.fetch('https://stats.ayugram.invalid/ping', { method: 'POST', body: JSON.stringify(install) });
  }
  if (request.method === 'POST' && url.pathname === '/stats/report') {
    const report = cleanReport(await readBody(request), country, now);
    if (!report) {
      return new Response('bad request\n', { status: 400 });
    }
    const response = await stub.fetch('https://stats.ayugram.invalid/report', { method: 'POST', body: JSON.stringify(report) });
    if (response.ok) {
      const stored = await response.clone().json().catch(() => ({}));
      report.rid = stored.rid || '';
      const notify = notifyReport(report, env).catch((error) => console.log('report not sent to Telegram: ' + error));
      if (ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil(notify);
      } else {
        await notify;
      }
    }
    return response;
  }
  if (request.method === 'POST' && url.pathname.startsWith('/stats/attach/')) {
    const rid = url.pathname.slice(14);
    const type = (request.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
    const spec = ATTACH_TYPES[type];
    if (!/^[0-9a-f]{12}$/.test(rid) || !spec) {
      return new Response('bad request\n', { status: 400 });
    }
    if (!env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
      return new Response('attachments unavailable\n', { status: 503 });
    }
    const declared = Number(request.headers.get('content-length') || 0);
    if (declared > spec[2]) {
      return new Response('too large\n', { status: 413 });
    }
    const bytes = await request.arrayBuffer();
    if (!bytes.byteLength || bytes.byteLength > spec[2]) {
      return new Response('too large\n', { status: 413 });
    }
    const checked = await stub.fetch('https://stats.ayugram.invalid/attach/' + rid, { method: 'POST', headers: { 'x-ayugram-token': request.headers.get('x-ayugram-token') || '' } });
    if (!checked.ok) {
      return new Response(await checked.text(), { status: checked.status });
    }
    const info = await checked.json();
    const sent = await forwardAttachment(env, spec[0], spec[1], type, bytes, info);
    return sent ? new Response('ok\n') : new Response('not delivered\n', { status: 502 });
  }
  if (request.method === 'POST' && url.pathname === '/stats/status') {
    const body = await readBody(request);
    if (!body || !/^[A-Za-z0-9-]{8,64}$/.test(text(body.id, 64))) {
      return new Response('bad request\n', { status: 400 });
    }
    return stub.fetch('https://stats.ayugram.invalid/status', { method: 'POST', body: JSON.stringify({ accounts: cleanAccounts(body.accounts) }) });
  }
  if (request.method === 'GET' && url.pathname === '/stats/summary') {
    const header = request.headers.get('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!sameToken(token, env.STATS_TOKEN)) {
      return new Response('forbidden\n', { status: 403 });
    }
    return stub.fetch('https://stats.ayugram.invalid/summary');
  }
  return new Response('not found\n', { status: 404 });
}
