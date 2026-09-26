import React from "react";
import { AlertTriangle, RotateCcw } from "lucide-react";

// Catches a crash inside one page so the rest of the app keeps working and
// the person gets a way out instead of a blank or frozen screen.
export default class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error("[page crash]", error, info?.componentStack);
  }

  componentDidUpdate(prev) {
    if (this.state.error && prev.resetKey !== this.props.resetKey) this.setState({ error: null });
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;
    // A page file that failed to download (e.g. after an update) needs a reload.
    const stale = /dynamically imported module|Importing a module script failed|Loading chunk/i.test(error?.message || "");
    return (
      <div className="flex flex-col items-center justify-center text-center py-20 px-6 gap-3">
        <div className="w-14 h-14 rounded-3xl flex items-center justify-center" style={{ background: "var(--pink-soft)", color: "var(--accent-rose)" }}>
          <AlertTriangle className="w-6 h-6" />
        </div>
        <h2 className="font-display text-xl font-semibold" style={{ color: "var(--text-primary)" }}>{stale ? "There's a new version" : "This page hit a snag"}</h2>
        <p className="text-sm max-w-sm" style={{ color: "var(--text-muted)" }}>{stale ? "Reload to get the latest version of the app." : "Something went wrong while showing this page. Try again, or reload the app."}</p>
        <div className="flex gap-2 mt-2">
          {!stale && <button className="btn-outline" onClick={() => this.setState({ error: null })}>Try again</button>}
          <button className="btn" onClick={() => window.location.reload()}><RotateCcw className="w-4 h-4" /> Reload</button>
        </div>
      </div>
    );
  }
}
