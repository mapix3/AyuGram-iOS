import { copyMenu, copyMessage, reportMessage, statsStub } from './stats.js';

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
    lines.push('Статус: ⛔ забанен ' + when(target.ban.time));
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
    lines.push('Бан: ' + (target.ban ? 'да, ' + when(target.ban.time) : 'нет'));
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

async function handleCopyCallback(env, query, action, cid, answer) {
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
    await edit({ inline_keyboard: [[{ text: '⛔ Да, заблокировать', callback_data: 'K:' + cid }], [{ text: 'Отмена', callback_data: 'y:' + cid }]] });
    await answer('Блок по ' + copy.blockable.join(', ') + '. Подтверди', true);
    return;
  }
  const moderated = await stats(env, '/copy-moderate/' + (action === 'K' ? 'block' : 'unblock') + '/' + cid, 'POST');
  if (!moderated || !moderated.ok) {
    await answer('Не получилось, попробуй ещё раз', true);
    return;
  }
  copy = await moderated.json();
  await edit();
  await answer(action === 'K' ? '⛔ Заблокирована, AyuGram в ней закроется при следующем запуске' : '✅ Разблокирована', true);
}

async function handleCallback(env, query) {
  const message = query.message;
  const [action, rid] = String(query.data || '').split(':');
  const answer = (text, alert) => telegram(env, 'answerCallbackQuery', { callback_query_id: query.id, text: text || undefined, show_alert: Boolean(alert) });
  if (['k', 'K', 'x', 'y'].includes(action)) {
    await handleCopyCallback(env, query, action, rid, answer);
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
    await edit({ inline_keyboard: [[{ text: '⛔ Да, забанить', callback_data: 'B:' + rid }], [{ text: 'Отмена', callback_data: 'v:' + rid }]] });
    await answer(review.target.installs.length ? 'Подтверди бан' : 'AyuGram у него не найден. Бан сработает, если он его установит', !review.target.installs.length);
    return;
  }
  const actions = { w: 'warn', B: 'ban', u: 'unban' };
  if (!actions[action]) {
    await answer();
    return;
  }
  const moderated = await stats(env, '/moderate/' + actions[action] + '/' + rid, 'POST');
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
    } else if (message && message.chat && String(message.chat.id) === owner && typeof message.text === 'string' && message.text.startsWith('/start')) {
      await telegram(env, 'sendMessage', { chat_id: owner, text: 'Готов. Жалобы на скам будут приходить сюда, кнопка «Рассмотреть жалобу» под каждой.' });
    }
  })().catch((error) => console.log('bot update failed: ' + error));
  if (ctx && typeof ctx.waitUntil === 'function') {
    ctx.waitUntil(work);
  } else {
    await work;
  }
  return new Response('ok\n');
}
