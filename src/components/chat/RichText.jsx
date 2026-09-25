import React from "react";

const TOKEN = /(https?:\/\/[^\s<]+[^\s<.,:;"')\]!?])|(@[\w.-]+)/g;

// Renders user text safely (no HTML injection) with clickable links and
// highlighted @mentions.
export default function RichText({ text, className = "" }) {
  if (!text) return null;
  const parts = [];
  let last = 0;
  let match;
  TOKEN.lastIndex = 0;
  while ((match = TOKEN.exec(text))) {
    if (match.index > last) parts.push(text.slice(last, match.index));
    if (match[1]) {
      parts.push(<a key={match.index} href={match[1]} target="_blank" rel="noopener noreferrer" className="underline underline-offset-2 break-all" style={{ color: "inherit" }}>{match[1]}</a>);
    } else {
      parts.push(<span key={match.index} className="mention">{match[2]}</span>);
    }
    last = match.index + match[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return <span className={`whitespace-pre-wrap break-words ${className}`}>{parts}</span>;
}

export function mentionedNames(text) {
  return [...String(text || "").matchAll(/@([\w.-]+)/g)].map((m) => m[1].toLowerCase());
}
