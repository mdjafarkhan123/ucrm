# Brevo MCP installation and secret handling

Research date: 2026-08-30

## Outcome

Brevo operates a hosted, authenticated MCP server. Its main endpoint is
`https://mcp.brevo.com/v1/brevo/mcp`; Brevo says this combines all 27 modules. The narrower webhook
server is `https://mcp.brevo.com/v1/brevo_webhooks_management/mcp`. Authentication uses a dedicated
Brevo **MCP token** in the HTTP header `Authorization: Bearer <token>`. Brevo says this token grants
full read/write access to the account and must be stored securely.

Sources: [Brevo MCP Server](https://developers.brevo.com/docs/mcp-protocol),
[Tool configuration](https://developers.brevo.com/docs/integration-guide).

## Supported clients and configuration contract

Brevo provides explicit setup instructions for Claude Desktop, Claude Code, Cursor, Windsurf, VS
Code with GitHub Copilot, and Cline. The overview also says the server works with those clients “and
more,” but the current official guide does **not** publish Codex-specific setup instructions.

- **Claude Desktop:** configure `mcpServers.brevo` with `command: "npx"`; invoke `mcp-remote` with
  the hosted URL and an authorization header; put `BREVO_MCP_TOKEN` in that MCP entry's `env` map.
  Node.js is required.
- **Claude Code:** Brevo's direct command is
  `claude mcp add --transport http --scope user brevo https://mcp.brevo.com/v1/brevo/mcp --header
  "Authorization: Bearer <token>"`. Its documented manual alternative uses the same `npx
  mcp-remote` bridge and `env` map as Claude Desktop.
- **Cursor and Cline:** use `mcpServers`, a `url`, and an `Authorization` entry under `headers`.
- **Windsurf:** use `mcpServers`, `serverUrl`, and `headers`.
- **VS Code:** use `servers`, `type: "http"`, `url`, and `headers`.

The guide does not document loading this token from a repository `.env` file. For Claude
Desktop/Claude Code's bridge configuration, the documented secret location is the MCP server
entry's `env.BREVO_MCP_TOKEN`; the other examples place the bearer value directly in the client's
MCP configuration. A project `.env` may be supported by a particular client or wrapper, but that is
outside Brevo's published contract and should not be assumed from these docs.

The overview and setup examples differ slightly in whether they show a space after the colon in the
`mcp-remote` header argument. Brevo's troubleshooting section is unambiguous: the header value must
be `Bearer <token>`, with a space between `Bearer` and the token.

Source: [Brevo MCP tool configuration](https://developers.brevo.com/docs/integration-guide).

## Two different bearer tokens

Do not conflate these credentials:

1. The **Brevo MCP token** authenticates an MCP client to `mcp.brevo.com` and grants Brevo-account
   read/write access.
2. A webhook's **delivery bearer token** is application-chosen data stored in the webhook's
   `auth.token` field. Brevo sends it when delivering events to that webhook's notification URL.

Rotating the second token does not repair or replace the first. If only `auth.token` appeared in a
webhook-list result, the exposed credential is the webhook receiver's delivery secret, not the MCP
account token.

Sources: [Brevo MCP tool configuration](https://developers.brevo.com/docs/integration-guide),
[Secure webhook calls](https://developers.brevo.com/docs/secured-webhooks).

## Does Brevo document redaction of `auth.token`?

No redaction requirement or MCP-specific secret-filtering behavior was found in Brevo's current MCP
overview or tool-configuration guide. More importantly, Brevo's official REST contract explicitly
shows both `auth.token` and custom header values in the successful response examples for **Get all
webhooks** and **Get a webhook details**. The list endpoint says it returns complete webhook details,
including authentication/security settings; the detail endpoint explicitly describes
authentication credentials as returned information.

Consequently, a Brevo MCP webhook-list tool returning `auth.token` is consistent with the documented
upstream webhook response shape. The public documentation does not establish whether the hosted MCP
layer is intended to pass that response through unchanged, but it provides no basis for claiming
that the local MCP client or configuration is malfunctioning merely because the field appears.

Sources: [Get all webhooks](https://developers.brevo.com/reference/get-webhooks),
[Get a webhook details](https://developers.brevo.com/reference/get-webhook).

## Security implication and practical boundary

Although the field is documented, a live webhook bearer token is still a secret. An MCP tool result
can enter model context, transcripts, logs, screenshots, or copied diagnostics. Treat a returned
`auth.token`, custom authentication-header value, or credential embedded in a webhook URL as sensitive
output.

- If a real webhook delivery token was copied into an untrusted place, rotate that webhook token and
  the receiver's expected value together.
- Rotate the Brevo MCP token only if the MCP credential itself was exposed or cannot be accounted
  for; it is a separate full-account credential.
- Client-side redaction may reduce accidental display, but it cannot change Brevo's hosted MCP or
  REST response contract. A provider-side redaction request would need to be raised with Brevo.
- Installing the narrower webhook MCP endpoint reduces tool breadth, not the sensitivity of webhook
  read results.

The rotation and redaction recommendations above are security inferences from Brevo's documented
response shapes and token authority; they are not Brevo-published MCP redaction instructions.
