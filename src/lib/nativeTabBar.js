// The native iOS tab bar (ios/App/App/NativeTabBar.swift): real Liquid Glass
// on iOS 26. In the browser (or if the plugin is missing) nothing happens and
// the web tab bar stays.
import { useEffect, useRef, useState } from "react";
import { Capacitor, registerPlugin } from "@capacitor/core";

const NativeTabBar = registerPlugin("NativeTabBar");
const native = () => Capacitor.isNativePlatform() && Capacitor.getPlatform() === "ios";

// True while a full-screen layer (sheet, viewer, camera…) or the keyboard is up.
function useCoveredScreen(enabled) {
  const [covered, setCovered] = useState(false);
  useEffect(() => {
    if (!enabled) return undefined;
    let frame = 0;
    const check = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => setCovered(!!document.querySelector('[aria-modal="true"]') || document.documentElement.classList.contains("keyboard-open")));
    };
    const mo = new MutationObserver(check);
    mo.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["aria-modal"] });
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });
    check();
    return () => { mo.disconnect(); cancelAnimationFrame(frame); };
  }, [enabled]);
  return covered;
}

// Returns true once the native bar is showing (then hide the web one).
export function useNativeTabBar({ items, selected, badges, dark, onSelect }) {
  const [on, setOn] = useState(false);
  const handler = useRef(onSelect);
  handler.current = onSelect;
  const covered = useCoveredScreen(on);
  const itemsKey = JSON.stringify(items);

  useEffect(() => {
    if (!native()) return undefined;
    let alive = true;
    let sub;
    NativeTabBar.show({ items, selected }).then(async () => {
      if (!alive) return;
      sub = await NativeTabBar.addListener("select", ({ id }) => handler.current?.(id));
      setOn(true);
      document.documentElement.classList.add("native-tabbar-on");
    }).catch(() => { /* plugin missing: keep the web tab bar */ });
    return () => {
      alive = false;
      sub?.remove();
      NativeTabBar.hide().catch(() => {});
      document.documentElement.classList.remove("native-tabbar-on");
    };
  }, [itemsKey]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { if (on) NativeTabBar.setSelected({ id: selected || "" }).catch(() => {}); }, [on, selected]);
  useEffect(() => { if (on) NativeTabBar.setBadges({ badges }).catch(() => {}); }, [on, JSON.stringify(badges)]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { if (on) NativeTabBar.setDark({ dark: !!dark }).catch(() => {}); }, [on, dark]);
  useEffect(() => {
    if (!on) return;
    (covered ? NativeTabBar.hide() : NativeTabBar.show({ items, selected })).catch(() => {});
  }, [on, covered]); // eslint-disable-line react-hooks/exhaustive-deps
  return on;
}
