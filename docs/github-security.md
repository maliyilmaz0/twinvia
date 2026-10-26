# GitHub security and code quality

Configuration reviewed **27 October 2026** for `maliyilmaz0/twinvia`. Public visibility was authorized by the owner after the publication/history checks. Enabling repository controls is different from proving software security; prepared workflows are different from completed scans. Always inspect the latest Actions run and repository settings before describing a control as enforced.

## Active repository controls

| Control | Configuration |
| --- | --- |
| Dependabot alerts and security updates | Enabled; security updates may open pull requests, never merge them automatically |
| Version updates | Weekly GitHub Actions and Gradle update checks, grouped minor/patch updates and bounded open-PR counts; see `.github/dependabot.yml` |
| Action trust | Selected actions only, full commit-SHA pinning required, exact reviewed SHA allowlist; not all Marketplace or GitHub-owned actions are implicitly allowed |
| Workflow token | Read-only by default; cannot approve pull requests. Checkout does not persist credentials. |
| Privileged workflows | Release publication gets only its required contents/actions access; dependency submission gets contents write only in a trusted main-branch job. Neither uses `pull_request_target`. |
| Forks | All external contributors require workflow approval; untrusted fork pull requests do not receive secrets or write tokens. No `pull_request_target` workflow executes contributor code. |
| Repository reuse | Other repositories have no access to this private repository's actions/workflows |
| Merge policy | Squash merges only, merged branches automatically deleted, update-branch UI enabled; automatic merging remains off |
| Release immutability | Enabled for future releases. The original v0.9.0 release is not claimed to become retroactively immutable. |
| Ownership and intake | CODEOWNERS routes review to `@maliyilmaz0`; pull-request and sanitized bug/feature templates are present; private vulnerability reporting provides a confidential channel |
| Main branch | Pull requests, resolved conversations, linear history and up-to-date successful `publication`, `security-quality`, `android` and `macos` checks are required, including for administrators; force pushes/deletion are blocked. No impossible independent self-approval requirement is imposed on the single maintainer. |
| Version tags | Updates/deletion of `v*` tags are blocked; creation remains available to the authorized publisher. |
| Native secret protection | GitHub secret scanning and push protection are enabled for the public repository; scan results remain separate from these enablement settings. |

Weekly dependency checks run on Wednesday at 06:00, 06:30 and 07:00 Europe/Istanbul for Actions, the Android app, and the clipboard probe respectively. Updates still need compatibility review and passing checks. Updating a pinned action also requires the administrator to review and extend the exact-SHA allowlist before that new pin can execute; do not relax the policy to make a bot PR pass.

## Checks independent of commercial security plans

`Build and test` runs on pushes, pull requests, manual dispatch, and Monday 03:17 UTC / 06:17 Europe/Istanbul:

- `publication`: the product-file allowlist, obvious-credential guard and tooling tests. Ignored research/device state stays excluded.
- `security-quality`: Gitleaks over complete fetched Git history plus staged changes, actionlint for workflows, and Ruff for Python syntax/undefined-name correctness. Output is redacted; raw secret reports are not uploaded.
- `android`: Kotlin formatting, shared/application unit tests, Android lint, APK/helper packaging and the separate clipboard-probe build.
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

## Native scanners and remaining eligibility limits

| Feature | Current state / required change |
| --- | --- |
| Native CodeQL code scanning | Public eligibility enables the four-language security workflow; inspect actual extraction/SARIF results before claiming coverage. Previously skipped private-repository runs are not scan evidence. |
| Native dependency-review gate | Enabled for eligible public pull requests. New detected moderate-or-higher vulnerable dependencies fail the check; a passing diff check does not clear existing alerts. |
| Native secret scanning / push protection | Public-repository protections complement Gitleaks; neither scanner guarantees all secret formats are detected. |
| GitHub private vulnerability reporting | Enabled after public conversion; reporting is confidential even though source is public. |
| GitHub Code Quality product / AI Autofix | Separate Team/Enterprise eligibility, licensing, Actions and AI-credit costs. Not purchased or enabled by this setup. Formatting/lint/tests/coverage are active independently. |

The CodeQL matrix covers Python, Actions, Java/Kotlin, and Swift using security-extended queries and platform-specific builds. It runs automatically on public pushes/PRs, or after an administrator enables `TWINVIA_CODEQL_ENABLED=true` on an actually eligible repository. Dependency review has a separate `TWINVIA_DEPENDENCY_REVIEW_ENABLED` switch, also useful when rerunning a previously private PR event after public conversion. Do not set these switches on an ineligible private repository merely to make skipped jobs look enabled. Validate extraction with the actual Kotlin/Swift toolchains; configuration alone is not scan evidence. Changing visibility back to private requires reassessing eligibility and disabling overrides when no license applies.

## Initial dependency findings

The first resolved Android snapshot surfaced 52 advisory alerts across 13 package names, including three critical alerts, on 27 October 2026. None of those package names appeared in the app's checked `debugRuntimeClasspath`; the submitted inventory also includes build/plugin dependencies. This is evidence about dependency placement, not proof of non-exploitability or permission to dismiss alerts. The build environment remains part of the supply chain, and graph coverage is not a binary-content audit.

Keep these alerts open while tracing tool/plugin ownership and testing compatible upgrades. The initial standalone-probe AGP update and app-library update PRs are not remediation for all 52 findings. Major Gradle/AGP/Kotlin/SDK changes need a coordinated migration and regression checks, not forced transitive-version overrides or mass alert suppression. Counts and severity are a dated snapshot; the GitHub alert list is authoritative.

References: [private CodeQL eligibility](https://docs.github.com/en/code-security/reference/code-scanning/troubleshoot-analysis-errors/private-repository-enablement), [secret scanning availability](https://docs.github.com/en/code-security/how-tos/secure-your-secrets/detect-secret-leaks/enable-secret-scanning), [dependency review](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-review), [GitHub Code Quality enablement](https://docs.github.com/en/code-security/how-tos/maintain-quality-code/enable-code-quality), and [Code Quality costs](https://docs.github.com/en/enterprise-cloud%40latest/code-security/how-tos/maintain-quality-code/view-and-manage-cost).

## Before changing visibility or making a general release

1. Review the complete product Git history, published assets, dependency notices and a project license. A private scanner result does not authorize making the repository public.
2. Configure native secret scanning/push protection and private vulnerability reporting once eligible; validate their actual enabled state. Require approval for all external public-fork workflow contributors and keep write tokens/secrets unavailable to untrusted pull requests.
3. Apply an eligible `main` rule requiring pull requests, resolved conversations, up-to-date branches and successful `publication`, `security-quality`, `android` and `macos` checks. Block branch deletion and force pushes. Add mandatory independent approvals when there is another trusted reviewer; do not create an impossible self-approval rule for a single maintainer.
4. Protect version tags, confirm future immutable release behavior and the publisher's privileges. Never rewrite existing releases to change signatures silently.
5. Run and validate CodeQL and dependency review, then add suitable required checks. Native GitHub Code Quality needs a separate licensing/budget decision; do not start a paid rollout implicitly.
6. Finish stable Android release-key handling and Developer ID/hardened/notarized Mac distribution. Current developer-preview signing limitations remain unchanged.

Account-wide 2FA/passkeys, organization membership and paid billing changes are owner decisions outside this repository setup; this work does not modify them.
