const ollama = require('ollama').default;

// Get the configured model (gemma:2b for now, flexible for llama3)
const MODEL = 'gemma:2b'; 

async function refineIntent(userIntent, trends) {
    console.log('🧠 Planner: Refining User Intent...');

    if (!userIntent || userIntent.length < 5) return userIntent; // Too short to refine

    const trendContext = trends.length > 0 ? `Active Trends: ${trends.join(', ')}` : "No specific trends.";
    
    const refinementPrompt = `
    Task: You are an expert Content Strategist. 
    User Request: "${userIntent}"
    ${trendContext}
    
    Action: 
    1. Analyze the user's request.
    2. If the request is simple (e.g., "post about food"), REWRITE it into a detailed, high-performing prompt.
    3. Incorporate ONE relevant trend if it fits naturally.
    4. Add details about Tone, Hook, and Value Proposition.
    5. Return ONLY the Rewritten Prompt text. Do not add explanations.
    `;

    try {
        const response = await ollama.chat({
            model: MODEL,
            messages: [{ role: 'user', content: refinementPrompt }],
            stream: false
        });

        const refinedPrompt = response.message.content.trim();
        console.log(`✨ Planner: Refined Prompt: "${refinedPrompt}"`);
        return refinedPrompt;

    } catch (error) {
        console.warn('⚠️ Planner: Refinement failed, using original intent.', error.message);
        return userIntent;
    }
}

async function planTask(context) {
    // Legacy placeholder, can be removed or kept for structure
    return { status: "ready" };
}

module.exports = {
    planTask,
    refineIntent
};
