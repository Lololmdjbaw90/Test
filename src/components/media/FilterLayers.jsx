import React from "react";
import { filterLayers } from "@/lib/filters";

// Tint / vignette of a filter, layered over a photo or video preview.
export default function FilterLayers({ filter, className = "" }) {
  const layers = filterLayers(filter);
  if (!layers.length) return null;
  return layers.map((style, i) => <span key={i} aria-hidden="true" className={`absolute inset-0 pointer-events-none ${className}`} style={style} />);
}
