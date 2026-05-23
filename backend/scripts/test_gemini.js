import { GoogleGenerativeAI } from "@google/generative-ai";
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.join(__dirname, '../.env') });

async function testGemini() {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) return console.error("❌ No API Key");

    const genAI = new GoogleGenerativeAI(apiKey);
    
    // Testing the models that appeared in your successful 'v1' list
    const modelsToTry = [
        "gemini-2.5-flash", 
        "gemini-3.1-flash-lite", 
        "gemini-flash-lite-latest",
        "gemini-2.0-flash-lite"
    ];

    for (const modelName of modelsToTry) {
        try {
            console.log(`\n🎬 Testing model: ${modelName}...`);
            const model = genAI.getGenerativeModel({ model: modelName });
            const result = await model.generateContent("Say hello.");
            console.log(`✅ Success with ${modelName}!`);
            console.log("Response:", result.response.text());
            
            console.log(`\n💡 RECOMMENDATION: Update geminiService.js to use "${modelName}"`);
            return;
        } catch (error) {
            console.error(`❌ ${modelName} failed:`, error.message);
        }
    }
    
    console.log("\n❌ All models failed. Your API key might have reached its DAILY limit of 20-50 requests.");
}

testGemini();
