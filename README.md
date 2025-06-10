# Duck Preview Yazi Plugin

A fast table data preview plugin for [Yazi](https://yazi-rs.github.io/) file manager that uses [DuckDB](https://duckdb.org/) to display CSV, Parquet, and TSV files in a formatted table view.

## Installation

### Using Yazi Package Manager (Recommended)

```bash
# Install using ya pkg
ya pkg add wybert/duck-preview-yazi:duck-preview
```

### Manual Installation

```bash
# Clone to your Yazi plugins directory
git clone https://github.com/wybert/duck-preview-yazi.git ~/.config/yazi/plugins/
```

## Plugin Location

The plugin files are located in the `duck-preview.yazi/` subdirectory:

```
duck-preview-yazi/
└── duck-preview.yazi/
    ├── main.lua
    ├── config.lua
    ├── duckdb.lua
    ├── formatter.lua
    ├── LICENSE
    └── README.md
```

For complete documentation, see [duck-preview.yazi/README.md](duck-preview.yazi/README.md).

## Quick Setup

1. Install DuckDB: `brew install duckdb` (macOS) or download from [duckdb.org](https://duckdb.org/)
2. Install plugin: `ya pkg add wybert/duck-preview-yazi:duck-preview`
3. Add to `~/.config/yazi/yazi.toml`:

```toml
[plugin]
prepend_previewers = [
    { name = "*.csv", run = "duck-preview" },
    { name = "*.parquet", run = "duck-preview" },
]
```

## Features

- 🦆 Fast preview using DuckDB
- 📊 Support for CSV, TSV, Parquet files  
- 🎨 Clean table formatting with colors
- 🔧 Configurable display options
- 💾 Smart caching for performance