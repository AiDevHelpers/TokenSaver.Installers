TokenSaver MCP is installed and running as the "TokenSaverMCP" Windows service.
It listens only on this computer, at:

    http://localhost:11436/mcp

To connect an AI client, copy the snippet for your client into its MCP config file,
then restart the client.

----------------------------------------------------------------------
Claude Code
----------------------------------------------------------------------
File: %USERPROFILE%\.claude.json   (root key: mcpServers)

    {
      "mcpServers": {
        "TokenSaver": {
          "type": "http",
          "url": "http://localhost:11436/mcp"
        }
      }
    }

----------------------------------------------------------------------
VS Code Copilot Chat
----------------------------------------------------------------------
File: %APPDATA%\Code\User\mcp.json   (root key: servers, not mcpServers)

    {
      "servers": {
        "TokenSaver": {
          "type": "http",
          "url": "http://localhost:11436/mcp"
        }
      }
    }

----------------------------------------------------------------------
Cursor
----------------------------------------------------------------------
File: %USERPROFILE%\.cursor\mcp.json   (root key: mcpServers)

    {
      "mcpServers": {
        "TokenSaver": {
          "url": "http://localhost:11436/mcp"
        }
      }
    }

----------------------------------------------------------------------
Check that it works
----------------------------------------------------------------------
1. Open the client's MCP panel (Claude Code: /mcp). TokenSaver should show as connected.
2. If it does not, check that the service is running: open Services (services.msc)
   and look for "TokenSaverMCP". Start it if it is stopped.

This README is also saved as CONNECT-TO-AI-CLIENT.txt in the install folder.
