-- duck-preview.yazi/main.lua
-- Yazi DuckDB Table Preview Plugin
-- Fast preview of CSV and Parquet files using DuckDB

-- ============================================================================
-- Configuration Module
-- ============================================================================
local config = {}

-- Default configuration
config.defaults = {
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
function config.get_user_config()
    local user_config = {}
    
    -- Try to get plugin configuration from yazi
    if rt and rt.plugin and rt.plugin["duck-preview"] then
        user_config = rt.plugin["duck-preview"]
    end
    
    -- Merge with defaults
    local merged_config = {}
    for k, v in pairs(config.defaults) do
        merged_config[k] = user_config[k] ~= nil and user_config[k] or v
    end
    
    return merged_config
end

-- ============================================================================
-- DuckDB Module
-- ============================================================================
local duckdb = {}

-- Check if DuckDB is available on the system
function duckdb.check_availability()
    local child, err = Command("duckdb"):arg({"--version"}):stdout(Command.PIPED):spawn()
    if not child then
        return false
    end
    
    local success = child:wait()
    return success and success.success
end

-- Execute DuckDB query and return parsed results
function duckdb.query_file(file_path, options)
    options = options or {}
    local limit = options.limit or 25
    
    -- Build the query
    local query = string.format(
        "SELECT * FROM '%s' LIMIT %d",
        file_path:gsub("'", "''"), -- Escape single quotes
        limit
    )
    
    -- Execute DuckDB command
    local child, err = Command("duckdb")
        :arg({"-json", "-cmd", query})
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :spawn()
    
    if not child then
        error("Failed to spawn DuckDB process: " .. (err or "unknown error"))
    end
    
    local output, err_output = child:wait_with_output()
    
    if not output or not output.success then
        local error_msg = err_output and err_output.stderr or "Unknown DuckDB error"
        error("DuckDB query failed: " .. error_msg)
    end
    
    -- Parse JSON output
    local json_str = output.stdout
    if not json_str or json_str == "" then
        return {columns = {}, rows = {}, metadata = {row_count = 0}}
    end
    
    -- Parse the JSON response
    local success, result = pcall(function()
        return duckdb.parse_duckdb_json(json_str)
    end)
    
    if not success then
        error("Failed to parse DuckDB JSON output: " .. tostring(result))
    end
    
    return result
end

-- Parse DuckDB JSON output
function duckdb.parse_duckdb_json(json_str)
    -- DuckDB returns JSON as an array of objects: [{col1: val1, col2: val2}, ...]
    local data = {}
    
    -- Simple JSON parser for DuckDB output
    -- Remove whitespace and check if we have an array
    local trimmed = json_str:gsub("^%s*", ""):gsub("%s*$", "")
    if not trimmed:match("^%[.*%]$") then
        return {columns = {}, rows = {}, metadata = {row_count = 0}}
    end
    
    -- Extract objects from array
    local objects = {}
    local content = trimmed:sub(2, -2) -- Remove [ and ]
    
    -- Split by },{ pattern
    local current_obj = ""
    local brace_count = 0
    local in_string = false
    local escape_next = false
    
    for i = 1, #content do
        local char = content:sub(i, i)
        
        if escape_next then
            current_obj = current_obj .. char
            escape_next = false
        elseif char == "\\" then
            current_obj = current_obj .. char
            escape_next = true
        elseif char == '"' then
            current_obj = current_obj .. char
            in_string = not in_string
        elseif not in_string then
            if char == "{" then
                brace_count = brace_count + 1
                current_obj = current_obj .. char
            elseif char == "}" then
                brace_count = brace_count - 1
                current_obj = current_obj .. char
                
                if brace_count == 0 then
                    -- Complete object found
                    table.insert(objects, current_obj)
                    current_obj = ""
                    -- Skip comma if present
                    if content:sub(i + 1, i + 1) == "," then
                        i = i + 1
                    end
                end
            else
                current_obj = current_obj .. char
            end
        else
            current_obj = current_obj .. char
        end
    end
    
    -- Parse each object
    local rows = {}
    local columns = {}
    local column_order = {}
    
    for _, obj_str in ipairs(objects) do
        local row = duckdb.parse_json_object(obj_str)
        table.insert(rows, row)
        
        -- Collect column names in order
        if #column_order == 0 then
            for k, _ in pairs(row) do
                table.insert(column_order, k)
            end
            table.sort(column_order)
            columns = column_order
        end
    end
    
    return {
        columns = columns,
        rows = rows,
        metadata = {row_count = #rows}
    }
end

-- Simple JSON object parser
function duckdb.parse_json_object(obj_str)
    local obj = {}
    local content = obj_str:gsub("^%s*{%s*", ""):gsub("%s*}%s*$", "")
    
    -- Split by comma (respecting quoted strings)
    local pairs = {}
    local current_pair = ""
    local in_string = false
    local escape_next = false
    
    for i = 1, #content do
        local char = content:sub(i, i)
        
        if escape_next then
            current_pair = current_pair .. char
            escape_next = false
        elseif char == "\\" then
            current_pair = current_pair .. char
            escape_next = true
        elseif char == '"' then
            current_pair = current_pair .. char
            in_string = not in_string
        elseif char == "," and not in_string then
            table.insert(pairs, current_pair)
            current_pair = ""
        else
            current_pair = current_pair .. char
        end
    end
    
    if current_pair ~= "" then
        table.insert(pairs, current_pair)
    end
    
    -- Parse each key-value pair
    for _, pair in ipairs(pairs) do
        local key, value = pair:match('^%s*"([^"]+)"%s*:%s*(.+)%s*$')
        if key and value then
            obj[key] = duckdb.parse_json_value(value)
        end
    end
    
    return obj
end

-- Parse JSON values
function duckdb.parse_json_value(value_str)
    local trimmed = value_str:gsub("^%s*", ""):gsub("%s*$", "")
    
    if trimmed == "null" then
        return nil
    elseif trimmed == "true" then
        return true
    elseif trimmed == "false" then
        return false
    elseif trimmed:match('^".*"$') then
        -- String value - remove quotes and handle escapes
        return trimmed:sub(2, -2):gsub('\\"', '"'):gsub('\\\\', '\\')
    elseif trimmed:match('^-?%d+%.?%d*$') then
        -- Number
        return tonumber(trimmed)
    else
        -- Return as string if we can't parse it
        return trimmed
    end
end

-- ============================================================================
-- Formatter Module
-- ============================================================================
local formatter = {}

-- Format query results as table widgets
function formatter.format_table(result, area, user_config)
    local widgets = {}
    
    if not result or not result.columns or #result.columns == 0 then
        table.insert(widgets, ui.Text("No data found"):fg("yellow"))
        return widgets
    end
    
    -- Add metadata header if enabled
    if user_config.show_metadata and result.metadata then
        local metadata_text = formatter.format_metadata(result.metadata)
        table.insert(widgets, ui.Text(metadata_text):fg("cyan"))
        table.insert(widgets, ui.Text("")) -- Empty line
    end
    
    -- Determine which columns to show
    local display_columns = formatter.select_columns(result.columns, user_config.max_columns)
    local truncated_columns = #result.columns > #display_columns
    
    -- Calculate column widths
    local col_widths = formatter.calculate_column_widths(result, display_columns, area.w - 4, user_config)
    
    -- Create table header
    local header_widgets = formatter.create_header(display_columns, result.column_types, col_widths, user_config)
    for _, widget in ipairs(header_widgets) do
        table.insert(widgets, widget)
    end
    
    -- Add separator
    table.insert(widgets, formatter.create_separator(col_widths, user_config))
    
    -- Add data rows
    local rows_to_show = math.min(user_config.max_rows, #result.rows)
    for i = 1, rows_to_show do
        local row_widget = formatter.create_row(result.rows[i], display_columns, col_widths, user_config)
        table.insert(widgets, row_widget)
    end
    
    -- Add truncation indicator if needed
    if #result.rows > rows_to_show or truncated_columns then
        local truncation_msg = formatter.create_truncation_message(result, rows_to_show, truncated_columns)
        table.insert(widgets, ui.Text(""))
        table.insert(widgets, ui.Text(truncation_msg):fg("gray"))
    end
    
    return widgets
end

-- Format metadata
function formatter.format_metadata(metadata)
    local parts = {}
    if metadata.row_count then
        table.insert(parts, "Rows: " .. metadata.row_count)
    end
    return table.concat(parts, " | ")
end

-- Select columns to display
function formatter.select_columns(columns, max_columns)
    if #columns <= max_columns then
        return columns
    end
    
    -- Take first N-1 columns, then add "..." indicator
    local selected = {}
    for i = 1, max_columns - 1 do
        table.insert(selected, columns[i])
    end
    table.insert(selected, "...")
    
    return selected
end

-- Calculate optimal column widths
function formatter.calculate_column_widths(result, display_columns, available_width, user_config)
    local widths = {}
    local total_cols = #display_columns
    
    -- Start with minimum widths (column header length)
    for _, col in ipairs(display_columns) do
        widths[col] = math.max(#col, 3) -- Minimum 3 chars
    end
    
    -- Sample data to determine content widths
    local sample_size = math.min(10, #result.rows)
    for i = 1, sample_size do
        local row = result.rows[i]
        for _, col in ipairs(display_columns) do
            if col ~= "..." and row[col] ~= nil then
                local content = formatter.format_cell_value(row[col])
                widths[col] = math.max(widths[col], #content)
            end
        end
    end
    
    -- Apply width limits
    for col, width in pairs(widths) do
        widths[col] = math.min(width, user_config.column_width_limit)
    end
    
    return widths
end

-- Format cell value for display
function formatter.format_cell_value(value)
    if value == nil then
        return "NULL"
    elseif type(value) == "number" then
        if value == math.floor(value) then
            return string.format("%d", value)
        else
            return string.format("%.2f", value)
        end
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    else
        return tostring(value)
    end
end

-- Create table header
function formatter.create_header(columns, column_types, col_widths, user_config)
    local widgets = {}
    
    -- Column names
    local header_parts = {}
    for _, col in ipairs(columns) do
        local width = col_widths[col] or 10
        local padded = formatter.pad_string(col, width)
        table.insert(header_parts, padded)
    end
    
    local header_line = "│ " .. table.concat(header_parts, " │ ") .. " │"
    table.insert(widgets, ui.Text(header_line):fg("white"):bold())
    
    return widgets
end

-- Create separator line
function formatter.create_separator(col_widths, user_config)
    local parts = {}
    for col, width in pairs(col_widths) do
        table.insert(parts, string.rep("─", width))
    end
    local separator = "├─" .. table.concat(parts, "─┼─") .. "─┤"
    return ui.Text(separator):fg("gray")
end

-- Create data row
function formatter.create_row(row, columns, col_widths, user_config)
    local row_parts = {}
    for _, col in ipairs(columns) do
        local width = col_widths[col] or 10
        local value = col == "..." and "..." or formatter.format_cell_value(row[col])
        local padded = formatter.pad_string(value, width)
        table.insert(row_parts, padded)
    end
    
    local row_line = "│ " .. table.concat(row_parts, " │ ") .. " │"
    return ui.Text(row_line)
end

-- Create truncation message
function formatter.create_truncation_message(result, rows_shown, columns_truncated)
    local parts = {}
    
    if #result.rows > rows_shown then
        table.insert(parts, string.format("Showing %d of %d rows", rows_shown, #result.rows))
    end
    
    if columns_truncated then
        table.insert(parts, string.format("showing %d of %d columns", #result.columns - 1, #result.columns))
    end
    
    return table.concat(parts, ", ")
end

-- Pad string to specific width
function formatter.pad_string(str, width)
    local len = #str
    if len >= width then
        return str:sub(1, width - 3) .. "..."
    else
        return str .. string.rep(" ", width - len)
    end
end

-- ============================================================================
-- Main Plugin
-- ============================================================================

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
    
    -- Debug logging for parquet files
    if file.name:lower():match("%.parquet$") then
        ya.dbg("duck-preview: Parquet file detected:", file.name)
    end
    
    -- Check if file is supported
    if not is_supported_file(file) then
        ya.dbg("duck-preview: File not supported:", file.name)
        return
    end
    
    ya.dbg("duck-preview: Processing supported file:", file.name)
    
    -- Check if DuckDB is available (cache the result)
    if duckdb_available == nil then
        ya.dbg("duck-preview: Checking DuckDB availability...")
        duckdb_available = duckdb.check_availability()
        ya.dbg("duck-preview: DuckDB available:", duckdb_available)
    end
    
    if not duckdb_available then
        ya.dbg("duck-preview: DuckDB not available, showing error message")
        ya.preview_widget(job, {
            ui.Text("DuckDB not found. Please install DuckDB to preview table data.")
                :fg("yellow")
        })
        return
    end
    
    ya.dbg("duck-preview: DuckDB is available, proceeding with query")
    
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
    ya.dbg("duck-preview: Running DuckDB query on:", file_path)
    local success, result = pcall(function()
        return duckdb.query_file(file_path, {
            limit = user_config.max_rows
        })
    end)
    
    ya.dbg("duck-preview: Query success:", success)
    if not success then
        ya.dbg("duck-preview: Query failed with error:", result)
        -- Fall back to error message
        ya.preview_widget(job, {
            ui.Text("Error reading file: " .. (result or "Unknown error"))
                :fg("red")
        })
        return
    end
    
    ya.dbg("duck-preview: Query successful, formatting table...")
    ya.dbg("duck-preview: Result has", result and #result.rows or 0, "rows")
    
    -- Format the data for display
    local widgets = formatter.format_table(result, area, user_config)
    ya.dbg("duck-preview: Created", #widgets, "widgets for display")
    
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
    ya.dbg("duck-preview: Calling ya.preview_widget with", #widgets, "widgets")
    ya.preview_widget(job, widgets)
    ya.dbg("duck-preview: preview_widget call completed")
end

return M