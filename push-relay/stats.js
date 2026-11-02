const INSTALL_TTL_MS = 60 * 24 * 60 * 60 * 1000;
const REPORT_TTL_MS = 180 * 24 * 60 * 60 * 1000;
const REPORTS_PER_DAY = 5;
const MAX_BODY = 4096;

const SOURCES = new Set(['sideload', 'enterprise', 'testflight', 'appstore', 'unknown']);
const STATUSES = new Set(['official', 'modified', 'unknown', 'checking']);

function text(value, max) {
  if (typeof value !== 'string' && typeof value !== 'number') {
    return '';
  }
  return String(value).replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);
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
  return {
    id,
    text: message,
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
      await storage.put('i:' + install.id, install);
      return new Response('ok\n');
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
      await storage.put('r:' + String(now).padStart(15, '0') + ':' + report.id + ':' + crypto.randomUUID(), report);
      return new Response('ok\n');
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
}

function statsStub(env) {
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
    body: JSON.stringify({ chat_id: env.REPORT_CHAT_ID, text: reportMessage(report), link_preview_options: { is_disabled: true } }),
  });
  if (!response.ok) {
    console.log('report not sent to Telegram: ' + response.status);
  }
  return response.ok;
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
      const notify = notifyReport(report, env).catch((error) => console.log('report not sent to Telegram: ' + error));
      if (ctx && typeof ctx.waitUntil === 'function') {
        ctx.waitUntil(notify);
      } else {
        await notify;
      }
    }
    return response;
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
