# Security policy

Twinvia is a developer preview. The latest source and latest preview release are the maintenance targets; there is no long-term support or security-response SLA. CI results do not establish that the software is free of vulnerabilities.

## Reporting a vulnerability

Do not disclose exploit details, credentials, pairing QR images, clipboard contents, contacts, notification text or device captures in a public issue or pull request.

When GitHub private vulnerability reporting is enabled, use **Security → Report a vulnerability** on this repository. While this repository is private, use the private issue tracker available to authorized collaborators for a sanitized initial report and arrange sensitive evidence directly with the repository owner, [maliyilmaz0](https://github.com/maliyilmaz0). An external reporter who cannot access the private repository should use an existing direct contact with the owner; a public issue is not a substitute for a confidential report. GitHub private reporting must be configured before a public launch; no public security mailbox is currently advertised.

Include the affected version/commit, OS/device, prerequisites, impact, and minimal reproduction using synthetic data. Label static suspicions, observed behavior and proven impact separately. Avoid excessive traffic, testing other people's devices, or collecting unrelated personal data.

## Scope and sensitive components

Review the Android/Mac authentication boundaries, QR trust, certificate pinning, helper IPC, file/path validation, clipboard lock state, notification actions, bounded queues and release/build provenance. The optional Android clipboard helper runs with shell privileges and deserves independent review. A change to network transport does not remove application authentication or OS permission requirements.

Private historical platform investigations, OS-policy modifications and device captures are not distributed in this repository. Do not attach them to issues, CI artifacts or security reports by default.

## Handling a leaked credential

Revoke/rotate the credential first; removing a file does not remove exposure from Git history or existing clones. Notify the owner through a confidential channel, assess affected artifacts and sessions, and document remediation without reproducing the secret. Gitleaks checks history with redacted output; it complements the publication guard and manual review, and is not GitHub push protection.

## Release trust

Read the [preview signing notes](docs/releasing.md) and verify `SHA256SUMS`. The current Android preview is debug-signed and the Mac preview is ad-hoc signed/not notarized. Do not disable system protections to install Twinvia. Future release immutability is enabled in repository settings; older releases are not claimed to become retroactively immutable.

See [GitHub security controls and limitations](docs/github-security.md) for active checks, native-feature eligibility and the public-launch checklist.
