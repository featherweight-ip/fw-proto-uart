# Configuration file for the Sphinx documentation builder.
#
# Full reference: https://www.sphinx-doc.org/en/master/usage/configuration.html

# -- Project information -----------------------------------------------------

project = "fw-proto-uart"
copyright = "2026, Featherweight-HDL"
author = "Featherweight-HDL"
release = "0.1.0"

# -- General configuration ---------------------------------------------------

extensions = [
    "myst_parser",
    "sphinx_copybutton",
]

# Parse both reStructuredText and Markdown sources.
source_suffix = {
    ".rst": "restructuredtext",
    ".md": "markdown",
}

# MyST extensions: tables, admonitions, $-math, definition lists, etc.
myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "fieldlist",
    "tasklist",
]
myst_heading_anchors = 3

templates_path = ["_templates"]

# Keep the build tree and any imported upstream spec dump out of the doc build.
exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
    "spec.md",
    "spec.pdf",
]

# -- Options for HTML output -------------------------------------------------

html_theme = "furo"
html_title = "fw-proto-uart — UART Protocol Kit"
html_static_path = ["_static"]

html_theme_options = {
    "source_repository": "https://github.com/featherweight-hdl/fw-proto-uart/",
    "source_branch": "main",
    "source_directory": "docs/",
}

# Default lexer for untagged code fences. Kept as plain text so ASCII diagrams
# don't fail Pygments lexing under the CI '-W' flag. Code blocks that are
# SystemVerilog tag themselves explicitly with ```systemverilog.
highlight_language = "text"
pygments_style = "friendly"
pygments_dark_style = "monokai"
