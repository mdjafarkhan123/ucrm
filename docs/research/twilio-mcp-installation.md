# Twilio MCP installation

Research date: 2026-08-26

## Outcome

Twilio's MCP server is a hosted, read-only documentation and API-schema service at
`https://mcp.twilio.com/docs`. It does not require a local package, a Twilio account, an API key,
OAuth, or another authentication secret. The only prerequisite beyond a supported coding agent is
network access to that URL.

The service is currently Public Beta. Twilio says beta behavior can change and is not covered by
its Support Terms or SLA.

Source: [Twilio MCP server](https://www.twilio.com/docs/ai/mcp).

## Codex setup documented by Twilio

From any shell where the Codex CLI is installed, run:

```powershell
codex mcp add twilio-docs --url https://mcp.twilio.com/docs
```

The current local Codex CLI identifies `--url` as a streamable HTTP MCP server. No bearer-token
option or environment variable is needed for Twilio's public documentation endpoint.

Twilio documents that exact Codex command, but its page does not describe a project-scope flag or
claim that the command writes configuration into the current repository. Therefore, if the goal is
specifically a repository-owned configuration, use the repo's established `.mcp.json` convention
instead of assuming the CLI command is project-scoped:

```json
{
  "mcpServers": {
    "twilio-docs": {
      "type": "http",
      "url": "https://mcp.twilio.com/docs"
    }
  }
}
```

In this repository, `.mcp.json` already contains `mcpServers` entries using this HTTP `type` and
`url` shape. Adding `twilio-docs` alongside those entries is the smallest project-level change. The
JSON example above is a repo-specific application of the existing convention; Twilio's page shows
the URL-based object explicitly for Cursor and its CLI command explicitly for Codex.

Sources: [Twilio MCP server: Codex and Cursor setup](https://www.twilio.com/docs/ai/mcp#codex),
[repository MCP configuration](../../.mcp.json).

## Authentication and capability boundary

- Authentication: none. Do not add Twilio Account SID, Auth Token, API key, OAuth client, or bearer
  token for this endpoint.
- Tools exposed: `twilio__search` searches indexed API operations and documentation;
  `twilio__retrieve` fetches full parameter and response schemas for IDs returned by search.
- Scope: public Twilio OpenAPI specifications, Twilio docs/support content, SendGrid docs/support
  content, and Segment docs.
- Execution: read-only. It does not make Twilio API calls or mutate a Twilio account.
- Version behavior: search prefers the latest API version; callers can request a specific version
  through `filter.version`.

Source: [Twilio MCP server: features and limitations](https://www.twilio.com/docs/ai/mcp#features).

## Verification

After the configuration is added, start a fresh Codex session if the active session does not reload
MCP servers automatically, then:

1. Run `codex mcp list` and confirm an enabled `twilio-docs` entry points to
   `https://mcp.twilio.com/docs`.
2. Ask the coding agent: `How do I send an SMS with Twilio?`
3. Confirm the response invokes `twilio__search` and references specific Twilio API endpoints. A
   follow-up requiring full request fields should cause the agent to use `twilio__retrieve` on one
   or more IDs returned by search.

Twilio's official verification specifically requires the server to appear in MCP configuration and
the example question to produce endpoint-specific output through `twilio__search`.

Source: [Twilio MCP server: verify your connection](https://www.twilio.com/docs/ai/mcp#verify-your-connection).

## Removal or rollback

If installed through the Codex CLI, inspect the registered name with `codex mcp list`. The Codex CLI
supports removing an MCP entry by name; for this installation the name is `twilio-docs`. If installed
through the repository configuration, remove only the `twilio-docs` object from `.mcp.json` and keep
the other server entries intact.

