import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter, Routes, Route } from 'react-router-dom';

import App from './App.jsx';
import StateMap from './pages/StateMap.jsx';
import CountyPage from './pages/CountyPage.jsx';
import './index.css';

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <Routes>
        <Route element={<App />}>
          <Route index element={<StateMap />} />
          <Route path="county/:slug" element={<CountyPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  </StrictMode>
);
