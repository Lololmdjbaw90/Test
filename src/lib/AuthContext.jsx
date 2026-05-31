import React, { createContext, useState, useContext, useEffect } from 'react';
import { base44 } from '@/api/base44Client';

const AuthContext = createContext();

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [isLoadingAuth, setIsLoadingAuth] = useState(true);
  const [isLoadingPublicSettings, setIsLoadingPublicSettings] = useState(true);
  const [authError, setAuthError] = useState(null);
  const [authChecked, setAuthChecked] = useState(false);
  const [appPublicSettings, setAppPublicSettings] = useState(null);

  useEffect(() => { checkAppState(); }, []);

  // Local/offline mode: there is no remote app, so there are no public settings
  // to fetch and no Base44 to authenticate against. We just load the local user.
  const checkAppState = async () => {
    setIsLoadingPublicSettings(true);
    setAuthError(null);
    setAppPublicSettings({ name: 'Mimi Locks', local: true });
    setIsLoadingPublicSettings(false);
    await checkUserAuth();
  };

  const checkUserAuth = async () => {
    try {
      setIsLoadingAuth(true);
      const currentUser = await base44.auth.me();
      setUser(currentUser);
      setIsAuthenticated(true);
      setAuthError(null);
    } catch (error) {
      setIsAuthenticated(false);
      setAuthError({ type: error?.message === 'auth_required' ? 'auth_required' : 'unknown', message: error && error.message });
    } finally {
      setIsLoadingAuth(false);
      setAuthChecked(true);
    }
  };

  const logout = () => { setUser(null); setIsAuthenticated(false); base44.auth.logout(); };
  const navigateToLogin = () => { base44.auth.redirectToLogin(); };

  return (
    <AuthContext.Provider value={{ user, isAuthenticated, isLoadingAuth, isLoadingPublicSettings, authError, appPublicSettings, authChecked, logout, navigateToLogin, checkUserAuth, checkAppState }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within an AuthProvider');
  return context;
};
