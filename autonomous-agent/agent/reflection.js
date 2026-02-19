const ollama = require('ollama').default;
const MODEL = 'gemma:2b';

async function reflectAndImprove(draftResult) {
    console.log('🪞 Reflection: Reviewing Draft for Quality...');

    // Skip reflection for very short or empty content
    if (!draftResult.caption || draftResult.caption.length < 50) return draftResult;

    const reflectionPrompt = `
    You are a Viral Content Editor. Review this draft:
    
    Title: ${draftResult.title}
    Caption: ${draftResult.caption}
    
    Task:
    1. Is the Hook engaging? (First line)
    2. Is the tone authentic?
    3. Are there emojis?
    
    If Good: Return the original draft JSON exactly.
    If Bad: IMPROVE it. Make it punchier, add emojis, fix grammar.
    
    Return ONLY valid JSON with keys: title, caption, hashtags, imagePrompt.
    `;

    try {
        const response = await ollama.chat({
            model: MODEL,
            messages: [{ role: 'user', content: reflectionPrompt }],
            format: 'json',
            stream: false
        });

        // Parse the improved draft
        let improvedData;
        try {
             improvedData = JSON.parse(response.message.content);
        } catch (e) {
             // If parse fails, return original
             return draftResult;
        }

        // Merge/Override
        const finalResult = {
            ...draftResult,
            title: improvedData.title || draftResult.title,
            caption: improvedData.caption || draftResult.caption,
            hashtags: improvedData.hashtags || draftResult.hashtags,
            imagePrompt: improvedData.imagePrompt || draftResult.imagePrompt
        };

        console.log('✅ Reflection: Draft Polished.');
        return finalResult;

    } catch (error) {
        console.warn('⚠️ Reflection: Check failed, returning original.', error.message);
        return draftResult;
    }
}

module.exports = {
    reflectAndImprove
};
