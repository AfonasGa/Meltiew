// Email: sign-up codes. A tiny SMTP client. Two setups, from the service's env:
//   our own Postfix on this machine (it signs with DKIM for narez.xyz):
//     MELTIEW_SMTP_HOST=127.0.0.1 MELTIEW_SMTP_PORT=25 MELTIEW_MAIL_FROM=noreply@narez.xyz
//   or a provider over implicit TLS with a login (port 465):
//     MELTIEW_SMTP_HOST, MELTIEW_SMTP_PORT, MELTIEW_SMTP_USER, MELTIEW_SMTP_PASS, MELTIEW_MAIL_FROM
import tls from 'node:tls';
import net from 'node:net';
import crypto from 'node:crypto';

export function mailConfigured(env = process.env) {
  return Boolean(env.MELTIEW_SMTP_HOST && (env.MELTIEW_SMTP_USER || env.MELTIEW_MAIL_FROM));
}

// Only big providers that verify their users: throwaway domains can't be used for bots.
export const EMAIL_DOMAINS = new Set([
  'gmail.com', 'googlemail.com',
  'outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'outlook.ru',
  'icloud.com', 'me.com', 'mac.com',
  'yahoo.com', 'ymail.com', 'aol.com',
  'yandex.ru', 'ya.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua',
  'mail.ru', 'bk.ru', 'inbox.ru', 'list.ru', 'internet.ru', 'rambler.ru',
  'proton.me', 'protonmail.com', 'pm.me',
  'gmx.com', 'gmx.de', 'gmx.net', 'web.de', 'zoho.com', 'ukr.net',
]);

/**
 * The address as the account keeps it, or null if it isn't one we accept. Gmail ignores
 * dots and every provider here ignores "+tag", so those don't make new addresses.
 */
export function normalizeEmail(raw) {
  const s = String(raw ?? '').trim().toLowerCase();
  const m = /^([a-z0-9._%+-]{1,64})@([a-z0-9.-]{3,80})$/.exec(s);
  if (!m) return null;
  let [, local, domain] = m;
  if (domain === 'googlemail.com') domain = 'gmail.com';
  if (!EMAIL_DOMAINS.has(domain)) return null;
  local = local.split('+')[0];
  if (domain === 'gmail.com') local = local.replace(/\./g, '');
  if (!local) return null;
  return `${local}@${domain}`;
}

export function newCode() {
  return String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
}

export function hashCode(code) {
  return crypto.createHash('sha256').update('meltiew-code:' + code).digest('hex');
}

const TEXT = {
  en: (code) => [`Meltiew code: ${code}`, `Your Meltiew code is ${code}\n\nIt works for 15 minutes. If you didn't ask for it, ignore this email.`],
  ru: (code) => [`Код Meltiew: ${code}`, `Твой код для Meltiew: ${code}\n\nОн действует 15 минут. Если ты его не запрашивал(а), просто не обращай внимания на письмо.`],
};

export function sendCode(to, code, lang = 'en', env = process.env) {
  const [subject, body] = (TEXT[lang] || TEXT.en)(code);
  return sendMail({ to, subject, text: body }, env);
}

function b64(s) {
  return Buffer.from(s, 'utf8').toString('base64');
}

/** One email over SMTP; resolves when the server accepted it. */
export function sendMail({ to, subject, text }, env = process.env) {
  const host = env.MELTIEW_SMTP_HOST;
  const port = Number(env.MELTIEW_SMTP_PORT) || 465;
  const user = env.MELTIEW_SMTP_USER;
  const from = env.MELTIEW_MAIL_FROM || user;
  const message = [
    `From: Meltiew <${from}>`,
    `To: <${to}>`,
    `Subject: =?UTF-8?B?${b64(subject)}?=`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${crypto.randomUUID()}@${from.split('@')[1] || 'meltiew'}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    b64(text).replace(/.{76}/g, '$&\r\n'),
  ].join('\r\n');
  const steps = [
    [null, 220],
    ['EHLO meltiew', 250],
    // A login only for a provider; our own local Postfix takes mail from this machine.
    ...(user ? [['AUTH PLAIN ' + b64(`\0${user}\0${env.MELTIEW_SMTP_PASS}`), 235]] : []),
    [`MAIL FROM:<${from}>`, 250],
    [`RCPT TO:<${to}>`, 250],
    ['DATA', 354],
    [message + '\r\n.', 250],
    ['QUIT', 221],
  ];
  return new Promise((resolve, reject) => {
    const sock = port === 465 ? tls.connect({ host, port, servername: host }) : net.connect({ host, port });
    let buf = '';
    let i = 0;
    const fail = (err) => {
      sock.destroy();
      reject(err instanceof Error ? err : new Error(String(err)));
    };
    sock.setTimeout(15000, () => fail('smtp timeout'));
    sock.on('error', fail);
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      // A reply is complete at a line "NNN text" (not "NNN-text").
      const lines = buf.split('\r\n');
      const last = lines.findLast((l) => /^\d{3} /.test(l));
      if (!last) return;
      buf = '';
      const code = Number(last.slice(0, 3));
      if (code !== steps[i][1]) return fail(`smtp ${steps[i][0]?.split(' ')[0] || 'greeting'}: ${last}`);
      i += 1;
      if (i >= steps.length) {
        sock.end();
        return resolve();
      }
      sock.write(steps[i][0] + '\r\n');
    });
  });
}
