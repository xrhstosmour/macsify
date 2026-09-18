# Function to display Herdr's default keybindings organized by category.
# Usage:
#   herdr_cheat_sheet
function herdr_cheat_sheet --description "Display Herdr keybindings with descriptions"
    echo ""
    echo "🐑 HERDR:"
    echo "  Prefix key:      Key 3 + b (ctrl+b, real ctrl per the keyboard remap)"
    echo "  Sidebar is pinned left, prefix+b toggles it out of the way."
    echo ""

    echo "⭐ ESSENTIAL FIVE:"
    echo "  - prefix + t                     New tab"
    echo "  - prefix + v                     Split right"
    echo "  - prefix + -                     Split down"
    echo "  - prefix + h/j/k/l               Move between panes"
    echo "  - prefix + w                     Workspace navigation"
    echo "  - prefix + q                     Detach, leave everything running"
    echo ""

    echo "🪟 PANES:"
    echo "  - prefix + z                     Zoom the focused pane"
    echo "  - prefix + x                     Close pane"
    echo "  - prefix + SHIFT + h/j/k/l       Swap panes"
    echo "  - prefix + SHIFT + r             Resize mode"
    echo ""

    echo "📑 TABS:"
    echo "  - prefix + ]                     Next tab"
    echo "  - prefix + [                     Previous tab"
    echo "  - prefix + SHIFT + t             Rename tab"
    echo "  - prefix + SHIFT + x             Close tab"
    echo ""

    echo "🤖 AGENTS:"
    echo "  - prefix + 1-9                   Focus agent by sidebar index"
    echo ""

    echo "📦 WORKSPACES & SESSION:"
    echo "  - prefix + n                     New workspace"
    echo "  - prefix + SHIFT + w             Rename workspace"
    echo "  - prefix + SHIFT + d             Close workspace"
    echo "  - prefix + w                     Workspace picker"
    echo "  - prefix + g                     Goto picker"
    echo "  - prefix + b                     Toggle sidebar"
    echo ""

    echo "⚙️  SYSTEM:"
    echo "  - prefix + s                     Open settings"
    echo "  - prefix + r                     Reload config"
    echo "  - prefix + /                     Show all bindings"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
end
