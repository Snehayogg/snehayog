const express = require('express');
const authController = require('../controllers/authController');

const router = express.Router();

router.post('/google', authController.googleSignIn);

module.exports = router;
