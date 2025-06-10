-- duck-preview.yazi/formatter.lua
-- Table formatting for terminal display

local M = {}

-- Format query results as table widgets
function M.format_table(result, area, config)
    local widgets = {}
    
    if not result or not result.columns or #result.columns == 0 then
        table.insert(widgets, ui.Text("No data found")
            :fg("yellow"))
        return widgets
    end
    
    -- Add metadata header if enabled
    if config.show_metadata and result.metadata then
        local metadata_text = M.format_metadata(result.metadata)
        table.insert(widgets, ui.Text(metadata_text)
            :fg("cyan"))
        table.insert(widgets, ui.Text("")) -- Empty line
    end
    
    -- Determine which columns to show
    local display_columns = M.select_columns(result.columns, config.max_columns)
    local truncated_columns = #result.columns > #display_columns
    
    -- Calculate column widths
    local col_widths = M.calculate_column_widths(result, display_columns, area.w - 4, config)
    
    -- Create table header
    local header_widgets = M.create_header(display_columns, result.column_types, col_widths, config)
    for _, widget in ipairs(header_widgets) do
        table.insert(widgets, widget)
    end
    
    -- Add separator
    table.insert(widgets, M.create_separator(col_widths, config))
    
    -- Add data rows
    local rows_to_show = math.min(config.max_rows, #result.rows)
    for i = 1, rows_to_show do
        local row_widget = M.create_row(result.rows[i], display_columns, col_widths, config)
        table.insert(widgets, row_widget)
    end
    
    -- Add truncation indicator if needed
    if #result.rows > rows_to_show or truncated_columns then
        local truncation_msg = M.create_truncation_message(result, rows_to_show, truncated_columns)
        table.insert(widgets, ui.Text(""))
        table.insert(widgets, ui.Text(truncation_msg)
            :fg("gray"))
    end
    
    return widgets
end

-- Format metadata information
function M.format_metadata(metadata)
    local parts = {}
    
    if metadata.row_count then
        table.insert(parts, string.format("Rows: %s", M.format_number(metadata.row_count)))
    end
    
    if metadata.column_count then
        table.insert(parts, string.format("Columns: %d", metadata.column_count))
    end
    
    if metadata.file_size then
        table.insert(parts, string.format("Size: %s", M.format_file_size(metadata.file_size)))
    end
    
    return table.concat(parts, " | ")
end

-- Select which columns to display
function M.select_columns(columns, max_columns)
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
function M.calculate_column_widths(result, display_columns, available_width, config)
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
                local content = M.format_cell_value(row[col])
                widths[col] = math.max(widths[col], #content)
            end
        end
    end
    
    -- Apply width limits
    for col, width in pairs(widths) do
        widths[col] = math.min(width, config.column_width_limit)
    end
    
    -- Distribute available space
    local border_space = (total_cols + 1) * 3 -- Account for borders and padding
    local content_space = available_width - border_space
    local total_width = 0
    
    for _, width in pairs(widths) do
        total_width = total_width + width
    end
    
    if total_width > content_space then
        -- Scale down proportionally
        local scale = content_space / total_width
        for col, width in pairs(widths) do
            widths[col] = math.max(3, math.floor(width * scale))
        end
    end
    
    return widths
end

-- Create table header widgets
function M.create_header(columns, column_types, col_widths, config)
    local widgets = {}
    
    -- Header row with column names
    local header_parts = {}
    for _, col in ipairs(columns) do
        local width = col_widths[col] or 10
        local padded = M.pad_string(col, width, "center")
        table.insert(header_parts, padded)
    end
    
    local header_line = M.create_table_line(header_parts, config.table_style)
    table.insert(widgets, ui.Text(header_line)
        :fg("white"):bold())
    
    -- Type row if enabled
    if config.show_types and config.type_display ~= "none" and column_types then
        local type_parts = {}
        for _, col in ipairs(columns) do
            local width = col_widths[col] or 10
            local type_name = column_types[col] or "UNKNOWN"
            if config.type_display == "short" then
                type_name = M.shorten_type_name(type_name)
            end
            local padded = M.pad_string(type_name, width, "center")
            table.insert(type_parts, padded)
        end
        
        local type_line = M.create_table_line(type_parts, config.table_style)
        table.insert(widgets, ui.Text(type_line)
            :fg("gray"))
    end
    
    return widgets
end

-- Create table separator
function M.create_separator(col_widths, config)
    local parts = {}
    for col, width in pairs(col_widths) do
        table.insert(parts, string.rep("-", width))
    end
    
    local separator = M.create_table_line(parts, config.table_style, "-")
    return ui.Text(separator):fg("gray")
end

-- Create data row
function M.create_row(row_data, columns, col_widths, config)
    local parts = {}
    
    for _, col in ipairs(columns) do
        local width = col_widths[col] or 10
        local value = row_data[col]
        local formatted = M.format_cell_value(value)
        local padded = M.pad_string(formatted, width, "left")
        table.insert(parts, padded)
    end
    
    local row_line = M.create_table_line(parts, config.table_style)
    return ui.Text(row_line)
end

-- Create table line with appropriate style
function M.create_table_line(parts, style, fill_char)
    fill_char = fill_char or " "
    
    if style == "bordered" then
        return "│ " .. table.concat(parts, " │ ") .. " │"
    elseif style == "simple" then
        return table.concat(parts, " | ")
    elseif style == "compact" then
        return table.concat(parts, "  ")
    else
        return table.concat(parts, " │ ")
    end
end

-- Format cell value for display
function M.format_cell_value(value)
    if value == nil then
        return "NULL"
    elseif type(value) == "string" then
        -- Escape control characters and limit length
        local escaped = value:gsub("[\r\n\t]", " ")
        return M.truncate_string(escaped, 100)
    elseif type(value) == "number" then
        -- Format numbers nicely
        if value == math.floor(value) then
            return tostring(math.floor(value))
        else
            return string.format("%.3f", value)
        end
    elseif type(value) == "boolean" then
        return value and "true" or "false"
    else
        return tostring(value)
    end
end

-- Pad string to specified width
function M.pad_string(str, width, align)
    str = str or ""
    width = width or 0
    align = align or "left"
    
    if #str >= width then
        return M.truncate_string(str, width)
    end
    
    local padding = width - #str
    
    if align == "center" then
        local left_pad = math.floor(padding / 2)
        local right_pad = padding - left_pad
        return string.rep(" ", left_pad) .. str .. string.rep(" ", right_pad)
    elseif align == "right" then
        return string.rep(" ", padding) .. str
    else -- "left"
        return str .. string.rep(" ", padding)
    end
end

-- Truncate string to specified length
function M.truncate_string(str, max_len)
    if #str <= max_len then
        return str
    end
    
    if max_len <= 3 then
        return string.rep(".", max_len)
    end
    
    return str:sub(1, max_len - 3) .. "..."
end

-- Shorten type names for compact display
function M.shorten_type_name(type_name)
    local short_names = {
        VARCHAR = "STR",
        INTEGER = "INT", 
        DOUBLE = "NUM",
        BOOLEAN = "BOOL",
        TIMESTAMP = "TIME",
        DATE = "DATE",
        NULL = "NULL"
    }
    
    return short_names[type_name] or type_name
end

-- Create truncation message
function M.create_truncation_message(result, rows_shown, columns_truncated)
    local parts = {}
    
    if #result.rows > rows_shown then
        table.insert(parts, string.format("Showing %d of %d rows", rows_shown, #result.rows))
    end
    
    if columns_truncated then
        table.insert(parts, string.format("Showing %d of %d columns", 
            (#result.columns - 1), #result.columns))
    end
    
    return table.concat(parts, ", ")
end

-- Format numbers with thousand separators
function M.format_number(num)
    if not num then return "unknown" end
    
    local formatted = tostring(num)
    local result = ""
    local len = #formatted
    
    for i = 1, len do
        result = result .. formatted:sub(i, i)
        if (len - i) % 3 == 0 and i < len then
            result = result .. ","
        end
    end
    
    return result
end

-- Format file sizes
function M.format_file_size(bytes)
    if not bytes or bytes == 0 then return "0 B" end
    
    local units = {"B", "KB", "MB", "GB", "TB"}
    local unit_index = 1
    local size = bytes
    
    while size >= 1024 and unit_index < #units do
        size = size / 1024
        unit_index = unit_index + 1
    end
    
    if unit_index == 1 then
        return string.format("%d %s", size, units[unit_index])
    else
        return string.format("%.1f %s", size, units[unit_index])
    end
end

return M 