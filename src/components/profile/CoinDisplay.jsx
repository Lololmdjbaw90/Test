import React from "react";
import { motion } from "framer-motion";
export default function CoinDisplay({coins=0,size="sm"}){
  const isLg=size==="lg";
  return(<motion.div whileHover={{scale:1.05}} className={`flex items-center gap-1 rounded-full font-bold ${isLg?"px-3 py-1 text-xs":"px-2 py-0.5 text-[10px]"}`} style={{background:"linear-gradient(135deg,#f59e0b,#fbbf24)",color:"white"}}><span className={isLg?"text-sm":"text-xs"}>🪙</span>{coins.toLocaleString()} Coins</motion.div>);
}