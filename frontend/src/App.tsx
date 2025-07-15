import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiConfig, createConfig, configureChains } from 'wagmi';
import { mainnet, polygon, arbitrum } from 'wagmi/chains';
import { publicProvider } from 'wagmi/providers/public';
import { infuraProvider } from 'wagmi/providers/infura';
import { MetaMaskConnector } from 'wagmi/connectors/metaMask';
import { WalletConnectConnector } from 'wagmi/connectors/walletConnect';
import { InjectedConnector } from 'wagmi/connectors/injected';

import { AuthProvider } from './context/AuthContext';
import { SafeProvider } from './context/SafeContext';
import { Layout } from './components/common/Layout';
import { Dashboard } from './pages/Dashboard';
import { SafeCreation } from './pages/SafeCreation';
import { SafeDetail } from './pages/SafeDetail';
import { TransactionProposal } from './pages/TransactionProposal';
import { Login } from './pages/Login';
import { ProtectedRoute } from './components/common/ProtectedRoute';

import './App.css';

const queryClient = new QueryClient();

const { chains, publicClient } = configureChains(
  [mainnet, polygon, arbitrum],
  [
    infuraProvider({ apiKey: process.env.REACT_APP_INFURA_PROJECT_ID! }),
    publicProvider()
  ]
);

const config = createConfig({
  autoConnect: true,
  connectors: [
    new MetaMaskConnector({ chains }),
    new WalletConnectConnector({
      chains,
      options: {
        projectId: process.env.REACT_APP_WALLETCONNECT_PROJECT_ID!,
      },
    }),
    new InjectedConnector({
      chains,
      options: {
        name: 'Injected',
        shimDisconnect: true,
      },
    }),
  ],
  publicClient,
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <WagmiConfig config={config}>
        <AuthProvider>
          <SafeProvider>
            <Router>
              <Layout>
                <Routes>
                  <Route path="/login" element={<Login />} />
                  <Route path="/" element={<ProtectedRoute><Dashboard /></ProtectedRoute>} />
                  <Route path="/safe/create" element={<ProtectedRoute><SafeCreation /></ProtectedRoute>} />
                  <Route path="/safe/:safeAddress" element={<ProtectedRoute><SafeDetail /></ProtectedRoute>} />
                  <Route path="/safe/:safeAddress/transaction/new" element={<ProtectedRoute><TransactionProposal /></ProtectedRoute>} />
                </Routes>
              </Layout>
            </Router>
          </SafeProvider>
        </AuthProvider>
      </WagmiConfig>
    </QueryClientProvider>
  );
}

export default App;
