import { GoogleGenerativeAI } from "@google/generative-ai";
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Setup __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from backend root
dotenv.config({ path: path.join(__dirname, '../.env') });

async function listModels() {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        console.error("❌ GEMINI_API_KEY is missing in .env file");
        return;
    }

    console.log("🚀 Checking available Gemini models...");
    console.log(`🔑 Using API Key: ${apiKey.substring(0, 5)}...${apiKey.substring(apiKey.length - 4)}`);

    try {
        const genAI = new GoogleGenerativeAI(apiKey);
        
        // List models
        // Note: The SDK might not have a direct listModels on the genAI instance in some versions,
        // but we can try to fetch from the API directly or use the available methods.
        
        // In @google/generative-ai, we can use the ModelService but it's often easier to just 
        // try common model names or use fetch to the endpoint.
        
        const versions = ['v1', 'v1beta'];
        
        for (const version of versions) {
            console.log(`\n--- Checking Version: ${version} ---`);
            try {
                const response = await fetch(`https://generativelanguage.googleapis.com/${version}/models?key=${apiKey}`);
                const data = await response.json();
                
                if (data.models) {
                    console.log(`✅ Found ${data.models.length} models in ${version}:`);
                    data.models.forEach(model => {
                        console.log(`   - ${model.name} (Methods: ${model.supportedGenerationMethods.join(', ')})`);
                    });
                } else if (data.error) {
                    console.error(`❌ Error in ${version}: ${data.error.message}`);
                } else {
                    console.log(`ℹ️ No models returned for ${version}`);
                }
            } catch (err) {
                console.error(`❌ Fetch failed for ${version}:`, err.message);
            }
        }

    } catch (error) {
        console.error("❌ Critical Error:", error.message);
    }
}

listModels();
