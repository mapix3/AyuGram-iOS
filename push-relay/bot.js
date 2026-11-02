import { BAN_REASONS, COPY_REASONS, OFFICIAL_REPO, copyMenu, copyMessage, reasonLabel, reportMessage, statsStub } from './stats.js';

const kyiv = new Intl.DateTimeFormat('ru-RU', { timeZone: 'Europe/Kyiv', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });

function when(time) {
  return time ? kyiv.format(new Date(time)) : '-';
}

function sameSecret(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !a || a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let index = 0; index < a.length; index += 1) {
    diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  }
  return diff === 0;
}

async function telegram(env, method, body) {
  const response = await fetch('https://api.telegram.org/bot' + env.REPORT_BOT_TOKEN + '/' + method, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    console.log('telegram ' + method + ' failed: ' + response.status);
  }
  return response;
}

function installLine(install) {
  const parts = ['сборка ' + (install.build || '?') + (install.variant ? ' ' + install.variant : ''), install.source, install.status, install.country];
  if (install.device || install.os) {
    parts.push([install.device, install.os ? 'iOS ' + install.os : ''].filter(Boolean).join(' '));
  }
  const lines = [parts.filter(Boolean).join(' · ')];
  lines.push('первый запуск ' + when(install.first) + ', последняя активность ' + when(install.seen));
  if (install.team || install.teamName || install.cert) {
    lines.push('сертификат: ' + [install.team, install.teamName, install.cert].filter(Boolean).join(' / '));
  }
  if (install.profile || install.bundle) {
    lines.push('профиль: ' + [install.profile, install.bundle].filter(Boolean).join(' / '));
  }
  if (install.devices) {
    lines.push('устройств в профиле: ' + install.devices);
  }
  return lines.join('\n   ');
}

function statusLines(review) {
  const target = review.target;
  if (!target) {
    return ['Скамер не определён: в жалобе нет @юзернейма, который удалось найти.'];
  }
  const lines = ['Скамер: ' + (target.name || '-') + ' (ID ' + target.id + ')'];
  if (target.installs.length) {
    lines.push('AyuGram: ✅ установлен (' + target.installs.length + ' устр.), активность ' + when(target.installs[0].seen));
  } else {
    lines.push('AyuGram: ❌ не установлен или выключена статистика');
  }
  if (target.ban) {
    lines.push('Статус: ⛔ забанен ' + when(target.ban.time) + ' · причина: ' + reasonLabel(target.ban.reason));
  } else if (target.warning) {
    lines.push('Статус: ⚠️ предупреждён ' + when(target.warning.time));
  } else {
    lines.push('Статус: без мер');
  }
  return lines;
}

function reviewText(review) {
  return reportMessage(review.report) + '\n\n' + statusLines(review).join('\n');
}

function menu(review) {
  const rid = review.report.rid;
  const banned = review.target && review.target.ban;
  return {
    inline_keyboard: [
      [{ text: '⚠️ Предупредить', callback_data: 'w:' + rid }, banned ? { text: '✅ Разбанить', callback_data: 'u:' + rid } : { text: '⛔ Забанить', callback_data: 'b:' + rid }],
      [{ text: '📋 Полные данные', callback_data: 'd:' + rid }],
      [{ text: '« Назад', callback_data: 'm:' + rid }],
    ],
  };
}

export function detailsText(review) {
  const report = review.report;
  const lines = ['📋 Жалоба ' + report.rid, 'Время: ' + when(report.time), 'Текст: ' + report.text, 'Вложений: ' + (report.received || 0) + ' из ' + (report.attachments || 0), ''];
  const target = review.target;
  lines.push('👤 Скамер');
  if (target) {
    lines.push('ID: ' + target.id);
    lines.push('Юзернейм и имя: ' + (target.name || '-'));
    lines.push('AyuGram: ' + (target.installs.length ? 'установлен на ' + target.installs.length + ' устр.' : 'не установлен или выключена статистика'));
    lines.push('Бан: ' + (target.ban ? 'да, ' + when(target.ban.time) + ', причина: ' + reasonLabel(target.ban.reason) : 'нет'));
    lines.push('Предупреждение: ' + (target.warning ? 'да, ' + when(target.warning.time) : 'нет'));
    target.installs.forEach((install, index) => lines.push((index + 1) + '. ' + installLine(install)));
  } else {
    lines.push('не определён: ' + (report.targetName || 'в жалобе нет @юзернейма'));
  }
  lines.push('');
  lines.push('📨 Кто пожаловался');
  if (review.reporter) {
    lines.push('Установка: ✅ найдена');
    lines.push('1. ' + installLine(review.reporter));
  } else {
    lines.push('Установка: ❌ не найдена (жалоба не с реальной установки или выключена статистика)');
    lines.push('сборка ' + (report.build || '?') + ' · ' + report.source + ' · ' + report.status + ' · ' + report.country);
  }
  return lines.join('\n').slice(0, 4000);
}

async function stats(env, path, method) {
  const stub = statsStub(env);
  if (!stub) {
    return null;
  }
  const response = await stub.fetch('https://stats.ayugram.invalid' + path, { method: method || 'GET' });
  return response;
}

function reasonMenu(reasons, prefix, cancel) {
  return { inline_keyboard: [...reasons.map(([code, label]) => [{ text: '⛔ ' + label, callback_data: prefix + ':' + code }]), [{ text: 'Отмена', callback_data: cancel }]] };
}

async function handleCopyCallback(env, query, action, cid, answer, reason) {
  const message = query.message;
  const response = await stats(env, '/copy/' + cid);
  if (!response || !response.ok || !message) {
    await answer('Копия не найдена', true);
    return;
  }
  let copy = await response.json();
  const edit = (markup) => telegram(env, 'editMessageText', {
    chat_id: message.chat.id,
    message_id: message.message_id,
    text: copyMessage(copy),
    link_preview_options: { is_disabled: true },
    reply_markup: markup || copyMenu(copy),
  });
  if (action === 'y') {
    await edit();
    await answer('Обновлено');
    return;
  }
  if (action === 'k') {
    if (!copy.blockable.length) {
      await answer('Заблокировать нечем', true);
      return;
    }
    await edit(reasonMenu(COPY_REASONS, 'K:' + cid, 'y:' + cid));
    await answer('Блок по ' + copy.blockable.join(', ') + '. Выбери причину', true);
    return;
  }
  const moderated = await stats(env, '/copy-moderate/' + (action === 'K' ? 'block/' + cid + '?reason=' + encodeURIComponent(reason || 'other') : 'unblock/' + cid), 'POST');
  if (!moderated || !moderated.ok) {
    await answer('Не получилось, попробуй ещё раз', true);
    return;
  }
  copy = await moderated.json();
  await edit();
  await answer(action === 'K' ? '⛔ Заблокирована, AyuGram в ней закроется при следующем запуске' : '✅ Разблокирована', true);
}

function copyLabel(copy) {
  return copy.repo && copy.repo !== OFFICIAL_REPO ? copy.repo : (copy.team || copy.kind || copy.cid);
}

function bansText(data) {
  const lines = ['🔐 Активные блокировки', ''];
  lines.push('Забаненные аккаунты (' + data.accounts.length + '):');
  if (data.accounts.length) {
    data.accounts.forEach((ban) => lines.push('• ' + (ban.name || 'без имени') + ' · ' + when(ban.time) + ' · ' + reasonLabel(ban.reason)));
  } else {
    lines.push('нет');
  }
  lines.push('');
  lines.push('Заблокированные копии (' + data.copies.length + '):');
  if (data.copies.length) {
    data.copies.forEach((copy) => lines.push('• ' + copyLabel(copy) + ' · ' + when(copy.time) + ' · ' + reasonLabel(copy.reason)));
  } else {
    lines.push('нет');
  }
  return lines.join('\n').slice(0, 4000);
}

function bansMenu(data) {
  const rows = [];
  for (const ban of data.accounts) {
    if (ban.id) {
      rows.push([{ text: '✅ Разбанить ' + (ban.name || ban.id), callback_data: 'V:' + ban.id }]);
    } else if (ban.rid) {
      rows.push([{ text: '✅ Разбанить ' + (ban.name || ban.rid), callback_data: 'U:' + ban.rid }]);
    }
  }
  for (const copy of data.copies) {
    rows.push([{ text: '✅ Разблокировать ' + copyLabel(copy), callback_data: 'X:' + copy.cid }]);
  }
  rows.push([{ text: '🔄 Обновить', callback_data: 'L:x' }]);
  return { inline_keyboard: rows.map((row) => row.map((button) => ({ ...button, text: button.text.slice(0, 60) }))) };
}

async function banById(env, chatId, text) {
  const [command, raw] = text.trim().split(/\s+/);
  const action = command.startsWith('/unban') ? 'unban' : 'ban';
  const id = String(raw || '').replace(/^ID/i, '');
  if (!/^[1-9][0-9]{0,19}$/.test(id)) {
    await telegram(env, 'sendMessage', { chat_id: chatId, text: 'Напиши числовой ID: /' + action + ' 123456789' });
    return;
  }
  if (action === 'ban') {
    await telegram(env, 'sendMessage', { chat_id: chatId, text: 'Бан ID ' + id + '. Выбери причину:', reply_markup: reasonMenu(BAN_REASONS, 'Z:' + id, 'L:x') });
    return;
  }
  const response = await stats(env, '/ban-id/unban/' + id, 'POST');
  if (!response || !response.ok) {
    await telegram(env, 'sendMessage', { chat_id: chatId, text: 'Не получилось, попробуй ещё раз' });
    return;
  }
  await telegram(env, 'sendMessage', { chat_id: chatId, text: '✅ Разбанен ID ' + id + '.' });
}

async function banByIdWithReason(env, query, id, reason, answer) {
  const message = query.message;
  if (!/^[1-9][0-9]{0,19}$/.test(id || '')) {
    await answer('Неверный ID', true);
    return;
  }
  const response = await stats(env, '/ban-id/ban/' + id + '?reason=' + encodeURIComponent(reason || 'other'), 'POST');
  if (!response || !response.ok) {
    await answer('Не получилось, попробуй ещё раз', true);
    return;
  }
  const result = await response.json();
  const installed = result.installs ? 'AyuGram у него: ✅ найден (' + result.installs + ' устр.)' : 'AyuGram у него: ❌ не найден или выключена статистика';
  const text = '⛔ Забанен ID ' + id + '. Причина: ' + reasonLabel(reason) + '. Сработает при следующем запуске AyuGram.\n' + installed;
  if (message) {
    await telegram(env, 'editMessageText', { chat_id: message.chat.id, message_id: message.message_id, text, reply_markup: { inline_keyboard: [[{ text: '✅ Разбанить', callback_data: 'V:' + id }]] } });
  }
  await answer('⛔ Забанен', false);
}

async function sendBans(env, chatId) {
  const response = await stats(env, '/bans');
  const data = response && response.ok ? await response.json() : { accounts: [], copies: [] };
  await telegram(env, 'sendMessage', { chat_id: chatId, text: bansText(data), link_preview_options: { is_disabled: true }, reply_markup: bansMenu(data) });
}

async function handleBansCallback(env, query, action, id, answer) {
  const message = query.message;
  if (action === 'U') {
    const review = await stats(env, '/review/' + id);
    if (!review || !review.ok) {
      await answer('Жалоба устарела, разбан отсюда недоступен', true);
      return;
    }
    const done = await stats(env, '/moderate/unban/' + id, 'POST');
    await answer(done && done.ok ? '✅ Разбанен' : 'Не получилось', true);
  } else if (action === 'V') {
    const done = await stats(env, '/ban-id/unban/' + id, 'POST');
    await answer(done && done.ok ? '✅ Разбанен' : 'Не получилось', true);
  } else if (action === 'X') {
    const done = await stats(env, '/copy-moderate/unblock/' + id, 'POST');
    await answer(done && done.ok ? '✅ Разблокирована' : 'Не получилось', true);
  }
  const response = await stats(env, '/bans');
  const data = response && response.ok ? await response.json() : { accounts: [], copies: [] };
  if (message) {
    await telegram(env, 'editMessageText', { chat_id: message.chat.id, message_id: message.message_id, text: bansText(data), link_preview_options: { is_disabled: true }, reply_markup: bansMenu(data) });
  }
}

async function handleCallback(env, query) {
  const message = query.message;
  const [action, rid, reason] = String(query.data || '').split(':');
  const answer = (text, alert) => telegram(env, 'answerCallbackQuery', { callback_query_id: query.id, text: text || undefined, show_alert: Boolean(alert) });
  if (['U', 'V', 'X', 'L'].includes(action)) {
    await handleBansCallback(env, query, action, rid, answer);
    return;
  }
  if (action === 'Z') {
    await banByIdWithReason(env, query, rid, reason, answer);
    return;
  }
  if (['k', 'K', 'x', 'y'].includes(action)) {
    await handleCopyCallback(env, query, action, rid, answer, reason);
    return;
  }
  const response = await stats(env, '/review/' + rid);
  if (!response || !response.ok || !message) {
    await answer('Жалоба не найдена', true);
    return;
  }
  let review = await response.json();
  const edit = (markup, text) => telegram(env, 'editMessageText', {
    chat_id: message.chat.id,
    message_id: message.message_id,
    text: text || reviewText(review),
    link_preview_options: { is_disabled: true },
    reply_markup: markup,
  });
  if (action === 'v') {
    await edit(menu(review));
    await answer();
    return;
  }
  if (action === 'm') {
    await edit({ inline_keyboard: [[{ text: '🔎 Рассмотреть жалобу', callback_data: 'v:' + rid }]] }, reportMessage(review.report));
    await answer();
    return;
  }
  if (action === 'd') {
    await telegram(env, 'sendMessage', {
      chat_id: message.chat.id,
      text: detailsText(review),
      reply_parameters: { message_id: message.message_id },
      link_preview_options: { is_disabled: true },
    });
    await answer();
    return;
  }
  if (['w', 'b', 'B', 'u'].includes(action) && !review.target) {
    await answer('Не на кого: в жалобе нет @юзернейма, который удалось найти', true);
    return;
  }
  if (action === 'b') {
    await edit(reasonMenu(BAN_REASONS, 'B:' + rid, 'v:' + rid));
    await answer(review.target.installs.length ? 'Выбери причину бана' : 'AyuGram у него не найден. Бан сработает, если он его установит. Выбери причину', !review.target.installs.length);
    return;
  }
  const actions = { w: 'warn', B: 'ban', u: 'unban' };
  if (!actions[action]) {
    await answer();
    return;
  }
  const moderated = await stats(env, '/moderate/' + actions[action] + '/' + rid + (action === 'B' ? '?reason=' + encodeURIComponent(reason || 'other') : ''), 'POST');
  if (!moderated || !moderated.ok) {
    await answer('Не получилось, попробуй ещё раз', true);
    return;
  }
  review = await moderated.json();
  await edit(menu(review));
  const installed = review.target.installs.length > 0;
  const texts = {
    w: installed ? '⚠️ Предупреждение покажется при следующем запуске AyuGram' : '⚠️ AyuGram у него не найден, предупреждение покажется, если он его установит',
    B: installed ? '⛔ Забанен, AyuGram заблокируется при следующем запуске' : '⛔ Забанен заранее: AyuGram заблокируется, если он его установит',
    u: '✅ Разбанен',
  };
  await answer(texts[action], true);
}

export async function handleBot(request, env, ctx) {
  if (request.method !== 'POST' || !env.REPORT_BOT_TOKEN || !env.REPORT_CHAT_ID) {
    return new Response('not found\n', { status: 404 });
  }
  if (!sameSecret(request.headers.get('x-telegram-bot-api-secret-token') || '', env.REPORT_WEBHOOK_SECRET || '')) {
    return new Response('forbidden\n', { status: 403 });
  }
  let update;
  try {
    update = await request.json();
  } catch {
    return new Response('ok\n');
  }
  const owner = String(env.REPORT_CHAT_ID);
  const query = update.callback_query;
  const message = update.message;
  const from = query ? query.from : message ? message.from : null;
  if (!from || String(from.id) !== owner) {
    return new Response('ok\n');
  }
  const work = (async () => {
    if (query) {
      await handleCallback(env, query);
    } else if (message && message.chat && String(message.chat.id) === owner && typeof message.text === 'string') {
      if (message.text.startsWith('/bans') || message.text.startsWith('/blocks')) {
        await sendBans(env, owner);
      } else if (/^\/(un)?ban(\s|$)/.test(message.text)) {
        await banById(env, owner, message.text);
      } else if (message.text.startsWith('/start')) {
        await telegram(env, 'sendMessage', { chat_id: owner, text: 'Готов. Жалобы на скам приходят сюда. /bans — список банов и блокировок с кнопками снятия.' });
      }
    }
  })().catch((error) => console.log('bot update failed: ' + error));
  if (ctx && typeof ctx.waitUntil === 'function') {
    ctx.waitUntil(work);
  } else {
    await work;
  }
  return new Response('ok\n');
}
