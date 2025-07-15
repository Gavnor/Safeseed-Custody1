import { useState, useEffect } from 'react';
import { ethers } from 'ethers';
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import { SafeApiKit } from '@safe-global/api-kit';
import { useAccount, useNetwork } from 'wagmi';

export function useSafeSDK() {
  const { address, isConnected } = useAccount();
  const { chain } = useNetwork();
  const [safeSdk, setSafeSdk] = useState<Safe | null>(null);
  const [apiKit, setApiKit] = useState<SafeApiKit | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!isConnected || !address || !chain) return;
    initializeSafeSDK();
  }, [isConnected, address, chain]);

  const initializeSafeSDK = async () => {
    try {
      setLoading(true);
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
      const safeApiKit = new SafeApiKit({
        txServiceUrl: getSafeServiceUrl(chain?.id || 1),
        chainId: chain?.id || 1
      });
      setApiKit(safeApiKit);
      setLoading(false);
    } catch (error) {
      console.error('Error initializing Safe SDK:', error);
      setLoading(false);
    }
  };

  const getSafeServiceUrl = (chainId: number): string => {
    switch (chainId) {
      case 1: return 'https://safe-transaction-mainnet.safe.global';
      case 137: return 'https://safe-transaction-polygon.safe.global';
      case 42161: return 'https://safe-transaction-arbitrum.safe.global';
      default: return 'https://safe-transaction-mainnet.safe.global';
    }
  };

  const createSafe = async (owners: string[], threshold: number) => {
    if (!safeSdk) throw new Error('Safe SDK not initialized');
    try {
      const safeAccountConfig = {
        owners,
        threshold,
        fallbackHandler: ethers.constants.AddressZero,
        paymentToken: ethers.constants.AddressZero,
        payment: 0,
        paymentReceiver: ethers.constants.AddressZero
      };
      const safeFactory = await Safe.create({ ethAdapter: safeSdk.getEthAdapter() });
      const deployedSafe = await safeFactory.deploySafe({ safeAccountConfig });
      return deployedSafe.getAddress();
    } catch (error) {
      console.error('Error creating Safe:', error);
      throw error;
    }
  };

  const connectToSafe = async (safeAddress: string) => {
    try {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      const signer = provider.getSigner();
      const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
      const connectedSafe = await Safe.create({ ethAdapter, safeAddress });
      setSafeSdk(connectedSafe);
      return connectedSafe;
    } catch (error) {
      console.error('Error connecting to Safe:', error);
      throw error;
    }
  };

  return { safeSdk, apiKit, loading, createSafe, connectToSafe, initializeSafeSDK };
    }
    
