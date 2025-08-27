import express from 'express';
import campaignRoutes from './campaignRoutes.js';
import creativeRoutes from './creativeRoutes.js';
import paymentRoutes from './paymentRoutes.js';
import analyticsRoutes from './analyticsRoutes.js';

const router = express.Router();

// Mount route modules
router.use('/campaigns', campaignRoutes);
router.use('/', creativeRoutes);
router.use('/', paymentRoutes);
router.use('/', analyticsRoutes);

export default router;
