// Debug configuration for parsers
// Set to true to enable debug logging for specific parsers
const DEBUG_CONFIG = {
    automation: false,
    azure: false,
    cluster: false,
    unix: false,
    events: false,
    packages: false,
    services: false,
    worker: false
};

// Helper function to check if debug is enabled for a parser
function isDebugEnabled(parserName) {
    return DEBUG_CONFIG[parserName] === true;
}

// Export for use in parsers
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { DEBUG_CONFIG, isDebugEnabled };
}
