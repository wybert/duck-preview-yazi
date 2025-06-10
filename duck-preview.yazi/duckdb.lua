-- duck-preview.yazi/duckdb.lua
-- DuckDB integration for table data queries

local M = {}

-- Check if DuckDB is available on the system
function M.check_availability()
    local child, err = Command("duckdb"):args({"--version"}):stdout(Command.PIPED):spawn()
    if not child then
        return false
    end
    
    local success = child:wait()
    return success and success.success
end

-- Execute DuckDB query and return parsed results
function M.query_file(file_path, options)
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
        :args({"-json", "-cmd", query})
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
    if not json_str or json_str:match("^%s*$") then
        return {
            columns = {},
            rows = {},
            metadata = {
                row_count = 0,
                column_count = 0,
                file_size = M.get_file_size(file_path)
            }
        }
    end
    
    local success, data = pcall(function()
        return M.parse_duckdb_json(json_str)
    end)
    
    if not success then
        error("Failed to parse DuckDB output: " .. (data or "JSON parse error"))
    end
    
    -- Get additional metadata
    data.metadata = M.get_file_metadata(file_path)
    
    return data
end

-- Parse DuckDB JSON output
function M.parse_duckdb_json(json_str)
    -- DuckDB outputs JSON as an array: [{"col1": "val1"}, {"col2": "val2"}]
    local rows = {}
    local columns = {}
    local column_types = {}
    
    -- Trim whitespace
    json_str = json_str:match("^%s*(.-)%s*$")
    
    -- Check if it's an array
    if not json_str:match("^%[.*%]$") then
        -- Fallback: try to parse as single object
        local obj = M.parse_json_line(json_str)
        if obj then
            table.insert(rows, obj)
            for k, v in pairs(obj) do
                table.insert(columns, k)
                column_types[k] = M.infer_type(v)
            end
        end
        return {
            columns = columns,
            column_types = column_types,
            rows = rows
        }
    end
    
    -- Remove outer brackets
    local content = json_str:match("^%[(.*)%]$")
    if not content or content == "" then
        return {
            columns = {},
            column_types = {},
            rows = {}
        }
    end
    
    -- Split array elements (this is a simple approach)
    -- Look for },{ patterns to split objects
    local objects = {}
    local current_obj = ""
    local brace_count = 0
    local in_string = false
    local escape_next = false
    
    for i = 1, #content do
        local char = content:sub(i, i)
        
        if escape_next then
            escape_next = false
        elseif char == "\\" then
            escape_next = true
        elseif char == '"' and not escape_next then
            in_string = not in_string
        elseif not in_string then
            if char == "{" then
                brace_count = brace_count + 1
            elseif char == "}" then
                brace_count = brace_count - 1
            end
        end
        
        current_obj = current_obj .. char
        
        -- If we completed an object, parse it
        if not in_string and brace_count == 0 and current_obj:match("^%s*{.*}%s*$") then
            local obj = M.parse_json_line(current_obj)
            if obj then
                table.insert(objects, obj)
                
                -- Extract column names from first object
                if #columns == 0 then
                    for k, v in pairs(obj) do
                        table.insert(columns, k)
                        column_types[k] = M.infer_type(v)
                    end
                end
            end
            current_obj = ""
        elseif not in_string and char == "," and brace_count == 0 then
            -- Skip comma between objects
            current_obj = ""
        end
    end
    
    return {
        columns = columns,
        column_types = column_types,
        rows = objects
    }
end

-- Simple JSON line parser (basic implementation)
function M.parse_json_line(line)
    -- This is a simplified JSON parser for DuckDB output
    -- DuckDB outputs simple key-value JSON objects
    
    if not line:match("^%s*{.*}%s*$") then
        return nil
    end
    
    local result = {}
    
    -- Remove outer braces and split by commas
    local content = line:match("^%s*{(.*)}%s*$")
    if not content then return nil end
    
    -- Simple state machine to parse key-value pairs
    local in_string = false
    local in_escape = false
    local current_item = ""
    local items = {}
    
    for i = 1, #content do
        local char = content:sub(i, i)
        
        if in_escape then
            current_item = current_item .. char
            in_escape = false
        elseif char == "\\" then
            current_item = current_item .. char
            in_escape = true
        elseif char == '"' then
            current_item = current_item .. char
            in_string = not in_string
        elseif char == "," and not in_string then
            table.insert(items, current_item)
            current_item = ""
        else
            current_item = current_item .. char
        end
    end
    
    if current_item ~= "" then
        table.insert(items, current_item)
    end
    
    -- Parse each key-value pair
    for _, item in ipairs(items) do
        local key, value = item:match('^%s*"([^"]+)"%s*:%s*(.+)%s*$')
        if key and value then
            result[key] = M.parse_json_value(value)
        end
    end
    
    return result
end

-- Parse individual JSON value
function M.parse_json_value(value)
    value = value:match("^%s*(.-)%s*$") -- trim
    
    if value == "null" then
        return nil
    elseif value == "true" then
        return true
    elseif value == "false" then
        return false
    elseif value:match('^".*"$') then
        -- String value - remove quotes and handle escapes
        return value:sub(2, -2):gsub('\\"', '"'):gsub('\\\\', '\\')
    elseif value:match("^-?%d+$") then
        -- Integer
        return tonumber(value)
    elseif value:match("^-?%d*%.%d+$") then
        -- Float
        return tonumber(value)
    else
        -- Fallback to string
        return value
    end
end

-- Infer data type from value
function M.infer_type(value)
    if value == nil then
        return "NULL"
    elseif type(value) == "boolean" then
        return "BOOLEAN"
    elseif type(value) == "number" then
        if value == math.floor(value) then
            return "INTEGER"
        else
            return "DOUBLE"
        end
    elseif type(value) == "string" then
        -- Try to detect date/time patterns
        if value:match("^%d%d%d%d%-%d%d%-%d%d$") then
            return "DATE"
        elseif value:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d") then
            return "TIMESTAMP"
        else
            return "VARCHAR"
        end
    else
        return "UNKNOWN"
    end
end

-- Get file metadata
function M.get_file_metadata(file_path)
    -- Get basic file information
    local file_size = M.get_file_size(file_path)
    
    -- Try to get row/column count with a separate query
    local row_count, column_count = M.get_table_stats(file_path)
    
    return {
        file_size = file_size,
        row_count = row_count,
        column_count = column_count
    }
end

-- Get file size
function M.get_file_size(file_path)
    local child = Command("stat")
        :args({"-f", "%z", file_path})
        :stdout(Command.PIPED)
        :spawn()
    
    if child then
        local output = child:wait_with_output()
        if output and output.success then
            return tonumber(output.stdout:match("%d+")) or 0
        end
    end
    
    return 0
end

-- Get table statistics (row count, column count)
function M.get_table_stats(file_path)
    -- Try to get count efficiently
    local count_query = string.format("SELECT COUNT(*) as row_count FROM '%s'", file_path:gsub("'", "''"))
    
    local child = Command("duckdb")
        :args({"-json", "-cmd", count_query})
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :spawn()
    
    local row_count = nil
    if child then
        local output = child:wait_with_output()
        if output and output.success then
            local count_data = M.parse_duckdb_json(output.stdout)
            if count_data.rows and count_data.rows[1] then
                row_count = count_data.rows[1].row_count
            end
        end
    end
    
    -- Get column count from DESCRIBE
    local describe_query = string.format("DESCRIBE '%s'", file_path:gsub("'", "''"))
    
    child = Command("duckdb")
        :args({"-json", "-cmd", describe_query})
        :stdout(Command.PIPED)
        :stderr(Command.PIPED)
        :spawn()
    
    local column_count = nil
    if child then
        local output = child:wait_with_output()
        if output and output.success then
            local describe_data = M.parse_duckdb_json(output.stdout)
            if describe_data.rows then
                column_count = #describe_data.rows
            end
        end
    end
    
    return row_count, column_count
end

return M 