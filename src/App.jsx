import React, { Suspense, lazy, useEffect } from "react";
import { QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter as Router, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { MotionConfig } from "framer-motion";
import { queryClientInstance } from "@/lib/query-client";
import { AuthProvider, useAuth } from "@/lib/AuthContext";
import { PlayerProvider } from "@/lib/player";
import { Toaster } from "@/lib/toast";
import { ConfirmProvider } from "@/components/common/Modal";
import { CenterSpinner } from "@/components/common/Page";
import Layout from "./Layout.jsx";
import Login from "./pages/Login";

// Pages are code-split so the first load stays small.
const Home = lazy(() => import("./pages/Home"));
const Gallery = lazy(() => import("./pages/Gallery"));
const Upload = lazy(() => import("./pages/Upload"));
const Logs = lazy(() => import("./pages/Logs"));
const Settings = lazy(() => import("./pages/Settings"));
const Community = lazy(() => import("./pages/Community"));
const Music = lazy(() => import("./pages/Music"));
const Profile = lazy(() => import("./pages/Profile"));
const Onboarding = lazy(() => import("./pages/Onboarding"));
const Communities = lazy(() => import("./pages/Communities"));
const CommunityChat = lazy(() => import("./pages/CommunityChat"));
const Friends = lazy(() => import("./pages/Friends"));
const Commissions = lazy(() => import("./pages/Commissions"));
const TopArtists = lazy(() => import("./pages/TopArtists"));
const DirectMessages = lazy(() => import("./pages/DirectMessages"));
const AdminPanel = lazy(() => import("./pages/AdminPanel"));
const PageNotFound = lazy(() => import("./lib/PageNotFound"));

function Splash() {
  return (
    <div className="fixed inset-0 flex flex-col items-center justify-center gap-4 app-shell">
      <div className="w-14 h-14 rounded-[18px] flex items-center justify-center text-white font-display italic text-2xl font-bold animate-pulse" style={{ background: "var(--accent-grad)", boxShadow: "var(--shadow-accent)" }}>M</div>
    </div>
  );
}

function RequireAuth({ children }) {
  const { isAuthenticated } = useAuth();
  const location = useLocation();
  if (!isAuthenticated) return <Navigate to={`/Login?next=${encodeURIComponent(location.pathname + location.search)}`} replace />;
  return children;
}

const AppRoutes = () => {
  const { authChecked, isAuthenticated } = useAuth();
  if (!authChecked) return <Splash />;
  return (
    <Suspense fallback={<Splash />}>
      <Routes>
        <Route path="/Login" element={isAuthenticated ? <Navigate to="/" replace /> : <Login />} />
        <Route path="/Onboarding" element={<RequireAuth><Onboarding /></RequireAuth>} />
        <Route element={<RequireAuth><Layout /></RequireAuth>}>
          <Route path="/" element={<Suspense fallback={<CenterSpinner />}><Home /></Suspense>} />
          <Route path="/Home" element={<Navigate to="/" replace />} />
          <Route path="/Gallery" element={<Suspense fallback={<CenterSpinner />}><Gallery /></Suspense>} />
          <Route path="/Upload" element={<Suspense fallback={<CenterSpinner />}><Upload /></Suspense>} />
          <Route path="/Logs" element={<Suspense fallback={<CenterSpinner />}><Logs /></Suspense>} />
          <Route path="/Settings" element={<Suspense fallback={<CenterSpinner />}><Settings /></Suspense>} />
          <Route path="/Community" element={<Suspense fallback={<CenterSpinner />}><Community /></Suspense>} />
          <Route path="/Music" element={<Suspense fallback={<CenterSpinner />}><Music /></Suspense>} />
          <Route path="/Profile" element={<Suspense fallback={<CenterSpinner />}><Profile /></Suspense>} />
          <Route path="/Communities" element={<Suspense fallback={<CenterSpinner />}><Communities /></Suspense>} />
          <Route path="/CommunityChat" element={<Suspense fallback={<CenterSpinner />}><CommunityChat /></Suspense>} />
          <Route path="/Friends" element={<Suspense fallback={<CenterSpinner />}><Friends /></Suspense>} />
          <Route path="/Commissions" element={<Suspense fallback={<CenterSpinner />}><Commissions /></Suspense>} />
          <Route path="/TopArtists" element={<Suspense fallback={<CenterSpinner />}><TopArtists /></Suspense>} />
          <Route path="/DirectMessages" element={<Suspense fallback={<CenterSpinner />}><DirectMessages /></Suspense>} />
          <Route path="/Admin" element={<Suspense fallback={<CenterSpinner />}><AdminPanel /></Suspense>} />
          <Route path="/AdminPanel" element={<Navigate to="/Admin" replace />} />
          <Route path="*" element={<Suspense fallback={<CenterSpinner />}><PageNotFound /></Suspense>} />
        </Route>
      </Routes>
    </Suspense>
  );
};

export default function App() {
  useEffect(() => {
    const el = document.getElementById("app-loading");
    if (!el) return;
    el.style.opacity = "0";
    const t = setTimeout(() => el.remove(), 450);
    return () => clearTimeout(t);
  }, []);

  return (
    <MotionConfig reducedMotion="user">
      <AuthProvider>
        <QueryClientProvider client={queryClientInstance}>
          <PlayerProvider>
            <ConfirmProvider>
              <Router>
                <AppRoutes />
              </Router>
              <Toaster />
            </ConfirmProvider>
          </PlayerProvider>
        </QueryClientProvider>
      </AuthProvider>
    </MotionConfig>
  );
}
