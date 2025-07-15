// Main React App
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
import { Login
