import React, { useState, useEffect, useRef, useMemo } from "react";
import { base44 } from "@/api/base44Client";
import { Send, ImageIcon, X, Loader2, Hash, Edit2, Trash2, Pin, AtSign, Reply, Smile, Search, ChevronDown, ChevronUp } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { Link } from "react-router-dom";
import { sendBadMessage } from "../../utils/discordWebhook";
const UploadFile = (args) => base44.integrations.Core.UploadFile(args);
const InvokeLLM = (args) => base44.integrations.Core.InvokeLLM(args);

const REACTIONS = ["❤️","😂","😮","😢","👍","🎉","🔥","✨"];

function Avatar({ user, size=8 }) {
  const [err,setErr]=useState(false);
  const cls=`w-${size} h-${size} rounded-full object-cover flex-shrink-0`;
  if(user?.profile_picture&&!err)return<img src={user.profile_picture} onError={()=>setErr(true)} className={cls} alt=""/>;
  return<div className={`w-${size} h-${size} rounded-full flex items-center justify-center flex-shrink-0 text-white text-xs font-semibold`} style={{ background:"var(--accent-pink)" }}>{(user?.display_name||user?.user_display_name)?.[0]?.toUpperCase()||"?"}</div>;
}

function MessageItem({ msg, me, canDelete, canPin, roles, onDelete, onEdit, onReact, onReply, onPin }) {
  const [hover,setHover]=useState(false),[showReactions,setShowReactions]=useState(false),[showThread,setShowThread]=useState(false),[threadMessages,setThreadMessages]=useState([]),[threadText,setThreadText]=useState(""),[sendingThread,setSendingThread]=useState(false);
  const isOwn=me?.email===msg.user_email;
  const loadThread=async()=>{ if(!showThread){const replies=await base44.entities.ChannelMessage.filter({reply_to_id:msg.id},"created_date");setThreadMessages(replies);}setShowThread(v=>!v);};
  const sendThreadReply=async()=>{if(!me||!threadText.trim())return;setSendingThread(true);await base44.entities.ChannelMessage.create({channel_id:msg.channel_id,community_id:msg.community_id,content:threadText.trim(),image_url:"",user_email:me.email,user_display_name:me.display_name||me.full_name,user_profile_picture:me.profile_picture||"",reply_to_id:msg.id,reply_to_preview:`${msg.user_display_name}: ${msg.content?.slice(0,60)}`,reactions:{},is_pinned:false,is_edited:false});const replies=await base44.entities.ChannelMessage.filter({reply_to_id:msg.id},"created_date");setThreadMessages(replies);setThreadText("");setSendingThread(false);};
  if(msg.user_email==="__system__")return<div className="flex justify-center py-1"><span className="text-[10px] px-3 py-1 rounded-full" style={{ background:"var(--pink-soft)",color:"var(--text-muted)" }}>{msg.content}</span></div>;
  return(
    <div>
      <motion.div initial={msg.grouped?{}:{opacity:0,y:4}} animate={{ opacity:1,y:0 }} onMouseEnter={()=>setHover(true)} onMouseLeave={()=>{setHover(false);setShowReactions(false);}} className={`relative flex gap-2.5 px-3 py-0.5 group rounded-lg transition-colors ${msg.grouped?"pl-[52px]":"pt-2"}`} style={hover?{background:"var(--pink-soft)"}:{}}>
        {msg.reply_to_preview&&!msg.grouped&&<div className="absolute left-14 -top-0 flex items-center gap-1 text-[10px]" style={{ color:"var(--text-muted)" }}><Reply className="w-3 h-3"/><span className="line-clamp-1 max-w-[200px]">{msg.reply_to_preview}</span></div>}
        {!msg.grouped&&<Link to={`/Profile?email=${encodeURIComponent(msg.user_email)}`} className="flex-shrink-0 mt-0.5"><Avatar user={{ profile_picture:msg.user_profile_picture,display_name:msg.user_display_name }}/></Link>}
        <div className="flex-1 min-w-0">
          {!msg.grouped&&<div className="flex items-baseline gap-2 mb-0.5 flex-wrap"><Link to={`/Profile?email=${encodeURIComponent(msg.user_email)}`} className="text-xs font-semibold hover:underline" style={{ color:"var(--text-primary)" }}>{msg.user_display_name}</Link>{msg.is_pinned&&<span className="text-[9px] px-1.5 py-0.5 rounded-full" style={{ background:"#f59e0b22",color:"#f59e0b" }}>📌 Pinned</span>}<span className="text-[10px]" style={{ color:"var(--text-muted)" }}>{new Date(msg.created_date).toLocaleTimeString([],{hour:"2-digit",minute:"2-digit"})}{msg.is_edited&&<span className="ml-1 italic">(edited)</span>}</span></div>}
          {msg.image_url&&<img src={msg.image_url} alt="" className="rounded-xl max-w-[280px] max-h-[280px] object-contain my-1" style={{ border:"1px solid var(--border-c)" }}/>}
          {msg.content&&<p className="text-sm leading-relaxed break-words" style={{ color:"var(--text-primary)" }} dangerouslySetInnerHTML={{ __html:msg.content.replace(/@(\S+)/g,'<span style="color:var(--accent-rose);font-weight:600">@$1</span>') }}/>}
          {msg.reactions&&Object.keys(msg.reactions).length>0&&<div className="flex flex-wrap gap-1 mt-1">{Object.entries(msg.reactions).map(([emoji,users])=>users.length>0&&<button key={emoji} onClick={()=>onReact(msg,emoji)} className="flex items-center gap-0.5 text-xs px-1.5 py-0.5 rounded-full transition-all" style={users.includes(me?.email)?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",border:"1px solid var(--border-c)",color:"var(--text-secondary)"}}>{emoji}<span className="text-[10px] font-semibold">{users.length}</span></button>)}</div>}
          {(msg.thread_count>0||showThread)&&<button onClick={loadThread} className="mt-1 flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full transition-all" style={{ background:"var(--pink-soft)",color:"var(--accent-rose)" }}>{showThread?<ChevronUp className="w-3 h-3"/>:<ChevronDown className="w-3 h-3"/>}{threadMessages.length>0?`${threadMessages.length} replies`:"View thread"}</button>}
        </div>
        {hover&&<div className="absolute right-2 top-1 flex items-center gap-0.5 rounded-xl px-1 py-0.5 shadow-sm border z-10" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
          <button onClick={()=>setShowReactions(!showReactions)} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:"var(--text-muted)" }}><Smile className="w-3.5 h-3.5"/></button>
          <button onClick={()=>onReply(msg)} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:"var(--text-muted)" }}><Reply className="w-3.5 h-3.5"/></button>
          <button onClick={loadThread} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:showThread?"var(--accent-rose)":"var(--text-muted)" }}><ChevronDown className="w-3.5 h-3.5"/></button>
          {isOwn&&<button onClick={()=>onEdit(msg)} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:"var(--text-muted)" }}><Edit2 className="w-3.5 h-3.5"/></button>}
          {canPin&&<button onClick={()=>onPin(msg)} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:msg.is_pinned?"#f59e0b":"var(--text-muted)" }}><Pin className="w-3.5 h-3.5"/></button>}
          {canDelete&&<button onClick={()=>onDelete(msg.id)} className="w-6 h-6 rounded flex items-center justify-center" style={{ color:"#e05a5a" }}><Trash2 className="w-3.5 h-3.5"/></button>}
        </div>}
        {showReactions&&<div className="absolute right-2 top-8 z-20 flex gap-1 p-1.5 rounded-xl shadow-lg border" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>{REACTIONS.map(e=><button key={e} onClick={()=>{onReact(msg,e);setShowReactions(false);}} className="w-7 h-7 rounded-lg flex items-center justify-center text-sm hover:scale-125 transition-transform">{e}</button>)}</div>}
      </motion.div>
      <AnimatePresence>{showThread&&<motion.div initial={{ opacity:0,height:0 }} animate={{ opacity:1,height:"auto" }} exit={{ opacity:0,height:0 }} className="ml-12 mr-3 mb-1 rounded-xl overflow-hidden border-l-2" style={{ borderColor:"var(--accent-pink)",background:"var(--pink-soft)" }}><div className="px-3 py-2 space-y-2 max-h-60 overflow-y-auto scroll">{threadMessages.length===0?<p className="text-[11px] text-center py-2" style={{ color:"var(--text-muted)" }}>No replies yet.</p>:threadMessages.map(tm=><div key={tm.id} className="flex gap-2 items-start"><Avatar user={{ profile_picture:tm.user_profile_picture,display_name:tm.user_display_name }} size={6}/><div><span className="text-[10px] font-semibold mr-1" style={{ color:"var(--text-primary)" }}>{tm.user_display_name}</span><p className="text-xs" style={{ color:"var(--text-secondary)" }}>{tm.content}</p></div></div>)}</div>{me&&<div className="flex items-center gap-2 px-3 pb-2"><input value={threadText} onChange={e=>setThreadText(e.target.value)} onKeyDown={e=>e.key==="Enter"&&sendThreadReply()} placeholder="Reply in thread..." className="flex-1 text-xs bg-transparent border rounded-lg px-2 py-1 focus:outline-none" style={{ borderColor:"var(--border-c)",color:"var(--text-primary)" }}/><button onClick={sendThreadReply} disabled={sendingThread||!threadText.trim()} className="w-6 h-6 rounded-lg flex items-center justify-center text-white disabled:opacity-40" style={{ background:"var(--accent-pink)" }}>{sendingThread?<Loader2 className="w-3 h-3 animate-spin"/>:<Send className="w-3 h-3"/>}</button></div>}</motion.div>}</AnimatePresence>
    </div>
  );
}

function PinnedMessagesPanel({ channelId, onClose }) {
  const [pinned,setPinned]=useState([]),[loading,setLoading]=useState(true);
  useEffect(()=>{base44.entities.ChannelMessage.filter({channel_id:channelId,is_pinned:true},"-created_date").then(msgs=>{setPinned(msgs);setLoading(false);});},[channelId]);
  return(
    <motion.div initial={{ opacity:0,y:-8 }} animate={{ opacity:1,y:0 }} exit={{ opacity:0,y:-8 }} className="absolute top-12 left-0 right-0 z-20 mx-3 rounded-xl shadow-xl border overflow-hidden" style={{ background:"var(--surface)",borderColor:"var(--border-c)",maxHeight:320 }}>
      <div className="flex items-center justify-between px-4 py-2.5 border-b" style={{ borderColor:"var(--border-c)" }}><span className="text-xs font-semibold flex items-center gap-1.5" style={{ color:"var(--text-primary)" }}><Pin className="w-3.5 h-3.5" style={{ color:"#f59e0b" }}/> Pinned Messages</span><button onClick={onClose}><X className="w-4 h-4" style={{ color:"var(--text-muted)" }}/></button></div>
      <div className="overflow-y-auto scroll" style={{ maxHeight:260 }}>{loading?<div className="flex justify-center py-6"><Loader2 className="w-4 h-4 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>:pinned.length===0?<p className="text-xs text-center py-6" style={{ color:"var(--text-muted)" }}>No pinned messages.</p>:pinned.map(msg=><div key={msg.id} className="px-4 py-2.5 border-b last:border-0" style={{ borderColor:"var(--border-c)" }}><div className="flex items-center gap-1.5 mb-0.5"><span className="text-[10px] font-semibold" style={{ color:"var(--accent-rose)" }}>{msg.user_display_name}</span></div>{msg.image_url&&<img src={msg.image_url} className="rounded-lg max-h-16 mb-1" alt=""/>}{msg.content&&<p className="text-xs" style={{ color:"var(--text-secondary)" }}>{msg.content}</p>}</div>)}</div>
    </motion.div>
  );
}

export default function ChatArea({ channel, community, me, roles, myMember, canManage }) {
  const [messages,setMessages]=useState([]),[loading,setLoading]=useState(true),[text,setText]=useState(""),[imgFile,setImgFile]=useState(null),[imgPreview,setImgPreview]=useState(null),[sending,setSending]=useState(false),[editingMsg,setEditingMsg]=useState(null),[replyTo,setReplyTo]=useState(null),[showMentions,setShowMentions]=useState(false),[mentionQuery,setMentionQuery]=useState(""),[searchQuery,setSearchQuery]=useState(""),[showSearch,setShowSearch]=useState(false),[showPinned,setShowPinned]=useState(false);
  const bottomRef=useRef(null),fileRef=useRef(null),inputRef=useRef(null),searchRef=useRef(null);
  const myRoles=useMemo(()=>roles?.filter(r=>myMember?.roles?.includes(r.id))||[],[roles,myMember]);
  const canPost=useMemo(()=>{if(!me)return false;if(canManage)return true;if(!channel?.allowed_roles||channel.allowed_roles.length===0)return true;const myRoleNames=myRoles.map(r=>r.name);return channel.allowed_roles.some(rName=>myRoleNames.includes(rName));},[me,canManage,channel,myRoles]);
  const canPinMessages=useMemo(()=>canManage||myRoles.some(r=>r.permissions?.can_pin_messages),[canManage,myRoles]);
  const canDeleteOthers=useMemo(()=>canManage||myRoles.some(r=>r.permissions?.can_kick_members||r.permissions?.can_manage_channels),[canManage,myRoles]);

  useEffect(()=>{if(!channel)return;setLoading(true);setShowPinned(false);setShowSearch(false);setSearchQuery("");base44.entities.ChannelMessage.filter({channel_id:channel.id},"created_date",100).then(msgs=>{setMessages(msgs);setLoading(false);});},[channel?.id]);
  useEffect(()=>{if(!channel)return;const unsub=base44.entities.ChannelMessage.subscribe(event=>{if(event.type==="create"&&event.data.channel_id===channel.id){setMessages(prev=>prev.find(m=>m.id===event.data.id)?prev:[...prev,event.data]);}else if(event.type==="update"&&event.data.channel_id===channel.id){setMessages(prev=>prev.map(m=>m.id===event.data.id?event.data:m));}else if(event.type==="delete"){setMessages(prev=>prev.filter(m=>m.id!==event.id));}});return unsub;},[channel?.id]);
  useEffect(()=>{if(!searchQuery)bottomRef.current?.scrollIntoView({behavior:"smooth"});},[messages.length,searchQuery]);
  useEffect(()=>{if(showSearch)searchRef.current?.focus();},[showSearch]);

  const handleTextChange=(e)=>{const val=e.target.value;setText(val);const match=val.match(/@(\w*)$/);if(match){setShowMentions(true);setMentionQuery(match[1]);}else{setShowMentions(false);}};
  const insertMention=(name)=>{setText(prev=>prev.replace(/@\w*$/,`@${name} `));setShowMentions(false);inputRef.current?.focus();};

  const send=async(e)=>{e?.preventDefault();if(!me||(!text.trim()&&!imgFile)||!canPost)return;setSending(true);if(editingMsg){await base44.entities.ChannelMessage.update(editingMsg.id,{content:text.trim(),is_edited:true});setEditingMsg(null);setText("");setSending(false);return;}
    if(text.trim()){try{const mod=await InvokeLLM({prompt:`Content moderator. JSON only. Is this chat message safe? Text: "${text.trim()}". Flag hate speech, explicit NSFW, violence. {"safe":true/false,"reason":""}`,response_json_schema:{type:"object",properties:{safe:{type:"boolean"},reason:{type:"string"}}}});if(!mod.safe){sendBadMessage({userEmail:me.email,displayName:me.display_name||me.full_name,communityName:community?.name,channelName:channel?.name,reason:mod.reason,content:text.trim()});setText("");setSending(false);return;}}catch{}}
    let imgUrl="";if(imgFile){const r=await UploadFile({file:imgFile});imgUrl=r.file_url;}
    await base44.entities.ChannelMessage.create({channel_id:channel.id,community_id:community.id,content:text.trim(),image_url:imgUrl,user_email:me.email,user_display_name:me.display_name||me.full_name,user_profile_picture:me.profile_picture||"",reply_to_id:replyTo?.id||"",reply_to_preview:replyTo?`${replyTo.user_display_name}: ${replyTo.content?.slice(0,60)}`:"",reactions:{},is_pinned:false,is_edited:false});
    setText("");setImgFile(null);setImgPreview(null);setReplyTo(null);if(fileRef.current)fileRef.current.value="";setSending(false);};

  const handleDelete=async(id)=>{await base44.entities.ChannelMessage.delete(id);};
  const handleReact=async(msg,emoji)=>{if(!me)return;const reactions={...(msg.reactions||{})};const users=reactions[emoji]?[...reactions[emoji]]:[];const idx=users.indexOf(me.email);if(idx>=0)users.splice(idx,1);else users.push(me.email);reactions[emoji]=users;await base44.entities.ChannelMessage.update(msg.id,{reactions});};
  const handlePin=async(msg)=>{await base44.entities.ChannelMessage.update(msg.id,{is_pinned:!msg.is_pinned});};
  const handleEdit=(msg)=>{setEditingMsg(msg);setText(msg.content);inputRef.current?.focus();};
  const canDeleteMsg=(msg)=>{if(!me)return false;if(me.email===msg.user_email)return true;return me.role==="admin"||me.email===community?.owner_email||canDeleteOthers;};

  const filteredMessages=useMemo(()=>{if(!searchQuery.trim())return messages;const q=searchQuery.toLowerCase();return messages.filter(m=>m.content?.toLowerCase().includes(q)||m.user_display_name?.toLowerCase().includes(q));},[messages,searchQuery]);
  const grouped=useMemo(()=>filteredMessages.reduce((acc,msg,i)=>{const prev=filteredMessages[i-1];const isGrouped=!searchQuery&&prev&&prev.user_email===msg.user_email&&prev.user_email!=="__system__"&&msg.user_email!=="__system__"&&(new Date(msg.created_date)-new Date(prev.created_date))<5*60*1000;acc.push({...msg,grouped:isGrouped});return acc;},[]),[filteredMessages,searchQuery]);
  const mentionSuggestions=[...(roles||[]).map(r=>({id:r.id,name:r.name,color:r.color,isRole:true}))];

  if(!channel)return<div className="flex-1 flex items-center justify-center" style={{ background:"var(--app-bg)" }}><div className="text-center"><Hash className="w-10 h-10 mx-auto mb-2" style={{ color:"var(--text-muted)" }}/><p className="text-sm" style={{ color:"var(--text-muted)" }}>Select a channel</p></div></div>;

  return(
    <div className="flex flex-col relative" style={{ background:"var(--app-bg)",height:"100%",minHeight:0 }}>
      <div className="flex-shrink-0 h-12 px-4 flex items-center gap-2 border-b" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>
        <Hash className="w-4 h-4 flex-shrink-0" style={{ color:"var(--text-muted)" }}/><span className="font-semibold text-sm flex-1 truncate" style={{ color:"var(--text-primary)" }}>{channel.name}</span>
        {channel.allowed_roles?.length>0&&<span className="hidden sm:flex items-center gap-1 text-[10px] px-2 py-0.5 rounded-full font-medium" style={{ background:"var(--pink-soft)",color:"var(--accent-rose)" }}>🔒 {channel.allowed_roles.join(", ")}</span>}
        <button onClick={()=>setShowPinned(v=>!v)} className="w-7 h-7 rounded-lg flex items-center justify-center transition-all" style={showPinned?{background:"#f59e0b",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-muted)"}}><Pin className="w-3.5 h-3.5"/></button>
        <button onClick={()=>{setShowSearch(v=>!v);if(showSearch)setSearchQuery("");}} className="w-7 h-7 rounded-lg flex items-center justify-center transition-all" style={showSearch?{background:"var(--accent-pink)",color:"white"}:{background:"var(--pink-soft)",color:"var(--text-muted)"}}><Search className="w-3.5 h-3.5"/></button>
      </div>
      <AnimatePresence>{showSearch&&<motion.div initial={{ height:0,opacity:0 }} animate={{ height:"auto",opacity:1 }} exit={{ height:0,opacity:0 }} className="flex-shrink-0 overflow-hidden border-b" style={{ borderColor:"var(--border-c)",background:"var(--surface)" }}><div className="px-4 py-2 flex items-center gap-2"><Search className="w-3.5 h-3.5 flex-shrink-0" style={{ color:"var(--text-muted)" }}/><input ref={searchRef} value={searchQuery} onChange={e=>setSearchQuery(e.target.value)} placeholder="Search messages..." className="flex-1 bg-transparent text-sm focus:outline-none" style={{ color:"var(--text-primary)" }}/>{searchQuery&&<span className="text-[10px] font-medium px-2 py-0.5 rounded-full" style={{ background:"var(--pink-soft)",color:"var(--accent-rose)" }}>{filteredMessages.length} result{filteredMessages.length!==1?"s":""}</span>}<button onClick={()=>{setSearchQuery("");setShowSearch(false);}}><X className="w-3.5 h-3.5" style={{ color:"var(--text-muted)" }}/></button></div></motion.div>}</AnimatePresence>
      <AnimatePresence>{showPinned&&<PinnedMessagesPanel channelId={channel.id} onClose={()=>setShowPinned(false)}/>}</AnimatePresence>
      <div className="flex-1 overflow-y-auto scroll py-2">
        {loading?<div className="flex justify-center py-12"><Loader2 className="w-5 h-5 animate-spin" style={{ color:"var(--accent-pink)" }}/></div>:grouped.length===0?<div className="flex flex-col items-center justify-center h-full gap-2 text-center px-6">{searchQuery?<><Search className="w-8 h-8" style={{ color:"var(--text-muted)" }}/><p className="text-sm font-medium" style={{ color:"var(--text-primary)" }}>No messages found</p></>:<><div className="w-12 h-12 rounded-2xl flex items-center justify-center" style={{ background:"var(--pink-soft)" }}><Hash className="w-6 h-6" style={{ color:"var(--accent-pink)" }}/></div><p className="font-semibold text-sm" style={{ color:"var(--text-primary)" }}>Welcome to #{channel.name}!</p><p className="text-xs" style={{ color:"var(--text-muted)" }}>{channel.description||"This is the beginning of this channel."}</p></>}</div>
          :grouped.map(msg=><MessageItem key={msg.id} msg={msg} me={me} roles={roles} canDelete={canDeleteMsg(msg)} canPin={canPinMessages} onDelete={handleDelete} onEdit={handleEdit} onReact={handleReact} onReply={setReplyTo} onPin={handlePin}/>)}
        <div ref={bottomRef}/>
      </div>
      <div className="flex-shrink-0 px-3 pt-1 border-t" style={{ borderColor:"var(--border-c)",background:"var(--surface)",paddingBottom:"max(12px,env(safe-area-inset-bottom,12px))" }}>
        {showMentions&&mentionSuggestions.filter(m=>m.name.toLowerCase().startsWith(mentionQuery.toLowerCase())).length>0&&<div className="mb-2 rounded-xl border overflow-hidden shadow-lg" style={{ background:"var(--surface)",borderColor:"var(--border-c)" }}>{mentionSuggestions.filter(m=>m.name.toLowerCase().startsWith(mentionQuery.toLowerCase())).map(m=><button key={m.id} onClick={()=>insertMention(m.name)} className="w-full text-left flex items-center gap-2 px-3 py-2 text-xs transition-all" onMouseEnter={e=>e.currentTarget.style.background="var(--pink-soft)"} onMouseLeave={e=>e.currentTarget.style.background="transparent"}>{m.isRole&&<span className="w-4 h-4 rounded-full flex-shrink-0" style={{ background:m.color }}/>}<span style={{ color:m.color||"var(--text-primary)" }}>{m.isRole?`@${m.name}`:m.name}</span></button>)}</div>}
        {replyTo&&<div className="mb-1 flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs" style={{ background:"var(--pink-soft)",color:"var(--text-muted)" }}><Reply className="w-3 h-3 flex-shrink-0"/><span className="flex-1 truncate">Replying to <strong>{replyTo.user_display_name}</strong>: {replyTo.content?.slice(0,40)}</span><button onClick={()=>setReplyTo(null)}><X className="w-3 h-3"/></button></div>}
        {editingMsg&&<div className="mb-1 flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs" style={{ background:"#f59e0b22",color:"#f59e0b" }}><Edit2 className="w-3 h-3 flex-shrink-0"/><span className="flex-1">Editing message</span><button onClick={()=>{setEditingMsg(null);setText("");}}><X className="w-3 h-3"/></button></div>}
        {imgPreview&&<div className="mb-1 relative w-fit"><img src={imgPreview} className="h-14 w-14 object-cover rounded-xl" alt=""/><button onClick={()=>{setImgFile(null);setImgPreview(null);}} className="absolute -top-1 -right-1 w-5 h-5 bg-white rounded-full flex items-center justify-center shadow" style={{ border:"1px solid var(--border-c)" }}><X className="w-2.5 h-2.5 text-gray-500"/></button></div>}
        {!canPost&&me?<div className="flex items-center justify-center gap-2 rounded-xl px-4 py-3 text-xs" style={{ background:"var(--pink-soft)",color:"var(--text-muted)",border:"1px solid var(--border-c)" }}>🔒 You need the <span className="font-semibold" style={{ color:"var(--accent-rose)" }}>{channel.allowed_roles?.join(" or ")}</span> role to post.</div>
          :<div className="flex items-center gap-2 rounded-xl px-3 py-2" style={{ background:"var(--pink-soft)",border:"1px solid var(--border-c)" }}>
            <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={e=>{const f=e.target.files?.[0];if(f?.type.startsWith("image/")){setImgFile(f);setImgPreview(URL.createObjectURL(f));}}}/>
            <button onClick={()=>fileRef.current?.click()} className="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background:"var(--surface)" }}><ImageIcon className="w-3.5 h-3.5" style={{ color:"var(--text-muted)" }}/></button>
            <button onClick={()=>{setText(prev=>prev+"@");inputRef.current?.focus();}} className="w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background:"var(--surface)" }}><AtSign className="w-3.5 h-3.5" style={{ color:"var(--text-muted)" }}/></button>
            <input ref={inputRef} value={text} onChange={handleTextChange} onKeyDown={e=>e.key==="Enter"&&!e.shiftKey&&send(e)} placeholder={`Message #${channel.name}...`} className="flex-1 bg-transparent text-sm focus:outline-none min-w-0" style={{ color:"var(--text-primary)" }}/>
            <button onClick={send} disabled={sending||(!text.trim()&&!imgFile)} className="w-7 h-7 rounded-lg flex items-center justify-center text-white flex-shrink-0 disabled:opacity-40" style={{ background:"var(--accent-pink)" }}>{sending?<Loader2 className="w-3.5 h-3.5 animate-spin"/>:<Send className="w-3.5 h-3.5"/>}</button>
          </div>}
      </div>
    </div>
  );
}