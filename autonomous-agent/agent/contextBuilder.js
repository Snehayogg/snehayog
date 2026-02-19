const { BASE_SYSTEM_PROMPT } = require('./systemPrompt');

/**
 * layer 1: User Profile Context
 */
/**
 * layer 1: User Profile Context
 */
/**
 * layer 1: User Background (HINTS ONLY)
 */
function buildUserProfileContext(userProfile, videoTitles) {
    const name = userProfile.name || 'Creator';
    let backgroundInfo = [];

    // Removed Bio as per user request (not part of feature)

    if (videoTitles && videoTitles.length > 0) {
        const titlesStr = videoTitles.slice(0, 5).map(t => `"${t}"`).join(', ');
        backgroundInfo.push(`- Content Style Hint: Matches videos like ${titlesStr}`);
    }
    
    return `
LAYER 1 — BACKGROUND CONTEXT (USE AS HINTS ONLY)
- Creator Name: ${name}
${backgroundInfo.join('\n')}
- Instruction: Use this background only to adjust tone/style. Do NOT let it override the user's specific request.
`;
}

/**
 * layer 2: Dynamic Intent Context (PRIMARY)
 */
function buildDynamicIntentContext(intent) {
    return `
LAYER 2 — USER REQUEST (ABSOLUTE PRIORITY)
- User Prompt: "${intent}"
- CRITICAL INSTRUCTION: Analyze this prompt deeply. This is your MAIN COMMAND. 
- Ignore background context if it contradicts this prompt.
- Focus on the specific topic, format, and goal requested here.
`;
}

/**
 * layer 2.5: Memory Context (HINTS ONLY)
 */
function buildMemoryContext(memory) {
    if (!memory || memory.length === 0) return '';
    
    return `
PAST MEMORY (REFERENCE ONLY):
- Recent interactions:
${memory.map(m => `- ${m}`).join('\n')}
- Instruction: Use this only to avoid repetition.
`;
}

/**
 * Combines all layers into the final system prompt.
 */
function constructContext(userProfile, intent, memory, videoTitles) {
    const profileLayer = buildUserProfileContext(userProfile, videoTitles);
    const intentLayer = buildDynamicIntentContext(intent);
    const memoryLayer = buildMemoryContext(memory);

    console.log('🏗️ Context Builder: Assembling layers (Profile + Intent + Memory)...');
    
    return `
${BASE_SYSTEM_PROMPT}

--------------------------------------------------
CURRENT SESSION CONTEXT:

${profileLayer}

${memoryLayer}

${intentLayer}
    `;
}

module.exports = {
    constructContext,
    buildUserProfileContext,
    buildDynamicIntentContext
};
