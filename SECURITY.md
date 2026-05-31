# Security

This project is a local proxy and configuration helper. It should be treated as sensitive because it forwards prompts, code context, and tool-call data to an external model provider.

## API Keys

- Do not commit API keys.
- Do not hard-code API keys in scripts.
- Set `CODEX_DEEPSEEK_KEY` in your shell or a local secret manager.
- Prefer a fresh key with limited permissions.
- Rotate or revoke keys after testing.

## Network Boundary

The proxy listens on `127.0.0.1` by default. Do not bind it to `0.0.0.0` unless you fully understand the exposure.

## Data Boundary

Prompts, code snippets, file contents, and tool-call arguments may be sent to the configured provider. Use this fallback only for projects where that is acceptable.

## Reporting

Open a GitHub issue without including secrets, request bodies, private code, or full logs.
