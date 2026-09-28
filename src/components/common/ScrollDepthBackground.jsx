import React, {useEffect, useRef} from 'react';

// Only transforms two decorative layers on scroll; no animation loop at rest.
export default function ScrollDepthBackground({scrollRef, route, disabled}) {
  const layer=useRef(null);
  useEffect(()=>{
    const scroll=scrollRef.current, node=layer.current;
    if(!scroll || !node || disabled) return;
    const media=matchMedia('(prefers-reduced-motion: reduce)');
    let frame=0;
    const update=()=>{
      frame=0;
      if(media.matches || document.hidden || document.querySelector('[aria-modal="true"]')) return;
      const depth=Math.min(120,Math.max(-120,scroll.scrollTop/12));
      node.style.setProperty('--scroll-depth',`${depth}px`);
    };
    const schedule=()=>{if(!frame) frame=requestAnimationFrame(update);};
    const reset=()=>{node.style.setProperty('--scroll-depth','0px');schedule();};
    scroll.addEventListener('scroll',schedule,{passive:true});media.addEventListener('change',reset);reset();
    return()=>{cancelAnimationFrame(frame);scroll.removeEventListener('scroll',schedule);media.removeEventListener('change',reset);};
  },[scrollRef,route,disabled]);
  if(disabled) return null;
  return <div ref={layer} aria-hidden="true" className="pointer-events-none absolute inset-0 overflow-hidden" style={{'--scroll-depth':'0px'}}>
    <div className="absolute -right-20 top-12 w-72 h-72 rounded-full" style={{background:'radial-gradient(circle, rgb(var(--accent-rgb)/0.12), transparent 70%)',transform:'translate3d(0, calc(var(--scroll-depth) * -0.35), 0)'}} />
    <div className="absolute left-4 bottom-24 text-8xl select-none" style={{color:'rgb(var(--accent-rgb)/0.07)',transform:'perspective(700px) translate3d(0, calc(var(--scroll-depth) * -0.65), 15px) rotate(-15deg)'}}>♥</div>
  </div>;
}
