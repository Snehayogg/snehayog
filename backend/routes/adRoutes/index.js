import express from 'express';
import campaignRoutes from './campaignRoutes.js';
import creativeRoutes from './creativeRoutes.js';
import paymentRoutes from './paymentRoutes.js';
import analyticsRoutes from './analyticsRoutes.js';
import userRoutes from './userRoutes.js';
import validationRoutes from './validationRoutes.js';
import impressionRoutes from './impressionRoutes.js';
import adTargetingRoutes from '../adTargetingRoutes.js';

const router = express.Router();

// Mount route modules
router.use('/campaigns', campaignRoutes);
router.use('/', creativeRoutes);
router.use('/', paymentRoutes);
router.use('/', analyticsRoutes);
router.use('/', userRoutes);
router.use('/', validationRoutes);
router.use('/', impressionRoutes);
router.use('/targeting', adTargetingRoutes);

export default router;
