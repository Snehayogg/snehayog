import express from 'express';
import campaignRoutes from './campaignRoutes.js';
import creativeRoutes from './creativeRoutes.js';
import paymentRoutes from './paymentRoutes.js';
import analyticsRoutes from './analyticsRoutes.js';
import userRoutes from './userRoutes.js';
import realtimeRoutes from './realtimeRoutes.js';

const router = express.Router();

// Mount route modules
router.use('/campaigns', campaignRoutes);
router.use('/', creativeRoutes);
router.use('/', paymentRoutes);
router.use('/', analyticsRoutes);
router.use('/', userRoutes);
router.use('/', realtimeRoutes); // provides /ws SSE endpoint

export default router;
