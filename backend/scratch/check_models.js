import dotenv from 'dotenv';
import axios from 'axios';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

async function listModels() {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        console.error("❌ GEMINI_API_KEY missing in .env");
        return;
    }

    console.log(`🔍 Checking available models for key: ${apiKey.substring(0, 5)}...`);
    
    const versions = ['v1', 'v1beta'];
    
    for (const v of versions) {
        try {
            const url = `https://generativelanguage.googleapis.com/${v}/models?key=${apiKey}`;
            const response = await axios.get(url);
            console.log(`\n✅ --- Models available in ${v} ---`);
            const models = response.data.models || [];
            models.forEach(m => {
                if (m.name.includes('embed')) {
                    console.log(`📍 ${m.name} (Methods: ${m.supportedGenerationMethods.join(', ')})`);
                }
            });
        } catch (error) {
            console.error(`❌ Failed to list models for ${v}: ${error.response?.data?.error?.message || error.message}`);
        }
    }
}

listModels();
