import React, { useState } from "react";
import { base44 } from "@/api/base44Client";
import { Sparkles, Check, Loader2 } from "lucide-react";
import { motion } from "framer-motion";
import { getLevelInfo } from "./LevelBadge";
const COIN_PACKS=[{id:"starter",label:"Starter Pack",coins:100,price:"Free",free:true,icon:"🪙"},{id:"small",label:"Small Pack",coins:500,price:"$0.99",icon:"💰"},{id:"medium",label:"Medium Pack",coins:1500,price:"$2.49",icon:"💎"},{id:"big",label:"Big Pack",coins:5000,price:"$6.99",icon:"🏆"}];
const NITRO_COST=800;
export default function NitroShop({user,onUpdate}){
  const[loading,setLoading]=useState(null);const[claimedFree,setClaimedFree]=useState(false);
  const coins=user?.coins||0;const isNitro=user?.nitro_active;const{current}=getLevelInfo(user?.xp||0);
  const claimFreeCoins=async()=>{setLoading("starter");const newCoins=coins+100;await base44.auth.updateMe({coins:newCoins});onUpdate({coins:newCoins});setClaimedFree(true);setLoading(null);};
  const buyNitro=async()=>{if(coins<NITRO_COST)return;setLoading("nitro");const until=new Date(Date.now()+30*24*60*60*1000).toISOString();await base44.auth.updateMe({nitro_active:true,nitro_until:until,coins:coins-NITRO_COST});onUpdate({nitro_active:true,nitro_until:until,coins:coins-NITRO_COST});setLoading(null);};
  return(
    <div className="space-y-5">
      <div className="rounded-2xl p-4 flex items-center gap-4" style={{background:"linear-gradient(135deg,#c084fc22,#818cf822)",border:"1px solid #c084fc44"}}>
        <div className="w-12 h-12 rounded-full flex items-center justify-center flex-shrink-0" style={{background:"linear-gradient(135deg,#c084fc,#818cf8)"}}><Sparkles className="w-6 h-6 text-white"/></div>
        <div><p className="font-bold text-sm" style={{color:"var(--text-primary)"}}>{isNitro?"✨ MimiNitro Active!":"Get MimiNitro"}</p><p className="text-xs" style={{color:"var(--text-muted)"}}>{isNitro?`Expires ${new Date(user.nitro_until).toLocaleDateString()}`:"Unlock animated banners, exclusive badges & more!"}</p></div>
        {!isNitro&&<button onClick={buyNitro} disabled={coins<NITRO_COST||loading==="nitro"} className="ml-auto text-xs font-bold px-4 py-2 rounded-full text-white disabled:opacity-50" style={{background:"linear-gradient(135deg,#c084fc,#818cf8)"}}>{loading==="nitro"?<Loader2 className="w-4 h-4 animate-spin"/>:`🪙 ${NITRO_COST} Coins`}</button>}
      </div>
      <div className="rounded-2xl p-4 flex items-center gap-4" style={{background:"linear-gradient(135deg,#f59e0b22,#fbbf2422)",border:"1px solid #f59e0b44"}}><span className="text-3xl">🪙</span><div><p className="font-bold text-lg" style={{color:"var(--text-primary)"}}>{coins.toLocaleString()} MimiCoins</p><p className="text-xs" style={{color:"var(--text-muted)"}}>Your current balance</p></div></div>
      <div className="grid grid-cols-2 gap-3">{COIN_PACKS.map(pack=>(<motion.div key={pack.id} whileHover={{scale:1.02}} className="rounded-xl p-3 text-center border" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><div className="text-2xl mb-1">{pack.icon}</div><p className="text-xs font-bold" style={{color:"var(--text-primary)"}}>{pack.label}</p><p className="text-sm font-bold" style={{color:"#f59e0b"}}>{pack.coins} coins</p>{pack.free?<button onClick={claimFreeCoins} disabled={claimedFree||loading===pack.id} className="mt-2 w-full text-[10px] font-bold py-1.5 rounded-full text-white disabled:opacity-50" style={{background:claimedFree?"#34d399":"linear-gradient(135deg,#f59e0b,#fbbf24)"}}>{claimedFree?<><Check className="w-3 h-3 inline"/>Claimed!</>:"Claim Free"}</button>:<button className="mt-2 w-full text-[10px] font-bold py-1.5 rounded-full text-white opacity-50 cursor-not-allowed" style={{background:"linear-gradient(135deg,#f59e0b,#fbbf24)"}}>{pack.price} (Soon)</button>}</motion.div>))}</div>
    </div>
  );
}