import { Toaster } from "@/components/ui/toaster";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClientInstance } from "@/lib/query-client";
import { BrowserRouter as Router, Route, Routes } from "react-router-dom";
import PageNotFound from "./lib/PageNotFound";
import { AuthProvider, useAuth } from "@/lib/AuthContext";
import UserNotRegisteredError from "@/components/UserNotRegisteredError";
import Gallery from "./pages/Gallery";
import Upload from "./pages/Upload";
import Logs from "./pages/Logs";
import Settings from "./pages/Settings";
import Community from "./pages/Community";
import Music from "./pages/Music";
import Profile from "./pages/Profile";
import Onboarding from "./pages/Onboarding";
import Communities from "./pages/Communities";
import CommunityChat from "./pages/CommunityChat";
import Friends from "./pages/Friends";
import Commissions from "./pages/Commissions";
import TopArtists from "./pages/TopArtists";
import DirectMessages from "./pages/DirectMessages";
import AdminPanel from "./pages/AdminPanel";
import Login from "./pages/Login";
import Layout from "./Layout.jsx";

const AuthenticatedApp = () => {
  const { isLoadingAuth, isLoadingPublicSettings, authError } = useAuth();
  if (isLoadingPublicSettings || isLoadingAuth) return (
    <div className="fixed inset-0 flex items-center justify-center">
      <div className="w-8 h-8 border-4 border-slate-200 border-t-slate-800 rounded-full animate-spin"></div>
    </div>
  );
  if (authError) {
    if (authError.type === "user_not_registered") return <UserNotRegisteredError />;
    else if (authError.type === "auth_required") return <Login />;
  }
  return (
    <Routes>
      <Route element={<Login />} path="/Login" />
      <Route element={<Layout><Onboarding /></Layout>} path="/Onboarding" />
      <Route element={<Layout><Gallery /></Layout>} path="/" />
      <Route element={<Layout><Gallery /></Layout>} path="/Gallery" />
      <Route element={<Layout><Upload /></Layout>} path="/Upload" />
      <Route element={<Layout><Logs /></Layout>} path="/Logs" />
      <Route element={<Layout><Settings /></Layout>} path="/Settings" />
      <Route element={<Layout><Community /></Layout>} path="/Community" />
      <Route element={<Layout><Music /></Layout>} path="/Music" />
      <Route element={<Layout><Profile /></Layout>} path="/Profile" />
      <Route element={<Layout><Communities /></Layout>} path="/Communities" />
      <Route element={<Layout><CommunityChat /></Layout>} path="/CommunityChat" />
      <Route element={<Layout><Friends /></Layout>} path="/Friends" />
      <Route element={<Layout><Commissions /></Layout>} path="/Commissions" />
      <Route element={<Layout><TopArtists /></Layout>} path="/TopArtists" />
      <Route element={<Layout><DirectMessages /></Layout>} path="/DirectMessages" />
      <Route element={<Layout><AdminPanel /></Layout>} path="/Admin" />
      <Route path="*" element={<PageNotFound />} />
    </Routes>
  );
};

export default function App() {
  return (
    <AuthProvider>
      <QueryClientProvider client={queryClientInstance}>
        <Router>
          <AuthenticatedApp />
        </Router>
        <Toaster />
      </QueryClientProvider>
    </AuthProvider>
  );
}