export const PLUGIN_PERMISSIONS = ['messages.read', 'messages.send', 'messages.intercept', 'account.basic', 'ui.inject', 'network.client', 'notifications'];

const MAX_FILES = 64;
const MAX_UNPACKED = 4194304;
const LEVELS = { info: 0, warn: 1, danger: 2 };

const API_PERMISSION = [
  [/\bwg\s*\.\s*messages\s*\.\s*(?:getList|currentChat)\b/, 'messages.read'],
  [/\bwg\s*\.\s*events\s*\.\s*on\s*\(\s*['"`](?:message\.|\*)/, 'messages.read'],
  [/\bwg\s*\.\s*messages\s*\.\s*send\b/, 'messages.send'],
  [/\bwg\s*\.\s*intercept\b/, 'messages.intercept'],
  [/\bwg\s*\.\s*(?:accounts\s*\.\s*getMe|tg\s*\.\s*myId)\b/, 'account.basic'],
  [/\bwg\s*\.\s*(?:menu|ui)\s*\./, 'ui.inject'],
  [/\bwg\s*\.\s*net\s*\.\s*fetch\b/, 'network.client'],
  [/\bwg\s*\.\s*notifications\s*\.\s*show\b/, 'notifications'],
];

const EXFIL_HOSTS = /(?:api\.telegram\.org\/bot|webhook\.site|requestbin|pipedream\.net|discord(?:app)?\.com\/api\/webhooks|ngrok(?:-free)?\.(?:io|app|dev)|trycloudflare\.com|hookdeck\.com|beeceptor\.com|interact\.sh|oast\.(?:fun|me|pro|site|live|online)|burpcollaborator\.net|pastebin\.com\/api|transfer\.sh|file\.io|ipinfo\.io|ip-api\.com|ipify\.org|canarytokens|requestcatcher\.com|mockbin|serveo\.net|localtunnel\.me|loca\.lt)/i;
const LOGIN_WORDS = /(?:(?:login|auth|confirmation|verification|sms|one[- ]?time)\s*code|код\s+(?:входа|подтверждения|авторизации)|auth_?key|session\s*string|string\s*session|tdata|two[- ]?step|2fa|cloud\s*password|облачн\w*\s+парол|passcode|seed\s*phrase|mnemonic|сид[- ]?фраз|private\s*key|приватн\w*\s+ключ)/i;
const WALLET = /(?:\b(?:UQ|EQ)[A-Za-z0-9_-]{46}\b|\bbc1[a-z0-9]{25,60}\b|\b0x[a-fA-F0-9]{40}\b|\bT[1-9A-HJ-NP-Za-km-z]{33}\b|\b[13][1-9A-HJ-NP-Za-km-z]{25,34}\b)/;
const INVITE = /(?:t(?:elegram)?\.me\/(?:\+|joinchat\/)|tg:\/\/join\b|tg:\/\/addstickers|tg:\/\/resolve\?[^'"`]*start=)/i;
const PAYMENT = /(?:ton:\/\/transfer|tonkeeper\.com\/transfer|app\.tonkeeper|bitcoin:|ethereum:|tg:\/\/invoice|t\.me\/\$|t\.me\/invoice|wallet\.tg|t\.me\/wallet|t\.me\/send\?start=|t\.me\/CryptoBot\?start=)/i;
const SENSITIVE_PROMPT = /(?:code|код|password|пароль|парол|phone|телефон|номер|passcode|seed|mnemonic|ключ|key)/i;

function lineOf(text, index) {
  let line = 1;
  for (let i = 0; i < index && i < text.length; i += 1) {
    if (text.charCodeAt(i) === 10) {
      line += 1;
    }
  }
  return line;
}

function snippet(text, index) {
  const start = Math.max(0, index - 40);
  return text.slice(start, Math.min(text.length, index + 80)).replace(/\s+/g, ' ').trim().slice(0, 140);
}

function stripComments(text) {
  let out = '';
  let i = 0;
  let quote = '';
  while (i < text.length) {
    const c = text[i];
    const n = text[i + 1];
    if (quote) {
      out += c;
      if (c === '\\') {
        out += n === undefined ? '' : n;
        i += 2;
        continue;
      }
      if (c === quote) {
        quote = '';
      }
      i += 1;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      quote = c;
      out += c;
      i += 1;
      continue;
    }
    if (c === '/' && n === '/') {
      while (i < text.length && text[i] !== '\n') {
        out += ' ';
        i += 1;
      }
      continue;
    }
    if (c === '/' && n === '*') {
      out += '  ';
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) {
        out += text[i] === '\n' ? '\n' : ' ';
        i += 1;
      }
      out += '  ';
      i += 2;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

export function parseHeader(source) {
  const fields = {};
  for (const raw of String(source || '').split(/\r?\n/).slice(0, 60)) {
    const line = raw.trim();
    if (!line.startsWith('//')) {
      if (!line || line.startsWith('/*') || line.startsWith('*')) {
        continue;
      }
      break;
    }
    const body = line.slice(2).trim();
    if (!body.startsWith('@')) {
      continue;
    }
    const match = /^@(\S+)\s+(.+)$/.exec(body);
    if (match) {
      fields[match[1].toLowerCase()] = match[2].trim();
    }
  }
  return fields;
}

function splitList(value) {
  if (Array.isArray(value)) {
    return value.map((item) => (typeof item === 'string' ? item : item && typeof item.id === 'string' ? item.id : '')).map((item) => item.trim()).filter(Boolean);
  }
  return String(value || '').split(/[,\s]+/).map((item) => item.trim()).filter(Boolean);
}

export function slugify(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^[^a-z0-9]+|[^a-z0-9]+$/g, '').slice(0, 48);
}

export function pluginInfo(files, manifest, fallbackName) {
  const main = files.find((file) => file.main) || files[0];
  const fields = parseHeader(main ? main.text : '');
  const name = String((manifest && typeof manifest.name === 'string' && manifest.name) || fields.name || fallbackName || '').trim().slice(0, 60);
  const rawId = (manifest && typeof manifest.id === 'string' && manifest.id) || fields.id || name;
  const permissions = splitList(manifest && manifest.permissions !== undefined ? manifest.permissions : fields.permissions).filter((item) => PLUGIN_PERMISSIONS.includes(item));
  const domains = splitList(manifest && manifest.domains !== undefined ? manifest.domains : fields.domains).filter((item) => item.includes('.')).map((item) => item.toLowerCase().slice(0, 120)).slice(0, 40);
  return {
    id: slugify(rawId),
    name,
    version: String((manifest && typeof manifest.version === 'string' && manifest.version) || fields.version || '1.0').trim().slice(0, 24),
    description: String((manifest && typeof manifest.description === 'string' && manifest.description) || fields.description || '').trim().slice(0, 300),
    permissions: [...new Set(permissions)],
    domains: [...new Set(domains)],
  };
}

export function compareVersions(a, b) {
  const left = String(a || '0').split(/[.\-+]/).map((part) => Number.parseInt(part, 10) || 0);
  const right = String(b || '0').split(/[.\-+]/).map((part) => Number.parseInt(part, 10) || 0);
  for (let i = 0; i < Math.max(left.length, right.length); i += 1) {
    const diff = (left[i] || 0) - (right[i] || 0);
    if (diff) {
      return diff > 0 ? 1 : -1;
    }
  }
  return 0;
}

async function inflateRaw(bytes) {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
  const reader = stream.getReader();
  const parts = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }
    total += value.byteLength;
    if (total > MAX_UNPACKED) {
      await reader.cancel().catch(() => null);
      throw new Error('too_large');
    }
    parts.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const part of parts) {
    out.set(part, at);
    at += part.byteLength;
  }
  return out;
}

export async function readZip(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let end = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 65557); i -= 1) {
    if (view.getUint32(i, true) === 0x06054b50) {
      end = i;
      break;
    }
  }
  if (end < 0) {
    throw new Error('bad_zip');
  }
  const count = view.getUint16(end + 10, true);
  let offset = view.getUint32(end + 16, true);
  if (count > MAX_FILES) {
    throw new Error('too_many_files');
  }
  const entries = [];
  let total = 0;
  const decoder = new TextDecoder();
  for (let n = 0; n < count; n += 1) {
    if (offset + 46 > bytes.length || view.getUint32(offset, true) !== 0x02014b50) {
      throw new Error('bad_zip');
    }
    const flags = view.getUint16(offset + 8, true);
    const method = view.getUint16(offset + 10, true);
    const compressed = view.getUint32(offset + 20, true);
    const size = view.getUint32(offset + 24, true);
    const nameLength = view.getUint16(offset + 28, true);
    const extraLength = view.getUint16(offset + 30, true);
    const commentLength = view.getUint16(offset + 32, true);
    const local = view.getUint32(offset + 42, true);
    const name = decoder.decode(bytes.subarray(offset + 46, offset + 46 + nameLength));
    offset += 46 + nameLength + extraLength + commentLength;
    if (name.endsWith('/')) {
      continue;
    }
    if (flags & 1) {
      throw new Error('encrypted_zip');
    }
    if (name.includes('..') || name.startsWith('/') || name.includes('\\') || name.includes('\0')) {
      throw new Error('bad_path');
    }
    total += size;
    if (total > MAX_UNPACKED) {
      throw new Error('too_large');
    }
    if (local + 30 > bytes.length || view.getUint32(local, true) !== 0x04034b50) {
      throw new Error('bad_zip');
    }
    const start = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
    const data = bytes.subarray(start, start + compressed);
    if (data.length !== compressed) {
      throw new Error('bad_zip');
    }
    let content;
    if (method === 0) {
      content = data;
    } else if (method === 8) {
      content = await inflateRaw(data);
    } else {
      throw new Error('bad_zip');
    }
    entries.push({ name, bytes: content });
  }
  return entries;
}

export async function unpackPlugin(bytes, fileName) {
  const lower = String(fileName || '').toLowerCase();
  const isZip = bytes.length > 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04;
  const fallbackName = String(fileName || 'plugin').replace(/\.[^.]+$/, '');
  if (!isZip) {
    if (!/\.(js|plugin|txt)$/.test(lower) && lower) {
      return { error: 'unsupported_file' };
    }
    let text;
    try {
      text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    } catch {
      return { error: 'not_text' };
    }
    if (!text.trim()) {
      return { error: 'empty' };
    }
    const files = [{ name: 'main.js', text, main: true }];
    return { kind: 'js', ext: 'js', files, manifest: null, info: pluginInfo(files, null, fallbackName), extras: [] };
  }
  let entries;
  try {
    entries = await readZip(bytes);
  } catch (error) {
    return { error: String(error && error.message ? error.message : 'bad_zip') };
  }
  const prefix = (() => {
    if (entries.some((entry) => entry.name === 'plugin.json')) {
      return '';
    }
    const tops = new Set(entries.map((entry) => entry.name.split('/')[0]));
    return tops.size === 1 && entries.every((entry) => entry.name.includes('/')) ? [...tops][0] + '/' : '';
  })();
  const relative = entries.map((entry) => ({ name: entry.name.slice(prefix.length), bytes: entry.bytes }));
  let manifest = {};
  const manifestEntry = relative.find((entry) => entry.name === 'plugin.json');
  if (manifestEntry) {
    try {
      const parsed = JSON.parse(new TextDecoder().decode(manifestEntry.bytes));
      manifest = parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
    } catch {
      return { error: 'bad_manifest' };
    }
  }
  const entry = String(manifest.main || (manifest.entryPoints && manifest.entryPoints.main) || 'main.js');
  if (entry.includes('..')) {
    return { error: 'bad_path' };
  }
  const decoder = new TextDecoder();
  const files = [];
  const extras = [];
  for (const item of relative) {
    if (/\.(m?js|json|txt|html?|css)$/i.test(item.name)) {
      files.push({ name: item.name, text: decoder.decode(item.bytes), main: item.name === entry });
    } else {
      extras.push({ name: item.name, size: item.bytes.length });
    }
  }
  if (!files.some((file) => file.main)) {
    return { error: 'no_source' };
  }
  files.sort((a, b) => Number(b.main) - Number(a.main));
  return { kind: 'zip', ext: 'zip', files, manifest, info: pluginInfo(files, manifest, fallbackName), extras };
}

function hostOf(url) {
  const match = /^[a-z][a-z0-9+.-]*:\/\/([^/?#:'"`\s]+)/i.exec(url);
  return match ? match[1].toLowerCase() : '';
}

function domainAllowed(host, domains) {
  return domains.some((rule) => (rule.startsWith('*.') ? host === rule.slice(2) || host.endsWith(rule.slice(1)) : host === rule));
}

export function scanPlugin(unpacked) {
  const findings = [];
  const seen = new Set();
  const info = unpacked.info;
  const permissions = new Set(info.permissions);
  const add = (level, code, text, file, index) => {
    const key = code + '|' + (file ? file.name : '');
    if (seen.has(key)) {
      return;
    }
    seen.add(key);
    findings.push({ level, code, text, file: file ? file.name : '', line: file && index !== undefined ? lineOf(file.text, index) : 0, snippet: file && index !== undefined ? snippet(file.text, index) : '' });
  };
  const used = new Set();
  const flags = {};
  const scripts = unpacked.files.filter((file) => /\.m?js$/i.test(file.name) || file.main);
  for (const file of unpacked.files) {
    if (!/\.m?js$/i.test(file.name) && !file.main && /\.(html?)$/i.test(file.name) && /<script/i.test(file.text)) {
      add('warn', 'html_script', 'В пакете есть HTML со скриптами', file, file.text.search(/<script/i));
    }
  }
  for (const file of scripts) {
    const code = stripComments(file.text);
    const at = (pattern) => {
      const match = pattern.exec(code);
      return match ? match.index : -1;
    };
    const has = (pattern) => at(pattern) >= 0;
    for (const [pattern, permission] of API_PERMISSION) {
      if (has(pattern)) {
        used.add(permission);
      }
    }
    let index;
    if ((index = at(/\b__ayu\b/)) >= 0) {
      add('danger', 'native_bridge', 'Лезет во внутренний мост __ayu в обход wg', file, index);
    }
    if ((index = at(/\beval\s*\(|\bnew\s+Function\s*\(|(?<![.\w$])Function\s*\(\s*['"`]|\[\s*['"`]constructor['"`]\s*\]|\.constructor\s*\(\s*['"`]|\bimport\s*\(/)) >= 0) {
      add('danger', 'dynamic_code', 'Выполняет строку как код (eval, new Function, constructor)', file, index);
    }
    if ((index = at(/\bset(?:Timeout|Interval)\s*\(\s*['"`]/)) >= 0) {
      add('warn', 'string_timer', 'Передаёт строку с кодом в таймер', file, index);
    }
    if ((index = at(/\b_0x[0-9a-f]{4,6}\b/i)) >= 0) {
      add('danger', 'obfuscated', 'Код прогнан через обфускатор (_0x…)', file, index);
    }
    const hexEscapes = (code.match(/\\x[0-9a-fA-F]{2}/g) || []).length;
    const uniEscapes = (code.match(/\\u[0-9a-fA-F]{4}/g) || []).length;
    if (hexEscapes + uniEscapes > 60) {
      add('danger', 'escaped_strings', 'Много закодированных строк (\\x / \\u), содержимое спрятано', file, at(/\\[xu][0-9a-fA-F]{2}/));
    } else if (hexEscapes + uniEscapes > 15) {
      add('warn', 'escaped_strings', 'Есть закодированные строки (\\x / \\u)', file, at(/\\[xu][0-9a-fA-F]{2}/));
    }
    const charCodes = (code.match(/fromCharCode/g) || []).length;
    if (charCodes > 2) {
      add('warn', 'char_codes', 'Собирает строки из кодов символов (String.fromCharCode)', file, at(/fromCharCode/));
    }
    const blob = at(/['"`][A-Za-z0-9+/=_-]{300,}['"`]/);
    if (blob >= 0) {
      add('warn', 'encoded_blob', 'Длинная закодированная строка (base64 / hex)', file, blob);
    }
    if ((index = at(/\batob\s*\(|\bBuffer\.from\s*\([^)]*['"`]base64['"`]/)) >= 0) {
      flags.decode = true;
      add('warn', 'decode', 'Раскодирует base64 во время работы', file, index);
    }
    if (code.split('\n').some((line) => line.length > 3000)) {
      add('warn', 'minified', 'Код сжат в очень длинные строки, его тяжело проверить', file, 0);
    }
    if ((index = at(/\b777000\b|\b42777\b/)) >= 0) {
      flags.service = true;
      add('danger', 'service_chat', 'Обращается к служебному чату Telegram 777000, куда приходят коды входа', file, index);
    }
    if ((index = at(LOGIN_WORDS)) >= 0) {
      flags.login = index;
      flags.loginFile = file;
    }
    if ((index = at(EXFIL_HOSTS)) >= 0) {
      add('danger', 'exfil_host', 'Отправляет данные на сервис-приёмник (бот Telegram, вебхук, туннель, определение IP)', file, index);
    }
    if ((index = at(/['"`]https?:\/\/(?:\d{1,3}\.){3}\d{1,3}/)) >= 0) {
      add('warn', 'raw_ip', 'Обращается к серверу по голому IP-адресу', file, index);
    }
    if (has(/clipboardSet\s*\(/) && (index = at(WALLET)) >= 0) {
      add('danger', 'clipboard_wallet', 'Пишет в буфер обмена и содержит адрес кошелька: похоже на подмену реквизитов', file, index);
    } else if ((index = at(/clipboardSet\s*\(/)) >= 0) {
      add('info', 'clipboard_write', 'Пишет в буфер обмена', file, index);
    }
    if ((index = at(/clipboardGet\s*\(/)) >= 0) {
      flags.clipboard = index;
      flags.clipboardFile = file;
      add('warn', 'clipboard_read', 'Читает буфер обмена', file, index);
    }
    const promptAt = at(/\bwg\s*\.\s*ui\s*\.\s*prompt\s*\(/);
    if (promptAt >= 0) {
      const around = code.slice(promptAt, promptAt + 300);
      if (SENSITIVE_PROMPT.test(around)) {
        add('danger', 'phishing_prompt', 'Просит ввести код, пароль, номер или ключ — так крадут аккаунты', file, promptAt);
      }
    }
    if ((index = at(INVITE)) >= 0) {
      add('warn', 'invite_link', 'Открывает или рассылает ссылки-приглашения и старт ботов', file, index);
    }
    if ((index = at(PAYMENT)) >= 0) {
      add('warn', 'payment_link', 'Содержит ссылки на оплату или перевод', file, index);
    }
    const sendAt = at(/\bwg\s*\.\s*messages\s*\.\s*send\s*\(\s*(?:['"`]?-?\d{5,}['"`]?|['"`]@?[A-Za-z][A-Za-z0-9_]{4,}['"`])/);
    if (sendAt >= 0) {
      flags.hardcodedSend = sendAt;
      flags.hardcodedFile = file;
    }
    const loopSend = /(?:for\s*\(|while\s*\(|\.forEach\s*\(|\.map\s*\()[\s\S]{0,400}?\bwg\s*\.\s*messages\s*\.\s*send\s*\(/.exec(code);
    if (loopSend) {
      add('warn', 'mass_send', 'Отправляет сообщения в цикле: возможна рассылка', file, loopSend.index);
    }
    if ((index = at(/\bwg\s*\.\s*system\s*\.\s*openURL\s*\(/)) >= 0) {
      add('info', 'open_url', 'Открывает ссылки', file, index);
    }
    if ((index = at(/Object\s*\.\s*defineProperty\s*\(\s*(?:globalThis|wg)\b|globalThis\s*\.\s*wg\s*=|\bwg\s*=[^=]/)) >= 0) {
      add('warn', 'api_override', 'Переопределяет API wg', file, index);
    }
    for (const match of code.matchAll(/['"`](https?:\/\/[^'"`\s]+)/g)) {
      const host = hostOf(match[1]);
      if (host && !domainAllowed(host, info.domains) && used.has('network.client')) {
        add('info', 'undeclared_domain', 'Обращается к домену ' + host + ', которого нет в @domains (запрос будет заблокирован)', file, match.index);
      }
    }
  }
  if (flags.login !== undefined) {
    const risky = permissions.has('network.client') || permissions.has('messages.send') || flags.clipboard !== undefined;
    add(risky ? 'danger' : 'warn', 'credentials', risky ? 'Упоминает коды входа, пароли или ключи и при этом может отправлять данные наружу' : 'Упоминает коды входа, пароли или ключи', flags.loginFile, flags.login);
  }
  if (flags.hardcodedSend !== undefined) {
    const reads = permissions.has('messages.read') || permissions.has('messages.intercept');
    add(reads ? 'danger' : 'warn', 'hardcoded_target', reads ? 'Читает переписку и отправляет сообщения в заранее зашитый чат — так сливают переписку' : 'Отправляет сообщения в заранее зашитый чат', flags.hardcodedFile, flags.hardcodedSend);
  }
  if (flags.clipboard !== undefined && permissions.has('network.client')) {
    add('danger', 'clipboard_exfil', 'Читает буфер обмена и имеет доступ в интернет', flags.clipboardFile, flags.clipboard);
  }
  if (flags.decode && findings.some((item) => item.code === 'encoded_blob')) {
    add('danger', 'hidden_payload', 'Раскодирует спрятанную строку во время работы', null);
  }
  if (permissions.has('network.client') && (permissions.has('messages.read') || permissions.has('messages.intercept'))) {
    add('warn', 'read_and_network', 'Может читать сообщения и ходить в интернет: проверь, куда уходят данные', null);
  }
  if (info.domains.some((domain) => domain === '*' || /^\*\.[a-z]{2,}$/.test(domain) || /^\*\.(?:co|com|org|net)\.[a-z]{2}$/.test(domain))) {
    add('danger', 'wildcard_domain', 'Разрешает запросы почти к любому сайту (' + info.domains.join(', ') + ')', null);
  } else if (info.domains.length > 8) {
    add('warn', 'many_domains', 'Слишком много доменов в @domains: ' + info.domains.length, null);
  }
  for (const permission of used) {
    if (!permissions.has(permission)) {
      add('info', 'undeclared_permission', 'Использует ' + permission + ', но не просит это разрешение (вызов упадёт)', null);
    }
  }
  for (const permission of permissions) {
    if (!used.has(permission)) {
      add('info', 'unused_permission', 'Просит ' + permission + ', но не использует', null);
    }
  }
  if (unpacked.extras && unpacked.extras.length) {
    add('info', 'binary_files', 'В пакете есть не-текстовые файлы: ' + unpacked.extras.map((item) => item.name).slice(0, 5).join(', '), null);
  }
  findings.sort((a, b) => LEVELS[b.level] - LEVELS[a.level]);
  const danger = findings.filter((item) => item.level === 'danger').length;
  const warn = findings.filter((item) => item.level === 'warn').length;
  return { verdict: danger ? 'danger' : warn ? 'warn' : 'clean', danger, warn, findings: findings.slice(0, 40), permissions: [...permissions], used: [...used] };
}

export function scanSummary(scan) {
  const icon = { clean: '🟢', warn: '🟡', danger: '🔴' }[scan.verdict] || '⚪️';
  const title = { clean: 'чисто', warn: 'есть что проверить', danger: 'опасно' }[scan.verdict] || '?';
  const lines = [icon + ' Автопроверка: ' + title];
  for (const item of scan.findings.filter((entry) => entry.level !== 'info').slice(0, 12)) {
    lines.push((item.level === 'danger' ? '⛔ ' : '⚠️ ') + item.text + (item.file ? ' — ' + item.file + (item.line ? ':' + item.line : '') : ''));
  }
  const infos = scan.findings.filter((entry) => entry.level === 'info').length;
  if (infos) {
    lines.push('ℹ️ Заметок: ' + infos);
  }
  if (scan.ai) {
    lines.push('🤖 ИИ: ' + ({ safe: 'безопасно', suspicious: 'подозрительно', malicious: 'вредонос' }[scan.ai.verdict] || scan.ai.verdict) + ' (' + Math.round((scan.ai.confidence || 0) * 100) + '%) — ' + scan.ai.summary);
  }
  return lines.join('\n');
}

export async function aiReview(env, unpacked) {
  const key = env && env.GEMINI_API_KEY;
  if (!key) {
    return null;
  }
  let budget = 60000;
  const parts = [];
  for (const file of unpacked.files) {
    if (budget <= 0) {
      break;
    }
    const text = file.text.slice(0, budget);
    budget -= text.length;
    parts.push('=== ' + file.name + ' ===\n' + text);
  }
  const system = 'You are a security reviewer for plugins of a Telegram client. Plugins run in a JavaScript sandbox and use the wg API: wg.messages.send/getList, wg.events.on("message.*"), wg.intercept, wg.net.fetch (only to declared domains), wg.ui.prompt, wg.system.clipboardGet/Set, wg.system.openURL, wg.kv storage. Decide whether the plugin is malicious: stealing login codes, passwords, sessions or messages, sending data to third parties without clear purpose, phishing prompts, spam or mass messaging, wallet address swapping, hidden or obfuscated payloads, joining channels or starting bots without consent. Benign plugins that clearly do what their name says are safe. Answer only JSON: {"verdict":"safe"|"suspicious"|"malicious","confidence":0..1,"summary":"one short sentence in Russian"}.';
  const prompt = 'Plugin name: ' + unpacked.info.name + '\nDeclared permissions: ' + unpacked.info.permissions.join(', ') + '\nDeclared domains: ' + unpacked.info.domains.join(', ') + '\n\n' + parts.join('\n\n');
  const model = env.GEMINI_MODEL || 'gemini-flash-latest';
  try {
    const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/' + encodeURIComponent(model) + ':generateContent', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({ systemInstruction: { parts: [{ text: system }] }, contents: [{ role: 'user', parts: [{ text: prompt }] }], generationConfig: { responseMimeType: 'application/json', maxOutputTokens: 400, temperature: 0 } }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      return null;
    }
    const data = await response.json();
    const text = (((data.candidates || [])[0] || {}).content || { parts: [] }).parts.map((part) => part.text || '').join('');
    const parsed = JSON.parse(text.replace(/^```(?:json)?|```$/g, '').trim());
    const verdict = ['safe', 'suspicious', 'malicious'].includes(parsed.verdict) ? parsed.verdict : 'suspicious';
    const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0));
    return { verdict, confidence, summary: String(parsed.summary || '').slice(0, 300) };
  } catch {
    return null;
  }
}
