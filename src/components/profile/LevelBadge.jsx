import React from "react";
import { Zap } from "lucide-react";
export const LEVELS = [
  {level:1,xpRequired:0,title:"Newcomer",color:"#a0a0a0"},{level:2,xpRequired:100,title:"Sketcher",color:"#60a5fa"},
  {level:3,xpRequired:300,title:"Artisan",color:"#34d399"},{level:4,xpRequired:700,title:"Creator",color:"#a78bfa"},
  {level:5,xpRequired:1500,title:"Master",color:"#f59e0b"},{level:6,xpRequired:3000,title:"Luminary",color:"#fb923c"},
  {level:7,xpRequired:6000,title:"Legend",color:"#e8a0b4"},{level:8,xpRequired:10000,title:"Mimi Elite",color:"#ec4899"},
];
export function getLevelInfo(xp=0) {
  let current=LEVELS[0],next=LEVELS[1];
  for(let i=LEVELS.length-1;i>=0;i--){if(xp>=LEVELS[i].xpRequired){current=LEVELS[i];next=LEVELS[i+1]||null;break;}}
  const xpInLevel=xp-current.xpRequired,xpNeeded=next?next.xpRequired-current.xpRequired:0;
  return{current,next,xpInLevel,xpNeeded,progress:next?Math.min(100,(xpInLevel/xpNeeded)*100):100};
}
export default function LevelBadge({xp=0,showProgress=false,size="sm"}){
  const{current,next,xpInLevel,xpNeeded,progress}=getLevelInfo(xp);const isLg=size==="lg";
  return(<div className="flex flex-col gap-1"><div className="flex items-center gap-1.5"><div className={`flex items-center gap-1 rounded-full font-bold ${isLg?"px-3 py-1 text-xs":"px-2 py-0.5 text-[10px]"}`} style={{background:current.color+"22",color:current.color,border:`1px solid ${current.color}44`}}><Zap className={isLg?"w-3.5 h-3.5":"w-3 h-3"}/>Lv.{current.level}·{current.title}</div>{next&&<span className={isLg?"text-xs":"text-[9px]"} style={{color:"var(--text-muted)"}}>{xpInLevel}/{xpNeeded} XP</span>}</div>{showProgress&&next&&<div className="h-1.5 rounded-full overflow-hidden" style={{background:"var(--border-c)",width:isLg?180:120}}><div className="h-full rounded-full transition-all duration-700" style={{width:`${progress}%`,background:`linear-gradient(90deg,${current.color},${next?.color||current.color})`}}/></div>}</div>);
}