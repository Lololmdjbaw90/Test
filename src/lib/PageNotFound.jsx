import { useLocation } from 'react-router-dom';
import { base44 } from '@/api/base44Client';
import { useQuery } from '@tanstack/react-query';
export default function PageNotFound() {
  const location = useLocation();
  const pageName = location.pathname.substring(1);
  const { data: authData, isFetched } = useQuery({ queryKey: ['user'], queryFn: async () => { try { const user = await base44.auth.me(); return { user, isAuthenticated: true }; } catch { return { user: null, isAuthenticated: false }; } } });
  return (
    <div className="min-h-screen flex items-center justify-center p-6 bg-slate-50">
      <div className="max-w-md w-full text-center space-y-6">
        <h1 className="text-7xl font-light text-slate-300">404</h1>
        <h2 className="text-2xl font-medium text-slate-800">Page Not Found</h2>
        <p className="text-slate-600">The page "{pageName}" could not be found.</p>
        {isFetched && authData?.isAuthenticated && authData?.user?.role === 'admin' && <div className="p-4 bg-slate-100 rounded-lg text-sm text-slate-600">Admin Note: This page may not be implemented yet.</div>}
        <button onClick={() => window.location.href = '/'} className="px-4 py-2 text-sm border rounded-lg hover:bg-slate-50">Go Home</button>
      </div>
    </div>
  );
}