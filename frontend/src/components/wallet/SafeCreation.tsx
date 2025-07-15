import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useAccount } from 'wagmi';
import { useSafeSDK } from '../../hooks/useSafeSDK';
import { apiService } from '../../services/apiService';
import { Button } from '../common/Button';
import { Input } from '../common/Input';
import { Card } from '../common/Card';
import { Plus, Trash2, Users, Shield } from 'lucide-react';

export function SafeCreation() {
  const navigate = useNavigate();
  const { address } = useAccount();
  const { createSafe } = useSafeSDK();
  const [owners, setOwners] = useState<string[]>([address || '']);
  const [threshold, setThreshold] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const addOwner = () => {
    setOwners([...owners, '']);
  };

  const removeOwner = (index: number) => {
    if (owners.length > 1) {
      setOwners(owners.filter((_, i) => i !== index));
      if (threshold > owners.length - 1) {
        setThreshold(owners.length - 1);
      }
    }
  };

  const updateOwner = (index: number, value: string) => {
    const newOwners = [...owners];
    newOwners[index] = value;
    setOwners(newOwners);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const validOwners = owners.filter(owner => owner.trim() !== '');
      if (validOwners.length < threshold) {
        throw new Error('Threshold cannot be greater than number of owners');
      }

      const response = await apiService.createSafe({
        owners: validOwners,
        threshold,
        chainId: 1
      });

      if (response.success) {
        navigate(`/safe/${response.safeAddress}`);
      } else {
        throw new Error(response.error || 'Failed to create Safe');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create Safe');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto p-6">
      <Card>
        <div className="p-6">
          <div className="flex items-center gap-3 mb-6">
            <Shield className="w-8 h-8 text-blue-600" />
            <h1 className="text-2xl font-bold">Create New Safe</h1>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            <div>
              <div className="flex items-center gap-2 mb-4">
                <Users className="w-5 h-5 text-gray-600" />
                <label className="text-lg font-medium">
                  Owners ({owners.length})
                </label>
              </div>

              <div className="space-y-3">
                {owners.map((owner, index) => (
                  <div key={index} className="flex gap-2">
                    <Input
                      value={owner}
                      onChange={(e) => updateOwner(index, e.target.value)}
                      placeholder="0x..."
                      className="flex-1"
                      required
                    />
                    {owners.length > 1 && (
                      <Button
                        type="button"
                        variant="outline"
                        onClick={() => removeOwner(index)}
                        className="px-3"
                      >
                        <Trash2 className="w-4 h-4" />
                      </Button>
                    )}
                  </div>
                ))}
              </div>

              <Button
                type="button"
                variant="outline"
                onClick={addOwner}
                className="mt-3 flex items-center gap-2"
              >
                <Plus className="w-4 h-4" />
                Add Owner
              </Button>
            </div>

            <div>
              <label className="block text-lg font-medium mb-2">
                Required Confirmations
              </label>
              <select
                value={threshold}
                onChange={(e) => setThreshold(Number(e.target.value))}
                className="w-full p-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                required
              >
                {Array.from({ length: owners.length }, (_, i) => i + 1).map((num) => (
                  <option key={num} value={num}>
                    {num} out of {owners.length} owners
                  </option>
                ))}
              </select>
              <p className="text-sm text-gray-600 mt-1">
                Any transaction will require confirmation from {threshold} out of {owners.length} owners
              </p>
            </div>

            {error && (
              <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
                <p className="text-red-700">{error}</p>
              </div>
            )}

            <div className="flex gap-4 pt-4">
              <Button
                type="button"
                variant="outline"
                onClick={() => navigate('/')}
                className="flex-1"
              >
                Cancel
              </Button>
              <Button
                type="submit"
                disabled={loading}
                className="flex-1"
              >
                {loading ? 'Creating Safe...' : 'Create Safe'}
              </Button>
            </div>
          </form>
        </div>
      </Card>
    </div>
  );
    }
