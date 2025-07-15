// Mongoose schema for Safe
import { Schema, model, Document } from 'mongoose';

export interface ISafe extends Document {
  address: string;
  owners: string[];
  threshold: number;
  chainId: number;
  createdBy: string;
  createdAt: Date;
  updatedAt: Date;
}

const safeSchema = new Schema<ISafe>({
  address: { type: String, required: true, unique: true, index: true },
  owners: [{ type: String, required: true }],
  threshold: { type: Number, required: true, min: 1 },
  chainId: { type: Number, required: true },
  createdBy: { type: String, required: true },
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now }
});

safeSchema.pre('save', function (next) {
  this.updatedAt = new Date();
  next();
});

export const SafeModel = model<ISafe>('Safe', safeSchema);
