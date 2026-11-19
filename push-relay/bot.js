import { paymentHealth, paymentHealthText } from './badges.js';
import { profileAdmin, profileVerify } from './profile.js';
import { BAN_REASONS, COPY_REASONS, OFFICIAL_REPO, copyMenu, copyMessage, reasonLabel, reasonNote, reportMessage, statsStub } from './stats.js';

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
    lines.push('Статус: ⛔ забанен ' + when(target.ban.time) + ' · причина: ' + reasonLabel(target.ban.reason, target.ban.note));
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

function profileLines(profile) {
  if (!profile) {
    return [];
  }
  const lines = ['Метка: #' + profile.tag + ' · жалоб с этой установки: ' + profile.reports + ' · аккаунтов: ' + profile.accounts];
  if (profile.banned) {
    lines.push('⛔ Сам жалобщик в бане');
  }
  if (profile.self) {
    lines.push('⚠️ Жалоба на собственный аккаунт');
  }
  profile.others.forEach((item) => lines.push('  ранее: ' + when(item.time) + ' → ' + (item.targetName || (item.target ? 'ID ' + item.target : 'без цели'))));
  return lines;
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
    lines.push('Бан: ' + (target.ban ? 'да, ' + when(target.ban.time) + ', причина: ' + reasonLabel(target.ban.reason, target.ban.note) : 'нет'));
    lines.push('Предупреждение: ' + (target.warning ? 'да, ' + when(target.warning.time) : 'нет'));
    target.installs.forEach((install, index) => lines.push((index + 1) + '. ' + installLine(install)));
  } else {
    lines.push('не определён: ' + (report.targetName || 'в жалобе нет @юзернейма'));
  }
  lines.push('');
  lines.push('📨 Кто пожаловался');
  for (const line of profileLines(review.profile)) {
    lines.push(line);
  }
  if (review.reporter) {
    lines.push('Установка: ✅ найдена');
    lines.push('1. ' + installLine(review.reporter));
  } else {
    lines.push('Установка: ❌ не найдена (жалоба не с реальной установки или выключена статистика)');
    lines.push('сборка ' + (report.build || '?') + ' · ' + report.source + ' · ' + report.status + ' · ' + report.country);
  }
  return lines.join('\n').slice(0, 4000);
}

async function stats(env, path, method, body) {
  const stub = statsStub(env);
  if (!stub) {
    return null;
  }
  const response = await stub.fetch('https://stats.ayugram.invalid' + path, { method: method || 'GET', body: body ? JSON.stringify(body) : undefined });
  return response;
}

function reasonQuery(reason, note) {
  return note ? '?note=' + encodeURIComponent(note) : '?reason=' + encodeURIComponent(reason || 'other');
}

function reasonMenu(reasons, prefix, cancel) {
  return { inline_keyboard: [...reasons.map(([code, label]) => [{ text: '⛔ ' + label, callback_data: prefix + ':' + code }]), [{ text: '✏️ Своя причина', callback_data: prefix + ':custom' }], [{ text: 'Отмена', callback_data: cancel }]] };
}

async function handleCopyCallback(env, query, action, cid, answer, reason, note) {
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
  const moderated = await stats(env, '/copy-moderate/' + (action === 'K' ? 'block/' + cid + reasonQuery(reason, note) : 'unblock/' + cid), 'POST');
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
    data.accounts.forEach((ban) => lines.push('• ' + (ban.name || 'без имени') + ' · ' + when(ban.time) + ' · ' + reasonLabel(ban.reason, ban.note)));
  } else {
    lines.push('нет');
  }
  lines.push('');
  lines.push('Заблокированные копии (' + data.copies.length + '):');
  if (data.copies.length) {
    data.copies.forEach((copy) => lines.push('• ' + copyLabel(copy) + ' · ' + when(copy.time) + ' · ' + reasonLabel(copy.reason, copy.note)));
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

async function banByIdWithReason(env, query, id, reason, answer, note) {
  const message = query.message;
  if (!/^[1-9][0-9]{0,19}$/.test(id || '')) {
    await answer('Неверный ID', true);
    return;
  }
  const response = await stats(env, '/ban-id/ban/' + id + reasonQuery(reason, note), 'POST');
  if (!response || !response.ok) {
    await answer('Не получилось, попробуй ещё раз', true);
    return;
  }
  const result = await response.json();
  const installed = result.installs ? 'AyuGram у него: ✅ найден (' + result.installs + ' устр.)' : 'AyuGram у него: ❌ не найден или выключена статистика';
  const text = '⛔ Забанен ID ' + id + '. Причина: ' + reasonLabel(reason, note) + '. Сработает при следующем запуске AyuGram.\n' + installed;
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

async function handleCallback(env, query, note) {
  const message = query.message;
  const [action, rid, reason] = String(query.data || '').split(':');
  const answer = (text, alert) => (query.id ? telegram(env, 'answerCallbackQuery', { callback_query_id: query.id, text: text || undefined, show_alert: Boolean(alert) }) : null);
  if (reason === 'custom' && !note && ['Z', 'K', 'B'].includes(action)) {
    if (!message) {
      await answer('Не получилось', true);
      return;
    }
    await stats(env, '/pending', 'POST', { data: action + ':' + rid + ':custom', chat: message.chat.id, message: message.message_id });
    await telegram(env, 'sendMessage', { chat_id: message.chat.id, text: 'Напиши причину одним сообщением, до 200 символов. Её увидит пользователь в окне блокировки. /cancel — отмена.', reply_parameters: { message_id: message.message_id } });
    await answer();
    return;
  }
  if (action === 'G' || action === 'D') {
    const done = await stats(env, '/badge-' + (action === 'G' ? 'grant' : 'deny') + '/' + rid, 'POST');
    if (!done || !done.ok) {
      await answer('Запрос не найден или уже обработан', true);
      return;
    }
    const result = await done.json();
    if (message) {
      await telegram(env, 'editMessageText', { chat_id: message.chat.id, message_id: message.message_id, text: (action === 'G' ? '✅ Бейдж выдан: ID ' : '❌ Отклонено: ID ') + result.id + (result.name ? ' · ' + result.name : ''), reply_markup: action === 'G' ? { inline_keyboard: [[{ text: 'Забрать бейдж', callback_data: 'R:' + result.id }]] } : undefined });
    }
    await answer(action === 'G' ? 'Выдан' : 'Отклонён');
    return;
  }
  if (action === 'R') {
    const done = await stats(env, '/badge-revoke/' + rid, 'POST');
    if (message && done && done.ok) {
      await telegram(env, 'editMessageText', { chat_id: message.chat.id, message_id: message.message_id, text: '🚫 Бейдж забран: ID ' + rid });
    }
    await answer(done && done.ok ? 'Забран' : 'Не получилось', !(done && done.ok));
    return;
  }
  if (['P', 'J', 'O'].includes(action)) {
    const done = await profileAdmin(env, rid, { P: 'background', J: 'block', O: 'unblock' }[action]);
    if (message && done) {
      const next = action === 'J' ? [[{ text: '✅ Снять запрет', callback_data: 'O:' + rid }]] : [[{ text: '⛔ Стереть всё и запретить', callback_data: 'J:' + rid }]];
      await telegram(env, 'editMessageReplyMarkup', { chat_id: message.chat.id, message_id: message.message_id, reply_markup: { inline_keyboard: next } });
    }
    const texts = { P: '🗑 Фон удалён', J: '⛔ Профиль стёрт, менять его больше нельзя', O: '✅ Запрет снят' };
    await answer(done ? texts[action] : 'Не получилось', true);
    return;
  }
  if (['U', 'V', 'X', 'L'].includes(action)) {
    await handleBansCallback(env, query, action, rid, answer);
    return;
  }
  if (action === 'Z') {
    await banByIdWithReason(env, query, rid, reason, answer, note);
    return;
  }
  if (['k', 'K', 'x', 'y'].includes(action)) {
    await handleCopyCallback(env, query, action, rid, answer, reason, note);
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
  const moderated = await stats(env, '/moderate/' + actions[action] + '/' + rid + (action === 'B' ? reasonQuery(reason, note) : ''), 'POST');
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

const VERIFY_TEXTS = {
  ready: (code) => '🔐 AyuGram: confirm Profile extras\n\nTap the button to link Profile extras in AyuGram to this Telegram account. Check that AyuGram shows the same code: ' + code + '.\nConfirm only if you started this yourself in your own AyuGram. Never confirm a link someone sent you.\n\n🔐 AyuGram: подтверждение украшений профиля\n\nНажмите кнопку, чтобы привязать украшения профиля в AyuGram к этому аккаунту Telegram. Проверьте, что AyuGram показывает тот же код: ' + code + '.\nПодтверждайте, только если сами начали проверку в своём AyuGram. Никогда не подтверждайте ссылку, которую вам прислали.',
  verified: '✅ Done. Go back to AyuGram: Profile extras can be edited now.\n\n✅ Готово. Вернитесь в AyuGram: теперь украшения профиля можно менять.',
  wrong: '❌ This link was created for another Telegram account. Open it from the account you use in AyuGram.\n\n❌ Эта ссылка создана для другого аккаунта Telegram. Откройте её с того аккаунта, который используете в AyuGram.',
  invalid: '⌛ This link has expired or was already used. Create a new one in AyuGram > Profile extras.\n\n⌛ Ссылка истекла или уже использована. Создайте новую в AyuGram > Украшения профиля.',
  error: '⚠️ Something went wrong. Try again in a minute.\n\n⚠️ Что-то пошло не так. Попробуйте через минуту.',
  limited: '⏳ Too many attempts today. Try again tomorrow.\n\n⏳ Слишком много попыток за сегодня. Попробуйте завтра.',
};

function forwarded(message) {
  return Boolean(message.forward_origin || message.forward_from || message.forward_from_chat || message.forward_sender_name || message.forward_date || message.is_automatic_forward || message.via_bot || message.sender_chat);
}
const VERIFY_BUTTON = '✅ Confirm · Подтвердить';

function verifyRequest(update) {
  const message = update && update.message;
  if (message && message.chat && message.chat.type === 'private' && message.from && String(message.chat.id) === String(message.from.id) && !forwarded(message) && typeof message.text === 'string') {
    const match = /^\/start(?:@[A-Za-z0-9_]+)?\s+pv_(\S*)\s*$/.exec(message.text.trim());
    if (match) {
      return { nonce: match[1], from: message.from, chat: message.chat.id, commit: false };
    }
  }
  const query = update && update.callback_query;
  const data = query ? String(query.data || '') : '';
  if (query && query.from && data.startsWith('pv:')) {
    const chat = query.message && query.message.chat;
    const own = chat && chat.type === 'private' && String(chat.id) === String(query.from.id) && !query.inline_message_id;
    return { nonce: data.slice(3), from: query.from, chat: own ? chat.id : null, message: query.message, query, commit: true };
  }
  return null;
}

async function handleVerify(env, request) {
  if (request.commit && !request.chat) {
    await telegram(env, 'answerCallbackQuery', { callback_query_id: request.query.id, text: VERIFY_TEXTS.invalid.split('\n')[0], show_alert: true });
    return;
  }
  const result = await profileVerify(env, request.nonce, request.from, request.commit);
  if (result.status === 'limited') {
    if (request.commit) {
      await telegram(env, 'answerCallbackQuery', { callback_query_id: request.query.id, text: VERIFY_TEXTS.limited.split('\n')[0], show_alert: true });
    }
    return;
  }
  const text = result.status === 'ready' ? VERIFY_TEXTS.ready(result.code) : VERIFY_TEXTS[result.status] || VERIFY_TEXTS.error;
  if (!request.commit) {
    const markup = result.status === 'ready' ? { inline_keyboard: [[{ text: VERIFY_BUTTON, callback_data: 'pv:' + request.nonce }]] } : undefined;
    await telegram(env, 'sendMessage', { chat_id: request.chat, text, reply_markup: markup });
    return;
  }
  if (request.message && request.message.message_id) {
    await telegram(env, 'editMessageText', { chat_id: request.chat, message_id: request.message.message_id, text });
  } else {
    await telegram(env, 'sendMessage', { chat_id: request.chat, text });
  }
  await telegram(env, 'answerCallbackQuery', { callback_query_id: request.query.id, text: text.split('\n')[0], show_alert: result.status !== 'verified' });
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
  const verify = verifyRequest(update);
  if (verify) {
    const task = handleVerify(env, verify).catch((error) => console.log('bot verify failed: ' + error));
    if (ctx && typeof ctx.waitUntil === 'function') {
      ctx.waitUntil(task);
    } else {
      await task;
    }
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
      } else if (/^\/pay(\s|$|@)/.test(message.text)) {
        await telegram(env, 'sendMessage', { chat_id: owner, text: paymentHealthText(await paymentHealth(env)) });
      } else if (/^\/(un)?badge(\s|$)/.test(message.text)) {
        const [command, raw] = message.text.trim().split(/\s+/);
        const id = String(raw || '').replace(/^ID/i, '');
        if (!/^[1-9][0-9]{0,15}$/.test(id)) {
          await telegram(env, 'sendMessage', { chat_id: owner, text: 'Напиши числовой ID: ' + command + ' 123456789' });
        } else {
          const revoke = command.startsWith('/unbadge');
          const done = await stats(env, (revoke ? '/badge-revoke/' : '/badge-grant-id/') + id, 'POST');
          await telegram(env, 'sendMessage', { chat_id: owner, text: done && done.ok ? (revoke ? '🚫 Бейдж забран: ID ' : '✅ Бейдж выдан: ID ') + id : 'Не получилось, попробуй ещё раз' });
        }
      } else if (/^\/(unprofile|reprofile|unbg)(\s|$|@)/.test(message.text)) {
        const [command, raw] = message.text.trim().split(/\s+/);
        const id = String(raw || '').replace(/^ID/i, '');
        const name = command.replace(/@.*$/, '');
        if (!/^[1-9][0-9]{0,15}$/.test(id)) {
          await telegram(env, 'sendMessage', { chat_id: owner, text: 'Напиши числовой ID: ' + name + ' 123456789' });
        } else {
          const action = { '/unprofile': 'block', '/reprofile': 'unblock', '/unbg': 'background' }[name];
          const done = await profileAdmin(env, id, action);
          const texts = { block: '⛔ Профиль стёрт (фейк-NFT, юзернеймы, фон), менять его больше нельзя: ID ', unblock: '✅ Запрет на профиль снят: ID ', background: '🗑 Фон профиля удалён: ID ' };
          await telegram(env, 'sendMessage', { chat_id: owner, text: done ? texts[action] + id : 'Не получилось, попробуй ещё раз' });
        }
      } else if (/^\/(un)?ban(\s|$)/.test(message.text)) {
        await banById(env, owner, message.text);
      } else if (message.text.startsWith('/cancel')) {
        const taken = await stats(env, '/pending/take', 'POST');
        const pending = taken && taken.ok ? await taken.json() : null;
        await telegram(env, 'sendMessage', { chat_id: owner, text: pending ? 'Отменено.' : 'Отменять нечего.' });
      } else if (!message.text.startsWith('/')) {
        const taken = await stats(env, '/pending/take', 'POST');
        const pending = taken && taken.ok ? await taken.json() : null;
        const note = reasonNote(message.text);
        if (pending && note) {
          await handleCallback(env, { data: pending.data, message: { chat: { id: pending.chat }, message_id: pending.message } }, note);
          await telegram(env, 'sendMessage', { chat_id: owner, text: '⛔ Готово. Причина: ' + note });
        }
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
