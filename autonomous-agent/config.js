require('dotenv').config();

module.exports = {
    PORT: process.env.PORT || 3000,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY, // Or whichever LLM provider you use
    AGENT_MODE: process.env.AGENT_MODE || 'hybrid', // 'local' or 'cloud'
    // Add other config variables here
};
