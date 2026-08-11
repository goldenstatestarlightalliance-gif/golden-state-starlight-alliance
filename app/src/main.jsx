import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route } from 'react-router-dom';

import App from './App.jsx';
import Home from './pages/Home.jsx';
import StateMap from './pages/StateMap.jsx';
import Contact from './pages/Contact.jsx';
import CountyPage from './pages/CountyPage.jsx';
import CityPage from './pages/CityPage.jsx';
import Guide from './pages/Guide.jsx';
import ModelOrdinance from './pages/ModelOrdinance.jsx';
import SignIn from './pages/SignIn.jsx';
import Account from './pages/Account.jsx';
import NotFound from './pages/NotFound.jsx';
import RequireAuth from './components/RequireAuth.jsx';
import { AuthProvider } from './lib/auth.jsx';
import './index.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route element={<App />}>
            <Route index element={<Home />} />
            <Route path="map" element={<StateMap />} />
            <Route path="contact" element={<Contact />} />
            {/* County pages hang off the map rather than the top nav — there
                are 58 of them, so they are reached by selecting a county. */}
            <Route path="county/:slug" element={<CountyPage />} />
            {/* City slugs are unique only within a county, so the county slug
                is part of the path rather than decoration. */}
            <Route path="county/:countySlug/:citySlug" element={<CityPage />} />
            <Route path="guide" element={<Guide />} />
            <Route path="model-ordinance" element={<ModelOrdinance />} />
            <Route path="signin" element={<SignIn />} />
            <Route
              path="account"
              element={
                <RequireAuth>
                  <Account />
                </RequireAuth>
              }
            />
            <Route path="*" element={<NotFound />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  </StrictMode>
);
