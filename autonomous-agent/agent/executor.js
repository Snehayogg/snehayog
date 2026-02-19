const ollama = require('ollama').default;
const contextBuilder = require('./contextBuilder');
const planner = require('./planner');
const reflection = require('./reflection');
const memoryManager = require('./memoryManager');
const trendTool = require('../tools/trendTool');

/**
 * Executor Module
 * Orchestrates the agent workflow: Understand -> Think -> Plan -> Execute -> Reflect
 */

// Matches the requested signature: async function runAgent(userInput, userProfile)
async function executeTask(userProfile, intent, videoTitles) {
    console.log('🏁 Agent Workflow Started');

    // 0. SMART PRE-PROCESSING (Trends & Planning)
    // Infers niche roughly from intent or titles to check trends
    let niche = "general";
    if (intent.toLowerCase().includes("tech")) niche = "tech";
    else if (videoTitles && videoTitles.length > 0) niche = videoTitles.join(" "); // simplistic inference
    
    // A. TREND AWARENESS
    const trends = await trendTool.analyzeTrends(niche);

    // B. SMART PLANNING (Refine the user's prompt)
    const refinedIntent = await planner.refineIntent(intent, trends);
    
    // 1. GET MEMORY
    console.log('🧠 Agent: Retrieving Memory...');
    const memory = await memoryManager.getMemory(userProfile);

    // 2. BUILD CONTEXT (Profile + REFINED Intent + Memory + Video Titles)
    console.log('🏗️ Agent: Building Context...');
    // We pass the REFINED intent to the Context Builder now
    const fullContext = contextBuilder.constructContext(userProfile, refinedIntent, memory, videoTitles);
    
    // 4. EXECUTE (Generate Content via Ollama)
    console.log('⚙️ Agent: Executing Plan with Ollama (gemma:2b)...');

    try {
        console.log('🤖 Connecting to Ollama (gemma:2b)...');
        const response = await ollama.chat({
            model: 'gemma:2b',
            messages: [
                { role: 'system', content: fullContext },
                { role: 'user', content: `Generate content for intent: "${refinedIntent}". Return ONLY valid JSON with keys: type, title, caption, hashtags, imagePrompt.` }
            ],
            format: 'json',
            stream: false
        });

        console.log('🤖 Ollama Draft Generated');
        
        let contentData;
        try {
            contentData = JSON.parse(response.message.content);
        } catch (parseError) {
            console.warn('⚠️ JSON Parse Failed, attempting fallback cleanup...');
            const cleanJson = response.message.content.replace(/```json/g, '').replace(/```/g, '').trim();
            contentData = JSON.parse(cleanJson);
        }

        const draftResult = {
            type: contentData.type || "text",
            title: contentData.title || "Generated Content",
            caption: contentData.caption || response.message.content,
            hashtags: contentData.hashtags || [],
            imagePrompt: contentData.imagePrompt || ""
        };

        // 5. SELF-REFLECTION (Critique & Improve)
        const improvedResult = await reflection.reflectAndImprove(draftResult);
        
        console.log('💾 Agent: Saving Process to Memory...');
        await memoryManager.addMemory(userProfile, intent, improvedResult); // Save original intent for history

        return {
            status: "success",
            data: improvedResult
        };

    } catch (error) {
        console.warn('⚠️ Agent: Ollama connection failed. Falling back to Mock Simulation.');
        console.error('❌ Error Details:', error.message);

        // FALLBACK MOCK LOGIC
        let mockContent = "";
        let mockTitle = "";
        
        if (intent.toLowerCase().includes("gym") || intent.toLowerCase().includes("fitness")) {
            mockTitle = "💪 Crush Your Goals Today! (Simulation)";
            mockContent = "Consistency is the key to progress. Don't look at how far you have to go, look at how far you've come. Keep pushing! 🔥\n\n(Note: Install Ollama for AI generation)";
        } else if (intent.toLowerCase().includes("tech") || intent.toLowerCase().includes("coding")) {
            mockTitle = "💻 The Future of Coding (Simulation)";
            mockContent = "AI isn't replacing developers, it's empowering them. \n\n(Note: Install Ollama for AI generation) 🚀";
        } else {
            mockTitle = "✨ Creativity Unleashed (Simulation)";
            mockContent = "Your unique perspective is your superpower. \n\n(Note: Install Ollama for AI generation) 🌍";
        }

        const fallbackResult = {
            type: "text",
            title: mockTitle,
            caption: mockContent,
            hashtags: "#simulation #fallback",
            imagePrompt: "Simulation placeholder image"
        };
        
        await memoryManager.addMemory(userProfile, intent, fallbackResult);

        return {
            status: "success", // Success because we handled the failure gracefully
            data: fallbackResult,
            source: "fallback_mock"
        };
    }
}

module.exports = {
    executeTask
};
