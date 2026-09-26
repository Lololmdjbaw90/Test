// Set VITE_DISCORD_WEBHOOK_URL in your .env for Discord moderation alerts
const WEBHOOK_URL = import.meta.env?.VITE_DISCORD_WEBHOOK_URL || "";
async function postEmbed(embed) { if (!WEBHOOK_URL) return; try { await fetch(WEBHOOK_URL, { method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({embeds:[embed]}) }); } catch(e){console.warn("Discord webhook failed:",e);} }
export async function sendBadMessage({ userEmail, displayName, communityName, channelName, reason, content }) {
  await postEmbed({ title:"💬 Bad Message Blocked", color:0xff6b35, fields:[{name:"User",value:`${displayName||"Unknown"} (${userEmail})`,inline:false},{name:"Server / Channel",value:`${communityName||"?"} → #${channelName||"?"}`,inline:false},{name:"Reason",value:reason||"Policy violation",inline:false},...(content?[{name:"Blocked Content",value:content.slice(0,500),inline:false}]:[])], timestamp:new Date().toISOString(), footer:{text:"Sugerly Chat Moderation"} });
}
export async function sendModerationStrike({ userEmail, displayName, reason, content }) {
  await postEmbed({ title:"🚫 Moderation Strike", color:0xff3da0, fields:[{name:"User",value:`${displayName||"Unknown"} (${userEmail})`,inline:false},{name:"Reason",value:reason||"Policy violation",inline:false},...(content?[{name:"Blocked Content",value:content.slice(0,500),inline:false}]:[])], timestamp:new Date().toISOString(), footer:{text:"Sugerly Moderation"} });
}