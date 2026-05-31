import React from "react";
import { Sparkles } from "lucide-react";
import { motion } from "framer-motion";
export default function NitroBadge({active=false,size="sm"}){
  if(!active)return null;const isLg=size==="lg";
  return(<motion.div animate={{boxShadow:["0 0 8px #c084fc44","0 0 18px #c084fcaa","0 0 8px #c084fc44"]}} transition={{duration:2,repeat:Infinity}} className={`flex items-center gap-1 rounded-full font-bold ${isLg?"px-3 py-1 text-xs":"px-2 py-0.5 text-[10px]"}`} style={{background:"linear-gradient(135deg,#c084fc,#818cf8)",color:"white"}}><Sparkles className={isLg?"w-3.5 h-3.5":"w-3 h-3"}/>MimiNitro</motion.div>);
}