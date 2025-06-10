-- duck-preview.yazi/config.lua
-- Configuration management for duck-preview plugin

local M = {}

-- Default configuration
M.defaults = {
    max_rows = 25,
    max_columns = 8,
    show_types = true,
    show_metadata = true,
    cache_enabled = true,
    cache_ttl = 300, -- 5 minutes
    cache_max_entries = 50,
    fallback_on_error = true,
    column_width_limit = 30,
    table_style = "bordered", -- "bordered", "simple", "compact"
    type_display = "short", -- "short", "long", "none"
}

-- Get user configuration from yazi
function M.get_user_config()
    local user_config = {}
    
    -- Try to get plugin configuration from yazi
    if rt and rt.plugin and rt.plugin["duck-preview"] then
        user_config = rt.plugin["duck-preview"]
    end
    
    -- Merge with defaults
    local config = {}
    for k, v in pairs(M.defaults) do
        config[k] = user_config[k] ~= nil and user_config[k] or v
    end
    
    return config
end

-- Validate configuration values
function M.validate_config(config)
    -- Ensure positive integers for limits
    config.max_rows = math.max(1, math.min(1000, config.max_rows or M.defaults.max_rows))
    config.max_columns = math.max(1, math.min(50, config.max_columns or M.defaults.max_columns))
    config.column_width_limit = math.max(5, math.min(100, config.column_width_limit or M.defaults.column_width_limit))
    config.cache_max_entries = math.max(1, math.min(500, config.cache_max_entries or M.defaults.cache_max_entries))
    config.cache_ttl = math.max(0, config.cache_ttl or M.defaults.cache_ttl)
    
    -- Validate string options
    local valid_styles = {bordered = true, simple = true, compact = true}
    if not valid_styles[config.table_style] then
        config.table_style = M.defaults.table_style
    end
    
    local valid_type_displays = {short = true, long = true, none = true}
    if not valid_type_displays[config.type_display] then
        config.type_display = M.defaults.type_display
    end
    
    return config
end

-- Export cache constants for other modules
M.cache_ttl = M.defaults.cache_ttl
M.cache_max_entries = M.defaults.cache_max_entries

return M 