# Contributing

Start with the [development guide](docs/development.md), [architecture](docs/architecture.md), and [test strategy](docs/testing.md).

- Write documentation, comments, UI text, and developer messages in English. Preserve deliberate Unicode fixtures and protocol/persistence identifiers.
- Keep transport, authentication policy, feature effects, storage, and UI responsibilities separate. Inject effects at meaningful boundaries; do not build interfaces with no substitution use.
- Preserve actor/thread ownership, generation checks, bounded queues, deadlines, and cancellation. A replaced or unauthenticated session must not execute user actions.
- Validate untrusted sizes, paths, timestamps, identities, and capability values before allocation or effects. Never log pairing material, clipboard contents, contact data, or notification text.
- Update both protocol implementations, shared fixtures/schemas, and compatibility tests when a wire contract changes.
- Add focused regression tests for real failure modes. Do not substitute mocks for OS/radio behavior claims.
- Run formatting, the publication guard, unit tests, Android lint, and both builds before submission. Explain any device-specific validation that could not be performed.
- Run `python3 scripts/install-security-tools.py` and `python3 scripts/check-security.py` for workflow/Python correctness and redacted history checks. Review dependency-update PRs; changing an action pin also requires an administrator-reviewed allowlist update.
- Keep commits reviewable and document behavior changes and limitations in English. Public function/type comments should explain contracts and ownership rather than restate names.
- Do not stage local investigations, device captures, generated outputs, credentials, signing keys, or personal environment settings. Review staged content even when `.gitignore` is present.

No deployment or public release is performed by the development CI pipelines.

See the [security policy](SECURITY.md) and [repository security controls](docs/github-security.md). Do not put sensitive findings or device data in public issue/PR templates.
