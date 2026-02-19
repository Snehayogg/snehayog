/**
 * Trend Analysis Tool
 * Simulates fetching trending topics from social media or news sources.
 */

async function analyzeTrends(niche) {
    console.log(`📈 Trend Tool: Analyzing trends for niche "${niche}"...`);
    
    // In a real app, this would call Google Trends API or Twitter API.
    // For now, we return high-quality simulated trends based on keywords.

    const trendsDB = {
        "tech": ["AI Agents", "Nothing Phone 2a", "GPT-5 Rumors", "Coding Best Practices"],
        "food": ["Mango Recipes", "Healthy Smoothies", "Monsoon Snacks", "Street Food Challenges"],
        "fitness": ["75 Hard Challenge", "Home Workouts", "Protein Myths", "Yoga for Back Pain"],
        "finance": ["SIP vs Lumpsum", "Tax Saving Tips", "Crypto Bull Run", "Stock Market Crash"],
        "travel": ["Hidden Gems in India", "Budget Solo Trip", "Visa Free Countries", "Staycation Ideas"],
        "general": ["Viral Instagram Audio", "Motivation Monday", "Weekend Vibes", "Life Hacks"]
    };

    // Simple keyword matching to find category
    let category = "general";
    const nicheLower = niche.toLowerCase();
    
    if (nicheLower.includes("tech") || nicheLower.includes("code") || nicheLower.includes("ai")) category = "tech";
    else if (nicheLower.includes("food") || nicheLower.includes("cook") || nicheLower.includes("recipe")) category = "food";
    else if (nicheLower.includes("gym") || nicheLower.includes("fit") || nicheLower.includes("health")) category = "fitness";
    else if (nicheLower.includes("money") || nicheLower.includes("invest") || nicheLower.includes("market")) category = "finance";
    else if (nicheLower.includes("travel") || nicheLower.includes("trip") || nicheLower.includes("tour")) category = "travel";

    const trends = trendsDB[category] || trendsDB["general"];
    console.log(`📈 Trend Tool: Found active trends: ${trends.join(", ")}`);
    
    return trends;
}

module.exports = {
    analyzeTrends
};
