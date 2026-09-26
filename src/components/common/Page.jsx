import React from "react";
import { Loader2 } from "lucide-react";

// Standard page container + header used by every content page.
export function Page({ children, className = "", width = "max-w-6xl" }) {
  return <div className={`${width} mx-auto w-full px-4 sm:px-6 lg:px-8 pt-5 sm:pt-8 pb-28 md:pb-12 ${className}`}>{children}</div>;
}

export function PageHeader({ eyebrow, title, subtitle, icon: Icon, actions, children }) {
  const d = (ms) => ({ "--d": `${ms}ms` });
  return (
    <header className="mb-6 sm:mb-8">
      <div className="flex flex-wrap items-end gap-4">
        <div className="flex items-center gap-3.5 flex-1 min-w-[220px]">
          {Icon && (
            <div className="enter w-12 h-12 rounded-2xl flex items-center justify-center flex-shrink-0 text-white" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}>
              <Icon className="w-5 h-5" />
            </div>
          )}
          <div className="min-w-0">
            {eyebrow && <p className="enter eyebrow mb-1" style={d(40)}>{eyebrow}</p>}
            <h1 className="enter font-display text-3xl sm:text-4xl font-semibold leading-tight" style={{ ...d(80), color: "var(--text-primary)" }}>{title}</h1>
            {subtitle && <p className="enter text-sm mt-1" style={{ ...d(120), color: "var(--text-muted)" }}>{subtitle}</p>}
          </div>
        </div>
        {actions && <div className="enter flex items-center gap-2 flex-wrap" style={d(120)}>{actions}</div>}
      </div>
      {children && <div className="enter mt-5" style={d(160)}>{children}</div>}
    </header>
  );
}

export function EmptyState({ icon: Icon, title, text, action, className = "" }) {
  return (
    <div className={`enter flex flex-col items-center justify-center text-center py-16 px-6 gap-3 ${className}`}>
      {Icon && (
        <div className="anim-bob w-16 h-16 rounded-3xl flex items-center justify-center mb-1" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>
          <Icon className="w-7 h-7" />
        </div>
      )}
      <p className="font-display text-lg font-semibold" style={{ color: "var(--text-primary)" }}>{title}</p>
      {text && <p className="text-sm max-w-sm" style={{ color: "var(--text-muted)" }}>{text}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

export function Spinner({ className = "w-5 h-5" }) {
  return <Loader2 className={`${className} animate-spin`} style={{ color: "var(--accent-rose)" }} />;
}

export function CenterSpinner() {
  return <div className="flex items-center justify-center py-24"><Spinner className="w-6 h-6" /></div>;
}
