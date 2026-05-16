import { GoogleGenerativeAI } from "@google/generative-ai";
import axios from 'axios';

/**
 * Gemini Service
 * Handles Multimodal Video Analysis and Semantic Embeddings using Google Gemini API.
 */
class GeminiService {
    constructor() {
        this.apiKey = process.env.GEMINI_API_KEY;
        this.genAI = this.apiKey ? new GoogleGenerativeAI(this.apiKey) : null;
    }

    /**
     * Generates a detailed description of the video content.
     * Uses Gemini 1.5 Flash multimodal analysis on the thumbnail + metadata.
     * @param {string} thumbnailUrl - URL of the video thumbnail
     * @param {Object} videoMetadata - Optional title/desc of the video
     * @returns {Promise<Object>} - AI generated metadata
     */
    async getVideoContext(thumbnailUrl, videoMetadata = {}) {
        if (!this.apiKey) throw new Error("GEMINI_API_KEY is missing.");

        try {
            console.log(`🎬 [Gemini] Analyzing thumbnail: ${thumbnailUrl}`);
            
            // For analysis, we'll use the SDK as it handles multimodal better than raw axios for images
            const model = this.genAI.getGenerativeModel({ model: "gemini-1.5-flash" }, { apiVersion: 'v1' });

            // Download thumbnail image to pass as part
            const imageResponse = await axios.get(thumbnailUrl, { responseType: 'arraybuffer' });
            const imagePart = {
                inlineData: {
                    data: Buffer.from(imageResponse.data).toString("base64"),
                    mimeType: "image/jpeg"
                }
            };

            const prompt = `
                Analyze this video thumbnail and metadata to provide structured findings in JSON.
                
                Video Info:
                - Title: ${videoMetadata.title || 'Unknown'}
                - Category: ${videoMetadata.category || 'General'}
                - Description: ${videoMetadata.description || 'None'}

                Return strictly valid JSON:
                1. "summary": Detailed summary in Hinglish (mix of Hindi/English).
                2. "oneLineAbout": Short description.
                3. "language": Primary language (Hindi, English, Hinglish, etc.).
                4. "region": Region (North India, South India, Global, etc.).
                5. "keywords": Array of 5-8 relevant tags.
                6. "activity": What is happening in the video?
                
                Ensure high quality for an Indian social media platform.
            `;

            const result = await model.generateContent([prompt, imagePart]);
            const response = await result.response;
            const responseText = response.text();
            
            const jsonMatch = responseText.match(/\{[\s\S]*\}/);
            if (!jsonMatch) throw new Error("Could not parse JSON from Gemini response");
            
            const metadata = JSON.parse(jsonMatch[0]);
            console.log(`✅ [Gemini] Metadata extracted for: ${videoMetadata.title || 'Video'}`);
            return metadata;
        } catch (error) {
            console.error(`❌ [Gemini] Analysis failed:`, error.message);
            return null; 
        }
    }

    /**
     * Generates semantic embeddings for a given text.
     * Uses text-embedding-004 which is optimized for Hinglish/Multilingual.
     * @param {string} text - The text to embed (Title + Desc + Tags)
     * @returns {Promise<number[]>} - 768-dimensional vector
     */
    async getEmbedding(text) {
        if (!this.apiKey) throw new Error("GEMINI_API_KEY is missing.");

        const attempts = [
            { 
                url: `https://generativelanguage.googleapis.com/v1/models/gemini-embedding-2:embedContent?key=${this.apiKey}`,
                model: "gemini-embedding-2"
            },
            { 
                url: `https://generativelanguage.googleapis.com/v1/models/gemini-embedding-001:embedContent?key=${this.apiKey}`,
                model: "gemini-embedding-001"
            }
        ];

        for (const attempt of attempts) {
            try {
                const response = await axios.post(attempt.url, {
                    content: { parts: [{ text }] }
                });

                if (response.data && response.data.embedding) {
                    return response.data.embedding.values;
                }
            } catch (error) {
                const errMsg = error.response?.data?.error?.message || error.message;
                
                if (errMsg.includes('Resource exhausted') || error.response?.status === 429) {
                    console.warn(`⏳ [Gemini] Rate limit hit. Sleeping for 2s...`);
                    await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2s
                    // Recursive retry once after sleep
                    return this.getEmbedding(text); 
                }

                console.warn(`⚠️ [Gemini REST] Attempt with ${attempt.model} failed: ${errMsg}`);
                
                if (errMsg.includes('API key') || errMsg.includes('expired')) {
                    throw new Error(`Critical Auth Error: ${errMsg}`);
                }
            }
        }

        console.error(`❌ [Gemini REST] All attempts failed.`);
        return null;
    }
}

export default new GeminiService();
