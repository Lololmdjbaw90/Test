import React, { useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Link } from "react-router-dom";
import { AnimatePresence, motion } from "framer-motion";
import { ChevronDown, Maximize2, MessageSquare, Minimize2, Phone, PhoneOff, Video } from "lucide-react";
import voice, { playTone } from "@/lib/voice";
import { RING_MS, callTitle, declineCall, joinCall } from "@/lib/calls";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { toast } from "@/lib/toast";
import { useIsMobile } from "@/lib/useMediaQuery";
import { useDelayedUnmount } from "@/components/common/Modal";
import Avatar from "@/components/common/Avatar";
import CallStage from "@/components/voice/CallStage";
import { useElapsed, useNow, useVoice } from "@/components/voice/useVoice";

const person = (call, email) => ({ email, name: call.member_names?.[email] || email.split("@")[0], picture: call.member_pictures?.[email] || "" });

function IncomingCall({ call, me, onAccept, onDecline }) {
  // Ring (and buzz on phones) until answered, declined or timed out.
  useEffect(() => {
    if (!call) return undefined;
    const ring = () => { playTone("ring"); try { if (navigator.userActivation?.hasBeenActive) navigator.vibrate?.([250, 120, 250]); } catch { /* ignore */ } };
    ring();
    const t = setInterval(ring, 2200);
    return () => clearInterval(t);
  }, [call?.id]);

  return createPortal(
    <div className="fixed z-[160] inset-x-0 top-0 flex justify-center p-3 pointer-events-none" style={{ paddingTop: "max(0.75rem, env(safe-area-inset-top))" }}>
      <AnimatePresence>
        {call && (
          <motion.div
            key={call.id}
            initial={{ opacity: 0, y: -30, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -30, scale: 0.96 }}
            transition={{ type: "spring", stiffness: 380, damping: 30 }}
            className="call-stage pointer-events-auto w-full sm:w-[400px] rounded-[1.75rem] p-4 flex items-center gap-3.5 overflow-hidden"
            style={{ boxShadow: "0 24px 60px rgb(0 0 0 / 0.45)" }}
            role="alertdialog"
            aria-label={`Incoming call from ${call.caller_name}`}
          >
            <span className="relative flex-shrink-0">
              <span className="ripple" /><span className="ripple" />
              <Avatar src={call.caller_picture} name={call.caller_name} size={52} />
            </span>
            <div className="flex-1 min-w-0">
              <p className="font-bold truncate">{call.conversation_type === "group" ? call.group_name : call.caller_name}</p>
              <p className="text-xs opacity-75 truncate">
                {call.conversation_type === "group" ? `${call.caller_name} started a ${call.video ? "video" : "voice"} call` : `Incoming ${call.video ? "video" : "voice"} call…`}
              </p>
            </div>
            <button onClick={() => onDecline(call)} className="call-btn call-btn-danger !w-11 !h-11" aria-label="Decline call" title="Decline"><PhoneOff className="w-5 h-5" /></button>
            {call.video && <button onClick={() => onAccept(call, true)} className="call-btn call-btn-accept !w-11 !h-11" aria-label="Accept with video" title="Accept with video"><Video className="w-5 h-5" /></button>}
            <button onClick={() => onAccept(call, false)} className="call-btn call-btn-accept !w-11 !h-11" aria-label="Accept call" title={call.video ? "Accept (voice only)" : "Accept"}><Phone className="w-5 h-5" /></button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>,
    document.body,
  );
}

// The call window: full screen on phones, a floating window (or full screen) on desktop.
function CallWindow({ vs, call, me, now }) {
  const isMobile = useIsMobile();
  const [full, setFull] = useState(false);
  const open = vs.room?.type === "call" && vs.expanded && (vs.connected || vs.connecting);
  const mounted = useDelayedUnmount(open, 240);
  const last = useRef({ vs, call });
  if (open) last.current = { vs, call };
  const view = open ? { vs, call } : last.current;
  const elapsed = useElapsed(view.call?.answered_at || view.vs.joinedAt);
  if (!mounted || !view.vs.room) return null;

  const c = view.call;
  const room = view.vs.room;
  const inCall = new Set(view.vs.participants.map((p) => p.email));
  const invitees = c ? c.member_emails.filter((e) => e !== me.email && !(c.declined_by || []).includes(e)).map((e) => person(c, e)) : [];
  const stillRinging = c && c.status !== "ended" && now - (c.started_at || 0) < RING_MS;
  const ringing = stillRinging ? invitees.filter((p) => !inCall.has(p.email)) : [];
  const alone = view.vs.participants.length <= 1;
  const calling = alone && (!c || c.status === "ringing" || ringing.length)
    ? { title: c ? callTitle(c, me) : room.name, status: !c || c.caller_email === me.email ? (c?.video ? "Video calling…" : "Calling…") : "Connecting…", people: invitees.length ? invitees : [{ email: room.id, name: room.name, picture: "" }] }
    : null;
  const status = view.vs.connecting ? "Connecting…" : calling ? calling.status : `${elapsed} · ${view.vs.participants.length} in call`;
  const fullScreen = isMobile || full;
  const minimize = () => voice.setExpanded(false);

  return createPortal(
    <motion.div
      className={`fixed z-[100] ${fullScreen ? "inset-0" : "right-5 bottom-5 w-[min(760px,calc(100vw-2.5rem))] h-[min(520px,calc(100vh-2.5rem))] rounded-[1.75rem] overflow-hidden"}`}
      initial={{ opacity: 0, y: 40, scale: 0.97 }}
      animate={open ? { opacity: 1, y: 0, scale: 1 } : { opacity: 0, y: 40, scale: 0.97 }}
      transition={{ type: "spring", stiffness: 360, damping: 32 }}
      style={{ pointerEvents: open ? "auto" : "none", boxShadow: fullScreen ? undefined : "0 30px 80px rgb(0 0 0 / 0.45)" }}
      role="dialog"
      aria-label={`Call with ${room.name}`}
    >
      <div className="call-stage h-full flex flex-col">
        <div className="flex items-center gap-2 px-3 pb-1" style={{ paddingTop: fullScreen ? "max(0.75rem, env(safe-area-inset-top))" : "0.75rem" }}>
          <button onClick={minimize} className="call-btn !w-10 !h-10 !bg-transparent hover:!bg-white/10" aria-label="Minimize call" title="Minimize">{isMobile ? <ChevronDown className="w-5 h-5" /> : <Minimize2 className="w-4 h-4" />}</button>
          <div className={`flex-1 min-w-0 ${isMobile ? "text-center" : ""}`}>
            <p className="font-bold truncate leading-tight">{c ? callTitle(c, me) : room.name}</p>
            <p className="text-xs opacity-70 tabular-nums">{status}</p>
          </div>
          {!isMobile && <button onClick={() => setFull((v) => !v)} className="call-btn !w-10 !h-10 !bg-transparent hover:!bg-white/10" aria-label={full ? "Exit full screen" : "Full screen"} title={full ? "Exit full screen" : "Full screen"}><Maximize2 className="w-4 h-4" /></button>}
          {room.link && <Link to={room.link} onClick={minimize} className="call-btn !w-10 !h-10 !bg-transparent hover:!bg-white/10" aria-label="Open chat" title="Open chat"><MessageSquare className="w-4 h-4" /></Link>}
        </div>
        <CallStage vs={view.vs} calling={calling} ringing={alone ? [] : ringing} className="flex-1" bare />
      </div>
    </motion.div>,
    document.body,
  );
}

// Lives in the app shell: rings for incoming calls, shows the call window,
// and hangs up calls that were declined, ended by the other side or unanswered.
export default function CallManager({ me }) {
  const vs = useVoice();
  const now = useNow(2000);
  const [dismissed, setDismissed] = useState(() => new Set());
  const { data: calls } = useLiveQuery("Call", { member_emails: { $contains: me.email } }, { sort: "-created_date", limit: 15 });
  const current = vs.room?.type === "call" ? calls.find((c) => c.id === vs.room.id) : null;

  const incoming = useMemo(() => calls.find((c) =>
    c.caller_email !== me.email && c.status !== "ended" && now - (c.started_at || 0) < RING_MS &&
    !(c.declined_by || []).includes(me.email) && !(c.joined_emails || []).includes(me.email) &&
    vs.room?.id !== c.id && !dismissed.has(c.id)), [calls, me.email, now, vs.room?.id, dismissed]);

  // The other side ended / declined the call.
  useEffect(() => {
    if (!current || current.status !== "ended" || !vs.connected) return;
    const declined = !current.answered_at && (current.declined_by || []).length > 0;
    toast(declined ? `${callTitle(current, me)} declined the call` : "Call ended", { icon: <PhoneOff className="w-5 h-5" /> });
    voice.leave();
  }, [current?.status, vs.connected]); // eslint-disable-line react-hooks/exhaustive-deps

  // Nobody picked up.
  useEffect(() => {
    if (!current || current.caller_email !== me.email || current.answered_at || !vs.connected) return undefined;
    const t = setTimeout(() => {
      if (voice.getState().participants.length <= 1) { toast("No answer", { icon: <PhoneOff className="w-5 h-5" /> }); voice.leave(); }
    }, Math.max(0, (current.started_at || 0) + RING_MS - Date.now()));
    return () => clearTimeout(t);
  }, [current?.id, current?.answered_at, vs.connected]); // eslint-disable-line react-hooks/exhaustive-deps

  // One-to-one call and the other person vanished (closed the tab, lost network).
  const hadOthers = useRef(false);
  const others = vs.participants.length - 1;
  useEffect(() => {
    if (!current || current.conversation_type === "group") { hadOthers.current = false; return undefined; }
    if (others > 0) { hadOthers.current = true; return undefined; }
    if (!hadOthers.current) return undefined;
    const t = setTimeout(() => { if (voice.getState().participants.length <= 1) voice.leave(); }, 8000);
    return () => clearTimeout(t);
  }, [current?.id, others]); // eslint-disable-line react-hooks/exhaustive-deps

  const accept = async (call, video) => {
    setDismissed((s) => new Set(s).add(call.id));
    const ok = await joinCall(call, me, { video });
    if (!ok) toast.error("Could not join the call.");
  };
  const decline = (call) => {
    setDismissed((s) => new Set(s).add(call.id));
    declineCall(call, me);
  };

  return (
    <>
      <IncomingCall call={incoming} me={me} onAccept={accept} onDecline={decline} />
      <CallWindow vs={vs} call={current} me={me} now={now} />
    </>
  );
}
