import React, { useState } from "react";
import { Link } from "react-router-dom";
import { motion } from "framer-motion";
import { ClipboardList, Download, Shield, Trash2, Upload, UserCog } from "lucide-react";
import { useAuth } from "@/lib/AuthContext";
import { useLiveQuery } from "@/lib/useLiveQuery";
import { timeAgo } from "@/lib/format";
import { exportToCsv } from "@/utils/exportCsv";
import { Page, PageHeader, EmptyState, CenterSpinner } from "@/components/common/Page";
import { SearchInput } from "@/components/common/Controls";

const ICONS = { artwork_added: Upload, artwork_deleted: Trash2, moderation_delete: Trash2, role_change: UserCog };

export default function LogsPage() {
  const { isAdmin } = useAuth();
  const [search, setSearch] = useState("");
  const { data: logs, loading } = useLiveQuery("Log", null, { sort: "-created_date", limit: 300, enabled: isAdmin });
  if (!isAdmin) return <Page><EmptyState icon={Shield} title="Admins only" action={<Link to="/" className="btn">Go home</Link>} /></Page>;
  const q = search.trim().toLowerCase();
  const filtered = logs.filter((l) => !q || [l.details, l.action, l.user_email].some((f) => String(f || "").toLowerCase().includes(q)));
  return (
    <Page width="max-w-3xl">
      <PageHeader eyebrow="Admin" title="Activity logs" subtitle={`${logs.length} admin actions recorded`} icon={ClipboardList} actions={<button className="icon-btn icon-btn-bordered" onClick={() => exportToCsv(filtered.map((l) => ({ date: l.created_date, action: l.action, details: l.details, by: l.user_email })), "logs")} aria-label="Export CSV"><Download className="w-4 h-4" /></button>}>
        <SearchInput value={search} onChange={setSearch} placeholder="Search logs…" className="max-w-sm" />
      </PageHeader>
      {loading ? <CenterSpinner /> : filtered.length === 0 ? <EmptyState icon={ClipboardList} title="No logs yet" text="Uploads, deletions and role changes are recorded here." /> : (
        <div className="relative pl-8">
          <div className="absolute left-[15px] top-2 bottom-2 w-px" style={{ background: "var(--border-strong)" }} />
          {filtered.map((l, i) => {
            const Icon = ICONS[l.action] || ClipboardList;
            return (
              <motion.div key={l.id} initial={{ opacity: 0, x: -10 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: Math.min(i, 15) * 0.03 }} className="relative mb-3">
                <span className="absolute -left-8 top-3 w-[30px] h-[30px] rounded-full flex items-center justify-center" style={{ background: "var(--surface)", border: "1px solid var(--border-c)", color: "var(--accent-rose)" }}><Icon className="w-3.5 h-3.5" /></span>
                <div className="card-sm p-3.5">
                  <p className="text-sm font-semibold" style={{ color: "var(--text-primary)" }}>{l.details}</p>
                  <p className="text-xs mt-0.5" style={{ color: "var(--text-muted)" }}>{l.action?.replace(/_/g, " ")} · {l.user_email} · {timeAgo(l.created_date)}</p>
                </div>
              </motion.div>
            );
          })}
        </div>
      )}
    </Page>
  );
}
