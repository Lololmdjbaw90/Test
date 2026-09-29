import React, { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft, Check, FileText, HelpCircle, LifeBuoy, Loader2, Send, Shield, Users } from "lucide-react";
import { base44 } from "@/api/base44Client";
import { useAuth } from "@/lib/AuthContext";
import { displayName } from "@/lib/format";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { BrandLogo } from "@/components/common/Brand";
import { LEGAL_SITE } from "@/lib/site";

// Terms, Privacy Policy, Community Guidelines and Help & FAQ. Reachable
// without logging in (App Store review, the sign-up screen).
// NOTE for the owner: this is a solid starting point written for how Sugerly
// works, not legal advice — have it checked before a public release.
// Support works without an email address: the "Contact us" form on the Help
// page lands in Admin → Reports (type "support"); answer by DM.
const UPDATED = "September 29, 2026";

const DOCS = {
  terms: {
    title: "Terms of Use",
    icon: FileText,
    sections: [
      ["Agreeing to these terms", "By creating an account or using Sugerly (the app and the website) you agree to these Terms, our Privacy Policy and our Community Guidelines. If you don't agree, please don't use Sugerly."],
      ["Who can use Sugerly", "You must be at least 13 years old (or the minimum age for online services in your country, if higher). If you're under 18, you need permission from a parent or guardian, and a parent must agree before you buy a commission. You're responsible for your account and for keeping your password safe."],
      ["Your content", "You own the art, music, reels, posts, comments and messages you share. By posting them, you give Sugerly a worldwide, non-exclusive, royalty-free licence to host, store, show and share them inside Sugerly so the service can work (for example to show your reel in the feed). This licence ends when you delete the content or your account, except for copies other people already shared with you or that we must keep by law. Only post things you have the right to share."],
      ["Zero tolerance for objectionable content and abusive users", "There is no place on Sugerly for objectionable content or abusive behaviour. You must not post or send anything that is illegal, hateful, harassing, sexually explicit, violent, or that sexualises minors; that bullies or threatens others; that is spam or a scam; or that infringes someone else's rights. You can report any post, reel, comment, message or person, and block anyone. We review reports within 24 hours and will remove content that breaks these rules and suspend or ban the accounts that posted it."],
      ["Safety tools", "Every post, reel, comment, message and profile has Report, and you can Block people from their profile. Blocked people can't message you, call you or see your posts. Captions, comments and messages are checked automatically for harmful words, and unclear cases can get a second check by AI (see the Privacy Policy)."],
      ["Commissions", "Artists can offer commissions: custom art made on request. The deal is between the buyer and the artist. The artist agrees to make what was described at the agreed price, and the buyer pays through Sugerly. Card payments are processed by Stripe; Sugerly never sees your full card number. Sugerly keeps a small service fee (shown to artists in their shop) and pays the rest to the artist after the buyer approves the finished art. Artists keep the copyright of their art; the buyer gets a personal, non-commercial licence to use what they commissioned unless the artist agrees otherwise. Artists are responsible for their own taxes. Never agree to pay outside Sugerly: we can't protect those payments."],
      ["Cancellations and refunds", "You can cancel for free before you pay. After paying, you can ask for a refund until you approve the art; our team looks at every request and refunds the full amount to your card when the artist didn't deliver what was agreed. Because commissions are made to your personal request, the 14-day right of withdrawal doesn't apply once the artist has started, where the law allows this. This doesn't affect your other rights as a consumer."],
      ["Music, GIFs and AI", "Song previews come from Deezer and GIFs from GIPHY. If you connect Apple Music, whole songs play through your own Apple Music subscription. All of these belong to their owners and are only played inside Sugerly. Where offered, \"Write with AI\" uses Google's Gemini (through Firebase) to suggest captions from your picture; suggestions can be wrong, so check them before posting."],
      ["Coins, levels, rewards and MimiPlus", "Coins, XP, levels and MimiPlus are just for fun inside Sugerly. Coins are earned (daily rewards, invites, posting) and can't be bought, sold or exchanged for money, and MimiPlus is unlocked with coins only. They may change."],
      ["Ending your account", "You can delete your account at any time in Settings. We may suspend or remove accounts that break these Terms. Open commissions are cancelled or refunded as described above."],
      ["No warranty", "Sugerly is provided \"as is\". We work hard to keep it running and safe, but we can't promise it will always be available or error-free. To the extent the law allows, we aren't liable for indirect or consequential losses. Nothing in these Terms limits rights you have by law as a consumer."],
      ["Apple", "If you use the iPhone or iPad app, these Terms are between you and Sugerly, not Apple. Apple isn't responsible for the app, its content, support or any claims about it, and Apple and its subsidiaries may enforce these Terms as third-party beneficiaries."],
      ["Changes", "We may update these Terms. If the changes are important we'll tell you in the app (What's new). Using Sugerly after that means you accept the new Terms."],
      ["Contact", "Questions or requests? Use Contact us in the app (Settings → Help & legal) or on the Help page of the website. We usually reply within 2 days."],
    ],
  },
  privacy: {
    title: "Privacy Policy",
    icon: Shield,
    sections: [
      ["What we collect", "Account details you give us: email address, display name, profile picture, banner and bio. What you create: artworks, posts, reels, music, comments, messages, likes, follows and reports. If you use commissions: your orders, prices and payment status (card details go straight to Stripe; we never see or store your full card number). Artists can add a PayPal email for payouts, which only admins can see. We don't collect your location, contacts or advertising identifiers, and we don't track you across other apps or websites."],
      ["Camera, microphone and face filters", "Camera and microphone are used only while you record a reel, take a photo, send a voice note or join a call. Face filters find your face on your device to place the effect; no face data is stored or sent anywhere."],
      ["On your device only", "What you watch in Reels (watch time, skips) is used to personalise your feed and stays on your device. Your theme, sounds and haptics settings are also stored on your device."],
      ["How we use it", "To run Sugerly: show your profile and content, deliver messages and notifications, recommend posts and reels, handle commissions and payouts, keep the community safe (moderation, reports, blocking) and fix problems. We don't sell your personal data and we don't show ads."],
      ["Safety checks with AI", "What you write is first checked on your device. If a caption, comment or message looks unclear, only its text (not your name or email) may be sent to Google's Gemini through Firebase AI Logic for a second opinion on whether it breaks the rules."],
      ["Services we use", "Google Firebase (accounts, database, file storage and hosting); Google Gemini through Firebase AI Logic (the safety checks above, and \"Write with AI\" when you tap it: the picture and your draft are sent to suggest captions); Stripe (card payments); PayPal (artist payouts); Apple Music (only if you connect it: Apple handles your subscription and we don't get your Apple ID); GIPHY (GIF search); Deezer (song previews); and, for calls, direct peer-to-peer connections between the people in the call. Each processes data under its own privacy policy. Some are based in the United States and protect transfers with the safeguards the law requires, such as standard contractual clauses."],
      ["Why we can use it (EU and UK)", "To provide Sugerly under our Terms (contract); to keep it safe and prevent abuse and fraud (legitimate interests); with your permission for camera, microphone, photos and Apple Music, which you can withdraw any time in iOS Settings (consent); and to keep payment records (legal obligation)."],
      ["Who can see what", "Your profile, posts, reels, artworks and comments are visible to other Sugerly users. Direct messages and group chats are visible only to the people in them (and to moderators when a message is reported). Commission orders are visible to the buyer, the artist and admins. Admins can see content and reports to keep Sugerly safe."],
      ["How long we keep it", "As long as your account exists. When you delete your account, your profile and content are deleted from our database; backups are cleared within 30 days. Payment records are kept as long as tax and accounting laws require, and reports may be kept longer when needed for safety or the law."],
      ["Your rights", "You can see and edit your profile in Settings and delete your account there; on the website you can also download a copy of your data (Settings → Account & data). Depending on where you live (for example the EU/UK under the GDPR, or California) you may also have rights to access, correct, delete or move your data and to object to processing, and you can complain to your data protection authority. Contact us to use them."],
      ["Children", "Sugerly isn't for children under 13 and we don't knowingly collect their data. If you believe a child under 13 has an account, contact us and we'll delete it."],
      ["Security", "Data is sent over encrypted connections and protected by Firebase security rules that only let people read and change what they're allowed to. Only our payment server can mark an order as paid."],
      ["Changes", "We'll tell you in the app if this policy changes in an important way."],
      ["Contact", "Questions or requests? Use Contact us in the app (Settings → Help & legal) or on the Help page of the website. We usually reply within 2 days."],
    ],
  },
  guidelines: {
    title: "Community Guidelines",
    icon: Users,
    sections: [
      ["Be kind", "Sugerly is a friendly place for artists. Give feedback kindly, celebrate each other's work, and never bully, harass or threaten anyone."],
      ["Post your own work", "Share art, music and reels you made or have the right to share. Credit collaborators and references. Don't trace or repost other people's work as your own."],
      ["Keep it safe for everyone", "No nudity or sexual content, no gore or glorified violence, no hate speech, no self-harm encouragement, no illegal goods, and nothing that sexualises minors — ever."],
      ["No spam, scams or links", "Don't spam, sell followers, impersonate others, or post scam links. Links aren't allowed in reel captions or bios."],
      ["Fair commissions", "Only offer what you can make, be honest about prices and timing, deliver your own work, and keep all payments inside Sugerly."],
      ["Protect privacy", "Don't share other people's personal information (addresses, phone numbers, private photos) without permission."],
      ["If you see something", "Use Report on the post, reel, comment, message or profile, and Block anyone you don't want to hear from. Our moderators review reports within 24 hours and remove content and accounts that break these rules."],
    ],
  },
};

const FAQ = [
  ["How do I post a reel?", "Tap + and choose \"Create a reel\". Film in clips (tap to start and pause), or pick a video or several pictures from your library for a slideshow. Then edit, add music and post."],
  ["How do I add music to my reel?", "In the reel editor, open Sound and pick a song from Top charts or search for one."],
  ["Can I turn off comments on my reel?", "Yes — switch off \"Allow comments\" when posting, or use the ⋯ menu on your reel later."],
  ["How do I report or block someone?", "Use Report from the ⋯ menu on any post, reel, comment or message, or open their profile and tap Block."],
  ["How do I change the app colour and logo?", "Settings → Appearance → Accent color. The logo changes to match."],
  ["Why can't I add a link to my caption or bio?", "To protect everyone from spam and scams, links aren't allowed there."],
  ["How do I delete my account?", "Settings → Account & data → Delete account. This deletes your profile and content."],
  ["Is Sugerly free?", "Yes. Coins and levels are just for fun and have no money value. The only thing that costs money is a commission, which you pay to the artist you hire."],
];

// Support without an email address: the message is stored like a report
// (only admins can read it) and the team answers with a direct message.
function ContactForm({ email }) {
  const { user } = useAuth();
  const [text, setText] = useState("");
  const [state, setState] = useState("idle"); // idle | sending | sent | error
  const send = async (e) => {
    e.preventDefault();
    if (!text.trim() || !user) return;
    setState("sending");
    try {
      await base44.entities.Report.create({
        target_type: "support",
        target_id: user.email,
        target_owner_email: user.email,
        target_preview: "",
        link: `/Profile?email=${encodeURIComponent(user.email)}`,
        reason: "Support request",
        details: text.trim().slice(0, 1000),
        reporter_email: user.email,
        reporter_name: displayName(user),
        status: "open",
      });
      setText("");
      setState("sent");
    } catch {
      setState("error");
    }
  };
  return (
    <section id="contact" className="card-sm p-5 mt-6 scroll-mt-6">
      <h2 className="font-bold flex items-center gap-2 mb-1" style={{ color: "var(--text-primary)" }}><LifeBuoy className="w-5 h-5" style={{ color: "rgb(var(--accent-rgb))" }} /> Contact us</h2>
      <p className="text-sm mb-3" style={{ color: "var(--text-secondary)" }}>
        Questions, problems, account or privacy requests — write to the Sugerly team and we'll reply with a message in the app{email ? <> (or email <a href={`mailto:${email}`} className="font-semibold underline">{email}</a>)</> : ""}.
      </p>
      {LEGAL_SITE ? (
        <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>In the Sugerly app, open Settings → Help & legal → Contact us.</p>
      ) : !user ? (
        <Link to="/Login" className="btn-primary inline-flex">Log in to contact us</Link>
      ) : state === "sent" ? (
        <p className="text-sm font-semibold flex items-center gap-2" style={{ color: "var(--success)" }}><Check className="w-4 h-4" /> Sent! We'll get back to you in your messages.</p>
      ) : (
        <form onSubmit={send} className="space-y-2">
          <textarea className="input min-h-[110px] resize-y" maxLength={1000} placeholder="How can we help?" value={text} onChange={(e) => setText(e.target.value)} aria-label="Your message" required />
          {state === "error" && <p className="text-xs" style={{ color: "var(--danger)" }}>Couldn't send — check your connection and try again.</p>}
          <button type="submit" className="btn-primary" disabled={state === "sending" || !text.trim()}>
            {state === "sending" ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />} Send
          </button>
        </form>
      )}
    </section>
  );
}

export default function Legal({ doc: forced }) {
  const params = useParams();
  const navigate = useNavigate();
  const doc = forced || params.doc || "help";
  const { data: configs } = useLiveQuery("SiteConfig", { key: "global" }, { live: false });
  const email = configs[0]?.support_email || import.meta.env.VITE_SUPPORT_EMAIL || "";
  const page = DOCS[doc];
  const back = () => (window.history.length > 1 ? navigate(-1) : navigate("/"));

  return (
    <div className="h-full overflow-y-auto overscroll-contain" style={{ background: "var(--app-bg)", paddingTop: "env(safe-area-inset-top)" }}>
      <div className="max-w-2xl mx-auto px-5 py-6 pb-24">
        <div className="flex items-center gap-3 mb-6">
          <button onClick={back} className="icon-btn icon-btn-bordered" aria-label="Back"><ArrowLeft className="w-5 h-5" /></button>
          <BrandLogo height={34} />
        </div>
        <nav className="flex gap-2 overflow-x-auto no-scrollbar mb-6" aria-label="Help and legal">
          {[["help", "Help & FAQ"], ["terms", "Terms"], ["privacy", "Privacy"], ["guidelines", "Guidelines"]].map(([id, label]) => (
            <Link key={id} to={id === "help" ? "/Help" : `/Legal/${id}`} replace className="flex-shrink-0 px-3.5 py-1.5 rounded-full text-xs font-bold" style={{ background: doc === id ? "var(--accent-grad)" : "var(--surface-2)", color: doc === id ? "#fff" : "var(--text-secondary)" }}>{label}</Link>
          ))}
        </nav>

        {page ? (
          <article>
            <h1 className="font-display text-3xl mb-1 flex items-center gap-2" style={{ color: "var(--text-primary)" }}><page.icon className="w-7 h-7" /> {page.title}</h1>
            <p className="text-xs mb-6" style={{ color: "var(--text-muted)" }}>Last updated {UPDATED}</p>
            <div className="space-y-5">
              {page.sections.map(([h, t]) => (
                <section key={h}>
                  <h2 className="font-bold mb-1" style={{ color: "var(--text-primary)" }}>{h}</h2>
                  <p className="text-sm leading-relaxed select-text" style={{ color: "var(--text-secondary)" }}>{t}</p>
                </section>
              ))}
              <section>
                <h2 className="font-bold mb-1" style={{ color: "var(--text-primary)" }}>Contact</h2>
                <p className="text-sm leading-relaxed" style={{ color: "var(--text-secondary)" }}>
                  Questions or requests: {email ? <>email <a href={`mailto:${email}`} className="font-semibold underline">{email}</a> or </> : ""}use the <Link to="/Help#contact" className="font-semibold underline">Contact us</Link> form and our team will reply in the app.
                </p>
              </section>
            </div>
          </article>
        ) : (
          <article>
            <h1 className="font-display text-3xl mb-6 flex items-center gap-2" style={{ color: "var(--text-primary)" }}><HelpCircle className="w-7 h-7" /> Help & FAQ</h1>
            <div className="space-y-2">
              {FAQ.map(([q, a]) => (
                <details key={q} className="card-sm p-4 group">
                  <summary className="font-bold cursor-pointer list-none flex items-center justify-between gap-3" style={{ color: "var(--text-primary)" }}>{q}<span className="text-lg transition-transform group-open:rotate-45" aria-hidden="true">+</span></summary>
                  <p className="text-sm mt-2 leading-relaxed" style={{ color: "var(--text-secondary)" }}>{a}</p>
                </details>
              ))}
            </div>
            <ContactForm email={email} />
          </article>
        )}
      </div>
    </div>
  );
}
