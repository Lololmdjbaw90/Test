import React, { createContext, useState, useContext, useEffect, useCallback, useRef } from "react";
import { base44 } from "@/api/base44Client";
import { applyTheme } from "@/lib/theme";

const AuthContext = createContext();

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoadingAuth, setIsLoadingAuth] = useState(true);
  const [authError, setAuthError] = useState(null);
  const [authChecked, setAuthChecked] = useState(false);

  const checkUserAuth = useCallback(async () => {
    try {
      setIsLoadingAuth(true);
      const currentUser = await base44.auth.me();
      setUser(currentUser);
      setIsAuthenticated(true);
      setAuthError(null);
      applyTheme({ theme: currentUser.theme, accent: currentUser.accent });
      return currentUser;
    } catch (error) {
      setUser(null);
      setIsAuthenticated(false);
      setAuthError({ type: error?.message === "auth_required" ? "auth_required" : "unknown", message: error?.message });
      return null;
    } finally {
      setIsLoadingAuth(false);
      setAuthChecked(true);
    }
  }, []);

  useEffect(() => { checkUserAuth(); }, [checkUserAuth]);

  // Keep last_seen fresh so friends see who is online.
  useEffect(() => {
    if (!isAuthenticated) return;
    const ping = () => base44.auth.updateMe({ last_seen: new Date().toISOString() }).catch(() => {});
    ping();
    const interval = setInterval(ping, 2 * 60 * 1000);
    return () => clearInterval(interval);
  }, [isAuthenticated]);

  // Update the profile. The app shows the change at once (save, follow,
  // theme…) and writes it in the background; if the write fails the change
  // is undone and the error is thrown as before. Quick repeated changes to
  // the same field never get overwritten by an older, slower write.
  const userRef = useRef(user);
  userRef.current = user;
  const pending = useRef({}); // field -> { value, seq } of the newest unsaved write
  const seq = useRef(0);
  const updateMe = useCallback(async (data) => {
    const mine = ++seq.current;
    const before = userRef.current;
    Object.keys(data).forEach((k) => { pending.current[k] = { value: data[k], seq: mine }; });
    setUser((prev) => ({ ...(prev || {}), ...data }));
    if ("theme" in data || "accent" in data) applyTheme({ theme: data.theme, accent: data.accent });
    const settle = () => {
      const owned = Object.keys(data).filter((k) => pending.current[k]?.seq === mine);
      owned.forEach((k) => { delete pending.current[k]; });
      const newer = Object.fromEntries(Object.entries(pending.current).map(([k, p]) => [k, p.value]));
      return { owned, newer };
    };
    try {
      const updated = await base44.auth.updateMe(data);
      const { newer } = settle();
      if (updated) setUser((prev) => ({ ...(prev || {}), ...updated, ...newer }));
      return updated;
    } catch (e) {
      const { owned } = settle();
      if (owned.length) setUser((prev) => ({ ...(prev || {}), ...Object.fromEntries(owned.map((k) => [k, before?.[k]])) }));
      throw e;
    }
  }, []);

  const logout = () => { setUser(null); setIsAuthenticated(false); base44.auth.logout(); };
  const navigateToLogin = () => { base44.auth.redirectToLogin(); };

  return (
    <AuthContext.Provider value={{
      user, setUser, isAuthenticated, isLoadingAuth, authError, authChecked,
      isAdmin: user?.role === "admin", logout, navigateToLogin, checkUserAuth, refreshUser: checkUserAuth, updateMe,
      // kept for compatibility with older components
      isLoadingPublicSettings: false, appPublicSettings: { name: "Sugerly" },
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used within an AuthProvider");
  return context;
};
