# DuckDB Preview Plugin for Yazi

A fast table data preview plugin for [Yazi](https://yazi-rs.github.io/) file manager that uses [DuckDB](https://duckdb.org/) to display CSV, Parquet, and TSV files in a formatted table view.

## Features

- 🦆 **Fast Preview**: Uses DuckDB's high-performance engine for quick data loading
- 📊 **Multiple Formats**: Supports CSV, TSV, Parquet files (including compressed versions)
- 🎨 **Formatted Display**: Clean table layout with colors and proper alignment
- 🔧 **Configurable**: Customizable row/column limits and display options
- 💾 **Smart Caching**: Built-in caching for better performance
- 📈 **Schema Information**: Optional display of column types and metadata

## Screenshots

```
┌─────────┬─────────────┬───────┬─────────────────────────┬─────────┬──────────┐
│  id     │    name     │  age  │          email          │ active  │  salary  │
│ int64   │   varchar   │ int64 │         varchar         │ boolean │  double  │
├─────────┼─────────────┼───────┼─────────────────────────┼─────────┼──────────┤
│     1   │ John Doe    │    25 │ john.doe@company.com    │ true    │  75000.5 │
│     2   │ Jane Smith  │    30 │ jane.smith@company.com  │ true    │  82000.0 │
│     3   │ Bob Johnson │    35 │ bob.johnson@company.com │ false   │ 68000.25 │
└─────────┴─────────────┴───────┴─────────────────────────┴─────────┴──────────┘
```

## Requirements

- [Yazi](https://yazi-rs.github.io/) file manager (v0.2.0 or later)
- [DuckDB](https://duckdb.org/) CLI tool

### Installing DuckDB

**macOS (Homebrew):**
```bash
brew install duckdb
```

**Ubuntu/Debian:**
```bash
wget https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip
unzip duckdb_cli-linux-amd64.zip
sudo mv duckdb /usr/local/bin/
```

**Windows:**
Download from [DuckDB releases](https://github.com/duckdb/duckdb/releases) and add to PATH.

## Installation

### Method 1: Using Yazi Package Manager (Recommended)

```bash
# Install using ya pkg (requires Yazi v0.3.0+)
ya pkg add wybert/duck-preview-yazi:duck-preview
```

The plugin will be automatically installed to your Yazi plugins directory.

### Method 2: Clone Repository

```bash
# Clone to your Yazi plugins directory
git clone https://github.com/wybert/duck-preview.yazi ~/.config/yazi/plugins/duck-preview.yazi
```

### Method 3: Manual Download

1. Download the plugin files to `~/.config/yazi/plugins/duck-preview.yazi/`
2. Ensure the directory structure matches:

```
~/.config/yazi/plugins/duck-preview.yazi/
├── main.lua
├── config.lua
├── duckdb.lua
├── formatter.lua
├── LICENSE
└── README.md
```

## Configuration

Add the plugin to your Yazi configuration file (`~/.config/yazi/yazi.toml`).

**Option 1: Modify the main previewers section (recommended)**

Add CSV support before the generic `text/*` rule in the main `previewers` section:

```toml
previewers = [
    { name = "*/", run = "folder", sync = true },
    # CSV files - DuckDB preview
    { mime = "text/csv", run = "duck-preview" },
    # Code (this must come AFTER CSV rule)
    { mime = "text/*", run = "code" },
    # ... rest of your previewers
]

[plugin]
prepend_previewers = [
    # DuckDB table data preview for compressed files
    { name = "*.csv.gz", run = "duck-preview" },
    { name = "*.csv.bz2", run = "duck-preview" },
    { name = "*.tsv", run = "duck-preview" },
    { name = "*.tsv.gz", run = "duck-preview" },
    { name = "*.parquet", run = "duck-preview" },
]
```

**Option 2: Override in prepend_previewers (alternative)**

```toml
[plugin]
prepend_previewers = [
    # DuckDB table data preview
    { mime = "text/csv", run = "duck-preview" },
    { name = "*.csv.gz", run = "duck-preview" },
    { name = "*.csv.bz2", run = "duck-preview" },
    { name = "*.tsv", run = "duck-preview" },
    { name = "*.tsv.gz", run = "duck-preview" },
    { name = "*.parquet", run = "duck-preview" },
]
```

**Important:** CSV files have mime type `text/csv` which is normally handled by the generic `text/*` rule for code preview. You need to add the CSV rule **before** the `text/*` rule for it to take precedence.

# Plugin configuration
[plugin.duck-preview]
max_rows = 25                    # Maximum rows to display
max_columns = 8                  # Maximum columns to display
show_types = true                # Show column types
show_metadata = true             # Show file metadata
table_style = "bordered"         # Table style: "bordered", "simple", "compact"
type_display = "short"           # Type display: "short", "full", "none"
column_width_limit = 30          # Maximum width per column
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `max_rows` | 25 | Maximum number of rows to display |
| `max_columns` | 8 | Maximum number of columns to display |
| `show_types` | true | Show column data types |
| `show_metadata` | true | Show file metadata (row count, etc.) |
| `table_style` | "bordered" | Table border style |
| `type_display` | "short" | How to display column types |
| `column_width_limit` | 30 | Maximum width per column |

## Supported File Types

| Format | Extensions | Compression |
|--------|------------|-------------|
| CSV | `.csv` | `.csv.gz`, `.csv.bz2` |
| TSV | `.tsv` | `.tsv.gz` |
| Parquet | `.parquet` | Native compression |

## Usage

1. Open Yazi file manager
2. Navigate to a supported file (CSV, TSV, Parquet)
3. The preview will automatically display in the right pane
4. Use Yazi's normal navigation keys to browse files

## Package Management

### Installing with ya pkg

```bash
# Install the plugin
ya pkg add wybert/duck-preview.yazi

# List installed plugins
ya pkg list

# Update all plugins
ya pkg upgrade

# Remove the plugin
ya pkg remove wybert/duck-preview.yazi
```

### Manual Uninstallation

If you installed manually, remove the plugin directory:
```bash
rm -rf ~/.config/yazi/plugins/duck-preview.yazi
```

## Performance

- **Caching**: Results are cached for 5 minutes to improve performance
- **Lazy Loading**: Only processes files when previewed
- **Memory Efficient**: Uses DuckDB's streaming capabilities
- **Fast Query**: Leverages DuckDB's optimized CSV/Parquet readers

## Troubleshooting

### Plugin Not Working

1. **Check DuckDB Installation**:
   ```bash
   duckdb --version
   ```

2. **Check Plugin Installation**:
   ```bash
   ls ~/.config/yazi/plugins/duck-preview.yazi/
   ```

3. **Check Yazi Configuration**:
   Ensure the plugin is correctly added to `yazi.toml`

4. **Check Logs**:
   ```bash
   YAZI_LOG=debug yazi
   tail -f ~/.local/state/yazi/yazi.log
   ```

### Common Issues

**"DuckDB not found" Error**:
- Install DuckDB and ensure it's in your PATH
- Test with: `which duckdb`

**No Preview Showing**:
- Check file extensions are correctly mapped
- Verify the plugin directory structure
- Restart Yazi after configuration changes

**Performance Issues with Large Files**:
- Reduce `max_rows` in configuration
- Reduce `max_columns` for wide datasets
- Consider using compressed formats (CSV.gz)

## File Structure

```
duck-preview.yazi/
├── main.lua           # Plugin entry point
├── config.lua         # Configuration management
├── duckdb.lua         # DuckDB integration
├── formatter.lua      # Table formatting
└── README.md          # This file
```

## Development

### Architecture

- **main.lua**: Plugin entry point, handles file detection and preview coordination
- **duckdb.lua**: DuckDB command execution and JSON parsing
- **formatter.lua**: Table formatting and UI widget creation
- **config.lua**: Configuration loading and defaults

### Extending the Plugin

To add support for new file formats:

1. Update `is_supported_file()` in `main.lua`
2. Add format detection logic if needed
3. Update configuration documentation

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with various file formats
5. Submit a pull request

## Changelog

### v1.0.0
- Initial release
- Support for CSV, TSV, Parquet files
- Configurable display options
- Caching for performance
- Clean table formatting

---

**Note**: This plugin requires both Yazi and DuckDB to be installed. Make sure to follow the installation instructions for both tools.