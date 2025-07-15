import React from 'react';
import { useQuery } from '@tanstack/react-query';
import { apiService } from '../../services/apiService';
import { Card } from '../common/Card';
import { LoadingSpinner } from '../common/LoadingSpinner';
import { Wallet, TrendingUp, Shield, Activity } from 'lucide-react';

interface AssetOverviewProps {
  safeAddress: string;
}

export function AssetOverview({ safeAddress }: AssetOverviewProps) {
  const { data: assets, isLoading, error } = useQuery({
    queryKey: ['assets', safeAddress],
    queryFn: () => apiService.getSafeAssets(safeAddress),
    refetchInterval: 30000
  });

  const { data: safeInfo } = useQuery({
    queryKey: ['safeInfo', safeAddress],
    queryFn: () => apiService.getSafeInfo(safeAddress)
  });

  if (isLoading) return <LoadingSpinner />;
  if (error) return <div className="text-red-600">Error loading assets</div>;

  const totalValue = assets?.reduce((sum, asset) => sum + asset.value, 0) || 0;

  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <Card>
          <div className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Total Value</p>
                <p className="text-2xl font-bold">${totalValue.toLocaleString()}</p>
              </div>
              <Wallet className="w-8 h-8 text-blue-600" />
            </div>
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Assets</p>
                <p className="text-2xl font-bold">{assets?.length || 0}</p>
              </div>
              <TrendingUp className="w-8 h-8 text-green-600" />
            </div>
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Owners</p>
                <p className="text-2xl font-bold">{safeInfo?.owners.length || 0}</p>
              </div>
              <Shield className="w-8 h-8 text-purple-600" />
            </div>
          </div>
        </Card>

        <Card>
          <div className="p-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-600">Threshold</p>
                <p className="text-2xl font-bold">{safeInfo?.threshold || 0}</p>
              </div>
              <Activity className="w-8 h-8 text-orange-600" />
            </div>
          </div>
        </Card>
      </div>

      <Card>
        <div className="p-6">
          <h3 className="text-lg font-semibold mb-4">Assets</h3>
          <div className="space-y-3">
            {assets?.map((asset, index) => (
              <div key={index} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                <div className="flex items-center gap-3">
                  <img
                    src={asset.logo || '/placeholder-token.png'}
                    alt={asset.symbol}
                    className="w-8 h-8 rounded-full"
                  />
                  <div>
                    <p className="font-medium">{asset.symbol}</p>
                    <p className="text-sm text-gray-600">{asset.name}</p>
                  </div>
                </div>
                <div className="text-right">
                  <p className="font-medium">{asset.balance}</p>
                  <p className="text-sm text-gray-600">${asset.value.toLocaleString()}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </Card>
    </div>
  );
      }
      
