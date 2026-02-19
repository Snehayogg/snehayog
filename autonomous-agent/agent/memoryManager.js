/**
 * Memory Manager
 * Handles compressed memory and context window optimization.
 */

// In-memory store for now (persisted only during server runtime)
// Structure: { userId: [ "Memory 1", "Memory 2" ] }
const memoryStore = {};

async function getMemory(userProfile) {
    const userId = userProfile.id || 'anonymous';
    const memories = memoryStore[userId] || [];
    
    // Return last 5 memories for context
    const recentMemories = memories.slice(-5);
    
    if (recentMemories.length > 0) {
        console.log(`🧠 Memory Manager: Retrieved ${recentMemories.length} recent memories for ${userId}`);
    }
    
    return recentMemories;
}

async function addMemory(userProfile, intent, result) {
    const userId = userProfile.id || 'anonymous';
    
    if (!memoryStore[userId]) {
        memoryStore[userId] = [];
    }

    // Synthesize a short memory string
    // In real app, LLM would summarize this: "User created a [topic] post about [intent]"
    const timestamp = new Date().toISOString();
    const shortMemory = `[${timestamp}] Created ${result.type} content about "${intent}" titled "${result.title}"`;

    memoryStore[userId].push(shortMemory);
    console.log(`💾 Memory Manager: Saved memory: "${shortMemory}"`);
}

module.exports = {
    getMemory,
    addMemory
};
