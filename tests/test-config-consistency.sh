#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"
cd "$KIT" || exit 1

TMPL="config/config.json.tmpl"
jq empty "$TMPL" || fail "$TMPL is not valid JSON"

mapfile -t declared < <(jq -r '.integrations[].template' "$TMPL")
for t in "${declared[@]}"; do
    assert_file "matugen/templates/$t"
done
pass "every integrations[].template in $TMPL exists under matugen/templates/"

mapfile -t hooks < <(jq -r '.postProcessing[].command' "$TMPL")
for h in "${hooks[@]}"; do
    base="${h##*/}"
    assert_file "bin/$base"
    grep -q "bin/$base" install.sh || fail "install.sh never mentions bin/$base, but $TMPL's postProcessing references it"
done
pass "every postProcessing[].command in $TMPL is a script install.sh ships"

for key in paperBin paperStillBin paperVkBin; do
    path="$(jq -r ".paths.$key" "$TMPL")"
    case "$path" in
        __HOME__/.local/bin/skwd-paper-v2|__HOME__/.local/libexec/skwd-wall-still|__HOME__/.local/libexec/skwd-wall-vk) ;;
        *) fail "paths.$key = $path does not match a location install.sh writes" ;;
    esac
done
pass "paths.* in $TMPL match the renderer locations install.sh writes"
