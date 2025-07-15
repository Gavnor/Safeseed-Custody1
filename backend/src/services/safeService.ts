import { ethers } from 'ethers';
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import { SafeApiKit } from '@safe-global/api-kit';
import { SafeTransactionDataPartial } from '@safe-global/safe-core-sdk-types';
import { config } from '../config';
import { logger } from '../utils/logger';
import { SafeModel } from '../models/Safe';
import { TransactionModel } from '../models/Transaction';

export class SafeService {
  private provider = new ethers.providers.JsonRpcProvider(config.rpcUrl);
  private apiKit = new SafeApiKit({
    txServiceUrl: config.safeServiceUrl,
    chainId: config.chainId
  });

  async createSafe(owners: string[], threshold: number, userAddress: string): Promise<string> {
    try {
      const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, this.provider);
      const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
      const safeFactory = await Safe.create({ ethAdapter });

      const safeAccountConfig = {
        owners,
        threshold,
        fallbackHandler: ethers.constants.AddressZero,
        paymentToken: ethers.constants.AddressZero,
        payment: 0,
        paymentReceiver: ethers.constants.AddressZero
      };

      const safeSdk = await safeFactory.deploySafe({ safeAccountConfig });
      const safeAddress = safeSdk.getAddress();

      await SafeModel.create({
        address: safeAddress,
        owners,
        threshold,
        chainId: config.chainId,
        createdBy: userAddress,
        createdAt: new Date()
      });

      logger.info(`Safe created: ${safeAddress}`);
      return safeAddress;
    } catch (error) {
      logger.error('Error creating safe:', error);
      throw error;
    }
  }

  async proposeTransaction(safeAddress: string, to: string, value: string, data: string, proposedBy: string): Promise<string> {
    try {
      const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, this.provider);
      const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });

      const safeSdk = await Safe.create({ ethAdapter, safeAddress });

      const safeTransactionData: SafeTransactionDataPartial = {
        to,
        value,
        data,
        operation: 0,
        safeTxGas: 0,
        baseGas: 0,
        gasPrice: 0,
        gasToken: ethers.constants.AddressZero,
        refundReceiver: ethers.constants.AddressZero,
        nonce: await safeSdk.getNonce()
      };

      const safeTransaction = await safeSdk.createTransaction({ safeTransactionData });
      const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);

      await TransactionModel.create({
        safeAddress,
        safeTxHash,
        to,
        value,
        data,
        proposedBy,
        status: 'pending',
        confirmations: [],
        createdAt: new Date()
      });

      logger.info(`Transaction proposed: ${safeTxHash}`);
      return safeTxHash;
    } catch (error) {
      logger.error('Error proposing transaction:', error);
      throw error;
    }
  }

  async confirmTransaction(safeTxHash: string, signature: string, signerAddress: string): Promise<void> {
    const transaction = await TransactionModel.findOne({ safeTxHash });
    if (!transaction) throw new Error('Transaction not found');

    transaction.confirmations.push({ signer: signerAddress, signature, timestamp: new Date() });

    const safe = await SafeModel.findOne({ address: transaction.safeAddress });
    if (!safe) throw new Error('Safe not found');

    if (transaction.confirmations.length >= safe.threshold) {
      transaction.status = 'ready';
    }

    await transaction.save();
    logger.info(`Transaction confirmed by ${signerAddress}: ${safeTxHash}`);
  }

  async executeTransaction(safeTxHash: string): Promise<string> {
    const transaction = await TransactionModel.findOne({ safeTxHash });
    if (!transaction || transaction.status !== 'ready') {
      throw new Error('Transaction not found or not ready');
    }

    const signer = new ethers.Wallet(process.env.PRIVATE_KEY!, this.provider);
    const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
    const safeSdk = await Safe.create({ ethAdapter, safeAddress: transaction.safeAddress });

    const safeTransactionData: SafeTransactionDataPartial = {
      to: transaction.to,
      value: transaction.value,
      data: transaction.data,
      operation: 0
    };

    const safeTransaction = await safeSdk.createTransaction({ safeTransactionData });

    for (const { signature } of transaction.confirmations) {
      safeTransaction.addSignature(signature);
    }

    const txResponse = await safeSdk.executeTransaction(safeTransaction);
    const txHash = txResponse.hash;

    transaction.status = 'executed';
    transaction.executedAt = new Date();
    transaction.transactionHash = txHash;
    await transaction.save();

    logger.info(`Transaction executed: ${txHash}`);
    return txHash;
  }

  async getSafeInfo(safeAddress: string) {
    try {
      return await this.apiKit.getSafeInfo(safeAddress);
    } catch (error) {
      logger.error('Error getting safe info:', error);
      throw error;
    }
  }

  async getTransactionHistory(safeAddress: string) {
    try {
      return await this.apiKit.getMultisigTransactions(safeAddress);
    } catch (error) {
      logger.error('Error getting transaction history:', error);
      throw error;
    }
  }
        }
