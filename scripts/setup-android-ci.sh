#!/usr/bin/env bash
# Linux CI bootstrap; package checksums come from developer.android.com/studio.
set -euo pipefail
[[ "$(uname -s)" == "Linux" ]] || { echo 'This bootstrap is for Linux CI only.' >&2; exit 1; }
: "${ANDROID_HOME:?Set ANDROID_HOME to the CI SDK cache directory}"
command -v java >/dev/null
command -v python3 >/dev/null
tools_version=15859902
tools_sha256=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
if [[ ! -x "$ANDROID_HOME/cmdline-tools/$tools_version/bin/sdkmanager" ]]; then
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    sdk_archive="$(mktemp)"
    curl --fail --location --retry 3 "https://dl.google.com/android/repository/commandlinetools-linux-${tools_version}_latest.zip" -o "$sdk_archive"
    printf '%s  %s\n' "$tools_sha256" "$sdk_archive" | sha256sum --check --status
    python3 - "$sdk_archive" "$ANDROID_HOME/cmdline-tools/$tools_version" <<'PY'
from pathlib import Path
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    target=Path(sys.argv[2])
    for entry in archive.infolist():
        parts=Path(entry.filename).parts
        if not parts or parts[0]!='cmdline-tools' or '..' in parts:
            raise SystemExit('Unexpected SDK archive path')
        path=target.joinpath(*parts[1:])
        if entry.is_dir(): path.mkdir(parents=True, exist_ok=True)
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(archive.read(entry))
            if path.parent.name=='bin': path.chmod(0o755)
PY
fi
sdkmanager="$ANDROID_HOME/cmdline-tools/$tools_version/bin/sdkmanager"
# CI operators must accept the Android SDK terms before enabling this job.
set +o pipefail
yes | "$sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null
license_status=${PIPESTATUS[1]}
set -o pipefail
[[ "$license_status" == 0 ]]
"$sdkmanager" --sdk_root="$ANDROID_HOME" 'platforms;android-37.0' 'build-tools;36.0.0' 'platform-tools'
