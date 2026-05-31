import React, { useState, useEffect } from "react";
import { base44 } from "@/api/base44Client";
import { Loader2, Crown } from "lucide-react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
function Avatar({ user }) {
  const [err,setErr]=useState(false);
  if(user?.profile_picture&&!err)return<img src={user.profile_picture} onError={()=>setErr(true)} className="w-10 h-10 rounded-full object-cover flex-shrink-0" alt=""/>;
  return<div className="w-10 h-10 rounded-full flex items-center justify-center text-white font-semibold flex-shrink-0" style={{background:"var(--accent-pink)"}}>{(user?.display_name||user?.full_name)?.[0]?.toUpperCase()||"?"}</div>;
}
export default function TopArtistsPage() {
  const [artists,setArtists]=useState([]),[loading,setLoading]=useState(true);
  useEffect(()=>{
    Promise.all([base44.entities.CommunityPost.list("-created_date",500),base44.entities.User.list()]).then(([posts,users])=>{
      const stats={};
      posts.forEach(p=>{if(!p.user_email)return;if(!stats[p.user_email])stats[p.user_email]={posts:0,likes:0};stats[p.user_email].posts+=1;stats[p.user_email].likes+=p.likes?.length||0;});
      const ranked=users.filter(u=>stats[u.email]).map(u=>({...u,...stats[u.email]})).sort((a,b)=>b.likes-a.likes||b.posts-a.posts).slice(0,10);
      setArtists(ranked);
    }).finally(()=>setLoading(false));
  },[]);
  const medalColors=["#f59e0b","#9ca3af","#b45309"];
  return(
    <div className="h-full flex flex-col overflow-hidden">
      <div className="flex-shrink-0 px-4 sm:px-6 py-4 border-b" style={{background:"var(--surface)",borderColor:"var(--border-c)"}}><h1 className="text-base font-semibold" style={{color:"var(--text-primary)"}}>Top Artists</h1><p className="text-xs" style={{color:"var(--text-muted)"}}>Ranked by total likes</p></div>
      <div className="flex-1 overflow-y-auto scroll px-4 sm:px-6 py-4">
        {loading?<div className="flex justify-center py-16"><Loader2 className="w-5 h-5 animate-spin" style={{color:"var(--accent-pink)"}}/></div>:artists.length===0?<p className="text-center text-sm py-16" style={{color:"var(--text-muted)"}}>No artists yet.</p>:
          <div className="max-w-lg mx-auto space-y-2 pb-8">{artists.map((artist,i)=><motion.div key={artist.email} initial={{opacity:0,y:8}} animate={{opacity:1,y:0}} transition={{delay:i*0.04}}>
            <Link to={"/Profile?email="+encodeURIComponent(artist.email)} className="card-sm p-3 flex items-center gap-3 hover:shadow-sm transition-shadow block">
              <div className="w-6 text-center flex-shrink-0">{i<3?<Crown className="w-4 h-4 mx-auto" style={{color:medalColors[i]}}/>:<span className="text-xs font-semibold" style={{color:"var(--text-muted)"}}>{i+1}</span>}</div>
              <Avatar user={artist}/>
              <div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate" style={{color:"var(--text-primary)"}}>{artist.display_name||artist.full_name}</p><p className="text-[10px]" style={{color:"var(--text-muted)"}}>{artist.posts} posts</p></div>
              <div className="text-right flex-shrink-0"><p className="text-sm font-semibold" style={{color:"var(--accent-rose)"}}>{artist.likes}</p><p className="text-[10px]" style={{color:"var(--text-muted)"}}>likes</p></div>
            </Link>
          </motion.div>)}</div>}
      </div>
    </div>
  );
}