#!/bin/bash
# Setup script for self_test MCP Server
# Adds the MCP server configuration to Claude Code

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         self_test MCP Server - Claude Code Setup          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$(dirname "$SCRIPT_DIR")"
DIST_PATH="$MCP_DIR/dist/index.js"

# Check if built
if [ ! -f "$DIST_PATH" ]; then
    echo -e "${YELLOW}MCP server not built. Building now...${NC}"
    cd "$MCP_DIR"
    npm install
    npm run build
    echo -e "${GREEN}✓ Build complete${NC}"
    echo
fi

# Claude Code config locations
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/settings.json"

# Also check for project-level config
PROJECT_CONFIG_FILE="$MCP_DIR/../../.claude/settings.local.json"

echo -e "${BLUE}Configuration Options:${NC}"
echo "  1) Global (applies to all projects)"
echo "  2) Project (applies to this project only)"
echo "  3) Both"
echo
read -p "Select option [1-3]: " CONFIG_CHOICE

# MCP server config to add
MCP_CONFIG=$(cat <<EOF
{
  "flutter-self-test": {
    "command": "node",
    "args": ["$DIST_PATH"],
    "env": {
      "FLUTTER_APP_HOST": "localhost",
      "FLUTTER_APP_PORT": "9999"
    }
  }
}
EOF
)

add_to_config() {
    local config_file="$1"
    local config_dir="$(dirname "$config_file")"

    # Create directory if needed
    mkdir -p "$config_dir"

    # Check if file exists
    if [ -f "$config_file" ]; then
        # Check if already configured
        if grep -q "flutter-self-test" "$config_file" 2>/dev/null; then
            echo -e "${YELLOW}⚠ MCP server already configured in $config_file${NC}"
            read -p "  Overwrite? [y/N]: " OVERWRITE
            if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
                return 0
            fi
        fi

        # Backup existing config
        cp "$config_file" "$config_file.bak"
        echo -e "${BLUE}  Backed up to $config_file.bak${NC}"

        # Use jq if available, otherwise use node
        if command -v jq &> /dev/null; then
            # Merge with existing config using jq
            jq --argjson new "$MCP_CONFIG" '.mcpServers = (.mcpServers // {}) + $new' "$config_file.bak" > "$config_file"
        else
            # Use node to merge
            node -e "
                const fs = require('fs');
                const existing = JSON.parse(fs.readFileSync('$config_file.bak', 'utf8'));
                const newConfig = $MCP_CONFIG;
                existing.mcpServers = { ...(existing.mcpServers || {}), ...newConfig };
                fs.writeFileSync('$config_file', JSON.stringify(existing, null, 2));
            "
        fi
    else
        # Create new config
        cat > "$config_file" <<CONF
{
  "mcpServers": $MCP_CONFIG
}
CONF
    fi

    echo -e "${GREEN}✓ Updated $config_file${NC}"
}

case $CONFIG_CHOICE in
    1)
        add_to_config "$CLAUDE_CONFIG_FILE"
        ;;
    2)
        add_to_config "$PROJECT_CONFIG_FILE"
        ;;
    3)
        add_to_config "$CLAUDE_CONFIG_FILE"
        add_to_config "$PROJECT_CONFIG_FILE"
        ;;
    *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
esac

echo
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    Setup Complete!                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Restart Claude Code to load the new MCP server"
echo "  2. Start your Flutter app with self_test_bridge enabled"
echo "  3. Use flutter_snapshot to see available widgets"
echo
echo -e "${BLUE}Flutter app setup:${NC}"
echo "  Add to your main.dart:"
echo
echo -e "${YELLOW}  import 'package:self_test_bridge/self_test_bridge.dart';${NC}"
echo
echo -e "${YELLOW}  void main() async {${NC}"
echo -e "${YELLOW}    WidgetsFlutterBinding.ensureInitialized();${NC}"
echo -e "${YELLOW}    if (kDebugMode) {${NC}"
echo -e "${YELLOW}      final bridge = SelfTestBridge(router: goRouter, port: 9999);${NC}"
echo -e "${YELLOW}      await bridge.start();${NC}"
echo -e "${YELLOW}    }${NC}"
echo -e "${YELLOW}    runApp(MyApp());${NC}"
echo -e "${YELLOW}  }${NC}"
echo
