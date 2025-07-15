import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { createServer } from 'http';
import { Server } from 'socket.io';
import { setupDatabase } from './utils/database';
import { setupRedis } from './utils/redis';
import { logger } from './utils/logger';
import { authMiddleware } from './middleware/auth';
import { errorHandler } from './middleware/errorHandler';
import { config } from './config';

// Route imports
import safeRoutes from './routes/safes';
import transactionRoutes from './routes/transactions';
import userRoutes from './routes/users';
import authRoutes from './routes/auth';

const app = express();
const server = createServer(app);
const io = new Server(server, {
  cors: {
    origin: config.cors.origin,
    methods: ['GET', 'POST']
  }
});

// Security middleware
app.use(helmet());
app.use(cors({
  origin: config.cors.origin,
  credentials: true
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api/', limiter);

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'OK', timestamp: new Date().toISOString() });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/users', authMiddleware, userRoutes);
app.use('/api/safes', authMiddleware, safeRoutes);
app.use('/api/transactions', authMiddleware, transactionRoutes);

// Error handling
app.use(errorHandler);

// Socket.IO for real-time updates
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth.token;
    if (!token) {
      return next(new Error('Authentication error'));
    }
    // Verify JWT token and attach user to socket
    // Implementation depends on your auth service
    next();
  } catch (error) {
    next(new Error('Authentication error'));
  }
});

io.on('connection', (socket) => {
  logger.info(`User connected: ${socket.id}`);
  
  socket.on('join-safe', (safeAddress) => {
    socket.join(`safe-${safeAddress}`);
    logger.info(`User ${socket.id} joined safe ${safeAddress}`);
  });

  socket.on('disconnect', () => {
    logger.info(`User disconnected: ${socket.id}`);
  });
});

// Initialize database and start server
async function startServer() {
  try {
    await setupDatabase();
    await setupRedis();
    
    const PORT = config.port || 3001;
    server.listen(PORT, () => {
      logger.info(`Server running on port ${PORT}`);
      logger.info(`Environment: ${config.nodeEnv}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
}

startServer();

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM received, shutting down gracefully');
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
});
