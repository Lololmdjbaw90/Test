import React, { useRef, useState, useCallback, useEffect } from "react";
import { motion } from "framer-motion";
import { Check, X, ZoomIn, ZoomOut } from "lucide-react";
const SIZE = 280;
export default function ImageCropper({ imageSrc, onCrop, onCancel }) {
  const canvasRef = useRef(null); const imgRef = useRef(null);
  const [scale, setScale] = useState(1); const [offset, setOffset] = useState({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false); const [dragStart, setDragStart] = useState({ x: 0, y: 0 });
  useEffect(() => { const img = new Image(); img.onload = () => { imgRef.current = img; setScale(Math.max(SIZE/img.naturalWidth, SIZE/img.naturalHeight)); setOffset({x:0,y:0}); }; img.src = imageSrc; }, [imageSrc]);
  const draw = useCallback(() => {
    const canvas = canvasRef.current; if (!canvas || !imgRef.current) return;
    const ctx = canvas.getContext("2d"); ctx.clearRect(0,0,SIZE,SIZE);
    const w=imgRef.current.naturalWidth*scale, h=imgRef.current.naturalHeight*scale, x=SIZE/2-w/2+offset.x, y=SIZE/2-h/2+offset.y;
    ctx.fillStyle="rgba(0,0,0,0.5)"; ctx.fillRect(0,0,SIZE,SIZE);
    ctx.save(); ctx.beginPath(); ctx.arc(SIZE/2,SIZE/2,SIZE/2-2,0,Math.PI*2); ctx.clip(); ctx.clearRect(0,0,SIZE,SIZE); ctx.drawImage(imgRef.current,x,y,w,h); ctx.restore();
    ctx.beginPath(); ctx.arc(SIZE/2,SIZE/2,SIZE/2-2,0,Math.PI*2); ctx.strokeStyle="#ff6eb5"; ctx.lineWidth=3; ctx.stroke();
  }, [scale, offset]);
  useEffect(() => { draw(); }, [draw]);
  const pt = (e) => e.touches ? e.touches[0] : e;
  const handleCrop = () => {
    const out = document.createElement("canvas"); out.width=300; out.height=300;
    const ctx=out.getContext("2d"), ratio=300/SIZE, w=imgRef.current.naturalWidth*scale, h=imgRef.current.naturalHeight*scale, x=SIZE/2-w/2+offset.x, y=SIZE/2-h/2+offset.y;
    ctx.beginPath(); ctx.arc(150,150,150,0,Math.PI*2); ctx.clip(); ctx.drawImage(imgRef.current,x*ratio,y*ratio,w*ratio,h*ratio);
    out.toBlob(blob=>{ const file=new File([blob],"profile.jpg",{type:"image/jpeg"}); onCrop(file,URL.createObjectURL(blob)); },"image/jpeg",0.92);
  };
  return (
    <motion.div initial={{opacity:0,scale:0.9}} animate={{opacity:1,scale:1}} className="flex flex-col items-center gap-4">
      <p className="text-sm font-semibold" style={{color:"var(--text-muted)"}}>Drag to reposition · Scroll to zoom</p>
      <div className="cursor-grab active:cursor-grabbing select-none rounded-full overflow-hidden shadow-2xl" style={{width:SIZE,height:SIZE,border:"4px solid rgba(255,110,181,0.4)"}}
        onMouseDown={e=>{setDragging(true);setDragStart({x:pt(e).clientX-offset.x,y:pt(e).clientY-offset.y});}}
        onMouseMove={e=>{if(!dragging)return;setOffset({x:pt(e).clientX-dragStart.x,y:pt(e).clientY-dragStart.y});}}
        onMouseUp={()=>setDragging(false)} onMouseLeave={()=>setDragging(false)}
        onTouchStart={e=>{setDragging(true);setDragStart({x:pt(e).clientX-offset.x,y:pt(e).clientY-offset.y});}}
        onTouchMove={e=>{if(!dragging)return;setOffset({x:pt(e).clientX-dragStart.x,y:pt(e).clientY-dragStart.y});}}
        onTouchEnd={()=>setDragging(false)}
        onWheel={e=>{e.preventDefault();setScale(s=>Math.max(0.3,Math.min(5,s-e.deltaY*0.002)));}}>
        <canvas ref={canvasRef} width={SIZE} height={SIZE}/>
      </div>
      <div className="flex items-center gap-3 w-full max-w-xs">
        <ZoomOut className="w-4 h-4 flex-shrink-0" style={{color:"var(--text-muted)"}}/>
        <input type="range" min="0.3" max="5" step="0.01" value={scale} onChange={e=>setScale(parseFloat(e.target.value))} className="flex-1" style={{accentColor:"#ff3da0"}}/>
        <ZoomIn className="w-4 h-4 flex-shrink-0" style={{color:"var(--text-muted)"}}/>
      </div>
      <div className="flex gap-3 w-full max-w-xs">
        <button type="button" onClick={onCancel} className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-full font-bold text-sm" style={{border:"2px solid rgba(255,110,181,0.4)",color:"var(--text-secondary)"}}><X className="w-4 h-4"/>Cancel</button>
        <button type="button" onClick={handleCrop} className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-full text-white font-bold text-sm" style={{background:"linear-gradient(135deg,#ff3da0,#ff6eb5)"}}><Check className="w-4 h-4"/>Use Photo</button>
      </div>
    </motion.div>
  );
}