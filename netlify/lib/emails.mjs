// Sugerly's emails: soft pink, rounded, one big code in the middle. Plain
// tables and inline styles, so they look the same in Gmail, Outlook and the
// iPhone's Mail app (which also offers to fill the code in for you).
import { SITE } from "./sugerly.mjs";

const PINK = "#E8457C";
const INK = "#3A2230";
const MUTED = "#8C7280";

function page({ title, lead, code, note, preheader }) {
  const digits = String(code).split("").map((d) => `<td style="padding:0 3px"><div style="width:42px;height:54px;line-height:54px;border-radius:14px;background:#FFF0F5;border:2px solid #F9C9DA;font-size:28px;font-weight:800;color:${PINK};text-align:center;font-family:'Trebuchet MS',Verdana,Arial,sans-serif">${d}</div></td>`).join("");
  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><title>${title}</title></head>
<body style="margin:0;padding:0;background:#FFE4EE">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#FFE4EE;padding:28px 12px">
<tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#FFFFFF;border-radius:28px;box-shadow:0 10px 30px rgba(232,69,124,0.15);overflow:hidden">
    <tr><td style="background:linear-gradient(135deg,#FFB3CB,#E8457C);background-color:#F27BA3;padding:26px 24px;text-align:center">
      <img src="${SITE}/icons/icon-192.png" width="64" height="64" alt="" style="display:block;margin:0 auto 10px;border-radius:18px;border:3px solid #FFFFFF">
      <div style="font-family:'Trebuchet MS',Verdana,Arial,sans-serif;font-size:26px;font-weight:800;color:#FFFFFF;letter-spacing:0.5px">Sugerly</div>
    </td></tr>
    <tr><td style="padding:28px 26px 8px;text-align:center;font-family:'Trebuchet MS',Verdana,Arial,sans-serif">
      <div style="font-size:22px;font-weight:800;color:${INK};margin-bottom:8px">${title}</div>
      <div style="font-size:15px;line-height:22px;color:${MUTED}">${lead}</div>
    </td></tr>
    <tr><td align="center" style="padding:18px 16px 6px">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>${digits}</tr></table>
    </td></tr>
    <tr><td style="padding:14px 26px 26px;text-align:center;font-family:'Trebuchet MS',Verdana,Arial,sans-serif;font-size:13px;line-height:20px;color:${MUTED}">
      ${note}
    </td></tr>
    <tr><td style="background:#FFF6F9;padding:16px 24px;text-align:center;font-family:'Trebuchet MS',Verdana,Arial,sans-serif;font-size:12px;line-height:18px;color:#B497A6">
      Made with love for artists &#9825; Sugerly<br>Never share this code. Sugerly will never ask you for it.
    </td></tr>
  </table>
</td></tr>
</table>
</body></html>`;
}

export function loginCodeEmail(code) {
  const lead = "Here's your little key to log in. Type it in the app and you're back with your art and friends.";
  const note = "It works for 10 minutes and only once.<br>Didn't ask for it? You can ignore this email, your account is safe.";
  return {
    subject: `${code} is your Sugerly login code`,
    html: page({ title: "Your login code", lead, code, note, preheader: `Your Sugerly code is ${code}` }),
    text: `Your Sugerly login code is ${code}\n\nIt works for 10 minutes and only once. Didn't ask for it? You can ignore this email, your account is safe.\n\nNever share this code. Sugerly will never ask you for it.`,
  };
}

export function resetCodeEmail(code) {
  const lead = "Forgot your password? It happens to everyone! Type this code in the app, then pick a new password.";
  const note = "It works for 10 minutes and only once.<br>Didn't ask for it? You can ignore this email, your password stays the same.";
  return {
    subject: `${code} is your Sugerly password code`,
    html: page({ title: "Let's get you back in", lead, code, note, preheader: `Your Sugerly password code is ${code}` }),
    text: `Your Sugerly password code is ${code}\n\nType it in the app, then pick a new password. It works for 10 minutes and only once. Didn't ask for it? You can ignore this email.\n\nNever share this code. Sugerly will never ask you for it.`,
  };
}
