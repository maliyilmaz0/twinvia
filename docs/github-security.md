# GitHub security and code quality

Configuration reviewed **27 October 2026** for `maliyilmaz0/twinvia`. The repository remains private. Enabling repository controls is different from proving software security; prepared workflows are different from completed scans. Always inspect the latest Actions run and repository settings before describing a control as enforced.

## Active repository controls

| Control | Configuration |
| --- | --- |
| Dependabot alerts and security updates | Enabled; security updates may open pull requests, never merge them automatically |
| Version updates | Weekly GitHub Actions and Gradle update checks, grouped minor/patch updates and bounded open-PR counts; see `.github/dependabot.yml` |
| Action trust | Selected actions only, full commit-SHA pinning required, exact reviewed SHA allowlist; not all Marketplace or GitHub-owned actions are implicitly allowed |
| Workflow token | Read-only by default; cannot approve pull requests. Checkout does not persist credentials. |
| Privileged workflows | Release publication gets only its required contents/actions access; dependency submission gets contents write only in a trusted main-branch job. Neither uses `pull_request_target`. |
| Private forks | Workflows disabled; no write tokens or secrets/variables sent to them. GitHub's public-fork contributor approval policy is not available while this repository is private. |
| Repository reuse | Other repositories have no access to this private repository's actions/workflows |
| Merge policy | Squash merges only, merged branches automatically deleted, update-branch UI enabled; automatic merging remains off |
| Release immutability | Enabled for future releases. The original v0.9.0 release is not claimed to become retroactively immutable. |
| Ownership and intake | CODEOWNERS routes review to `@maliyilmaz0`; pull-request and sanitized bug/feature templates are present; see [SECURITY.md](../SECURITY.md) for reporting |

Weekly dependency checks run on Wednesday at 06:00, 06:30 and 07:00 Europe/Istanbul for Actions, the Android app, and the clipboard probe respectively. Updates still need compatibility review and passing checks. Updating a pinned action also requires the administrator to review and extend the exact-SHA allowlist before that new pin can execute; do not relax the policy to make a bot PR pass.

## Checks that work on the private repository

`Build and test` runs on pushes, pull requests, manual dispatch, and Monday 03:17 UTC / 06:17 Europe/Istanbul:

- `publication`: the product-file allowlist, obvious-credential guard and tooling tests. Ignored research/device state stays excluded.
- `security-quality`: Gitleaks over complete fetched Git history plus staged changes, actionlint for workflows, and Ruff for Python syntax/undefined-name correctness. Output is redacted; raw secret reports are not uploaded.
- `android`: Kotlin formatting, shared/application unit tests, Android lint and APK/helper packaging.
- `macos`: Swift formatting, shared/application unit tests, native Swift coverage exports, nested signature verification and app packaging.

The manual release workflow requires all four jobs to have succeeded in a trusted `main` push run. It uploads an explicit binary allowlist, verifies downloaded release bytes, then publishes its draft. Private research and broad local artifact directories are not release inputs.

Security CLI versions and archive SHA-256 values are committed in `.github/security-tools.json`. `install-security-tools.py` checks the archive before installing only the expected regular binary under ignored local tooling. Tool upgrades require reviewing new upstream artifacts/hashes; these versions do not float at runtime.

Run locally from a trusted checkout:

```sh
python3 scripts/install-security-tools.py
python3 scripts/check-security.py
./scripts/check.sh
```

Gitleaks retains all default rules. The only configured exception is the exact public synthetic string `fixture-notification-1`, which denotes a notification ID in fixed protocol examples. No fixture directory, history range, real credential type or scanner failure is broadly suppressed. Any new finding needs investigation before an exception is added. These checks run after a GitHub push; they do not replace server-side push protection or revoking an exposed credential.

Swift coverage artifacts and Android test/lint reports are retained for seven days. Coverage exports are evidence, not an asserted percentage or a new arbitrary threshold. Full Android/UI coverage is not claimed. The local security tools do not constitute Kotlin/Swift semantic vulnerability analysis, and clean scanners do not establish absence of bugs.

## Dependency inventory

`Submit Android dependency graph` runs only on trusted main-branch build-definition changes or explicit main dispatch. The pinned Gradle dependency-submission action resolves dependencies and submits the graph to GitHub with failures visible. This supplies resolved dependencies for GitHub's inventory and Dependabot; it does not send source code to an additional external scanning service.

The Swift helper's resolved pins are committed. Its Google Nearby dependency is fetched from the pinned revision and patched locally during builds. A standalone Dependabot Swift resolver cannot be assumed to reconstruct that ignored local SDK layout, so automatic Swift update PRs are not advertised. Review Nearby, Abseil and BoringSSL pins and upstream advisories deliberately; regenerate the lockfile and run helper/device tests when changing them.

## Native features currently blocked by repository eligibility

| Feature | Current state / required change |
| --- | --- |
| Main-branch rules and rulesets | GitHub returned HTTP 403 requiring GitHub Pro or public visibility for this personal private repository. CODEOWNERS and passing CI are not branch enforcement. |
| Native CodeQL code scanning | Unavailable on the current personal private setup; public repositories are eligible, while private repository coverage requires an eligible Code Security plan/ownership arrangement. The four-language workflow is prepared but skipped here. |
| Native dependency-review gate | Prepared for eligible public/Code Security repositories; skipped here. When active, new moderate-or-higher vulnerable dependencies fail the PR check. |
| Native secret scanning / push protection | Not enabled on this private personal repository. Public repository protections or an eligible Secret Protection arrangement are required. Gitleaks is an additional local/CI control, not an equivalent GitHub setting. |
| GitHub private vulnerability reporting | Not available in the current private state; configure it before public launch. Use the current private reporting guidance meanwhile. |
| GitHub Code Quality product / AI Autofix | Separate Team/Enterprise eligibility, licensing, Actions and AI-credit costs. Not purchased or enabled by this setup. Formatting/lint/tests/coverage are active independently. |

The prepared CodeQL matrix covers Python, Actions, Java/Kotlin, and Swift using security-extended queries and platform-specific builds. It runs automatically after an explicitly approved public conversion, or after an administrator enables `TWINVIA_CODEQL_ENABLED=true` on an actually eligible private repository. Dependency review has a separate `TWINVIA_DEPENDENCY_REVIEW_ENABLED` switch. Do not set either switch merely to make skipped jobs look enabled: first establish licensing/API access, then validate extraction with the actual Kotlin/Swift toolchains. Compiled-language extraction and transitive source coverage must be reviewed in that first run; configuration alone is not scan evidence.

References: [private CodeQL eligibility](https://docs.github.com/en/code-security/reference/code-scanning/troubleshoot-analysis-errors/private-repository-enablement), [secret scanning availability](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/detect-secret-leaks/enable-secret-scanning), [dependency review](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-review), [GitHub Code Quality enablement](https://docs.github.com/en/code-security/how-tos/maintain-quality-code/enable-code-quality), and [Code Quality costs](https://docs.github.com/en/enterprise-cloud%40latest/code-security/how-tos/maintain-quality-code/view-and-manage-cost).

## Before changing visibility or making a general release

1. Review the complete product Git history, published assets, dependency notices and a project license. A private scanner result does not authorize making the repository public.
2. Configure native secret scanning/push protection and private vulnerability reporting once eligible; validate their actual enabled state. Require approval for all external public-fork workflow contributors and keep write tokens/secrets unavailable to untrusted pull requests.
3. Apply an eligible `main` rule requiring pull requests, resolved conversations, up-to-date branches and successful `publication`, `security-quality`, `android` and `macos` checks. Block branch deletion and force pushes. Add mandatory independent approvals when there is another trusted reviewer; do not create an impossible self-approval rule for a single maintainer.
4. Protect version tags, confirm future immutable release behavior and the publisher's privileges. Never rewrite existing releases to change signatures silently.
5. Run and validate CodeQL and dependency review, then add suitable required checks. Native GitHub Code Quality needs a separate licensing/budget decision; do not start a paid rollout implicitly.
6. Finish stable Android release-key handling and Developer ID/hardened/notarized Mac distribution. Current developer-preview signing limitations remain unchanged.

Account-wide 2FA/passkeys, organization membership and paid billing changes are owner decisions outside this repository setup; this work does not modify them.
