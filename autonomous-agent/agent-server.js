const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const config = require('./config');
const executor = require('./agent/executor');

const app = express();

// Middleware
app.use(cors());
app.use(bodyParser.json());

// Routes
app.get('/', (req, res) => {
    res.send('Autonomous Agent Backend is running!');
});

// Generate Content Endpoint
app.post('/agent/generate', async (req, res) => {
    try {
        const { userProfile, intent, videoTitles } = req.body;

        if (!userProfile || !intent) {
            return res.status(400).json({ error: 'Missing userProfile or intent' });
        }

        console.log(`🤖 Application Request: Generative Task for ${userProfile.name || 'Unknown User'}`);
        console.log(`📝 Intent: ${intent}`);
        if (videoTitles && videoTitles.length > 0) {
            console.log(`📹 Context: ${videoTitles.length} recent video titles received`);
        }

        const result = await executor.executeTask(userProfile, intent, videoTitles);

        res.json(result);
    } catch (error) {
        console.error('❌ Agent Error:', error);
        res.status(500).json({ error: 'Internal Agent Error', details: error.message });
    }
});

// Start Server
app.listen(config.PORT, () => {
    console.log(`🚀 Autonomous Agent Server running on http://localhost:${config.PORT}`);
});
