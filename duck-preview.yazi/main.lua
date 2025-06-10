-- duck-preview.yazi/main.lua
-- Yazi DuckDB Table Preview Plugin
-- Fast preview of CSV and Parquet files using DuckDB

local config = require("config")
local duckdb = require("duckdb")
local formatter = require("formatter")

-- Plugin state for caching (simple module-level cache)
local cache_data = {}
local duckdb_available = nil

-- Detect if file is supported
local function is_supported_file(file)
    local name = file.name:lower()
    return name:match("%.csv$") or 
           name:match("%.parquet$") or 
           name:match("%.csv%.gz$") or
           name:match("%.csv%.bz2$") or
           name:match("%.tsv$") or
           name:match("%.tsv%.gz$")
end

-- Main previewer implementation
local M = {}

function M:peek(job)
    local file = job.file
    local area = job.area
    
    -- Check if file is supported
    if not is_supported_file(file) then
        return
    end
    
    -- Check if DuckDB is available (cache the result)
    if duckdb_available == nil then
        duckdb_available = duckdb.check_availability()
    end
    
    if not duckdb_available then
        ya.preview_widget(job, {
            ui.Text("DuckDB not found. Please install DuckDB to preview table data.")
                :fg("yellow")
        })
        return
    end
    
    local file_path = tostring(file.url)
    
    -- Simple cache check
    local cached = cache_data[file_path]
    if cached and (os.time() - cached.timestamp) < 300 then -- 5 min cache
        ya.preview_widget(job, cached.data)
        return
    end
    
    -- Get user configuration
    local user_config = config.get_user_config()
    
    -- Query the file with DuckDB
    local success, result = pcall(function()
        return duckdb.query_file(file_path, {
            limit = user_config.max_rows
        })
    end)
    
    if not success then
        -- Fall back to error message
        ya.preview_widget(job, {
            ui.Text("Error reading file: " .. (result or "Unknown error"))
                :fg("red")
        })
        return
    end
    
    
    -- Format the data for display
    local widgets = formatter.format_table(result, area, user_config)
    
    -- Cache the result (simple cache with size limit)
    if #cache_data > 50 then
        -- Simple cleanup: remove half the entries
        local keys = {}
        for k in pairs(cache_data) do table.insert(keys, k) end
        for i = 1, math.floor(#keys / 2) do
            cache_data[keys[i]] = nil
        end
    end
    
    cache_data[file_path] = {
        data = widgets,
        timestamp = os.time()
    }
    
    -- Display the preview
    ya.preview_widget(job, widgets)
end


return M 