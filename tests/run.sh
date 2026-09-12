#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT" || exit 1

fail_count=0
run() {
    echo
    echo "== $* =="
    "$@" || fail_count=$((fail_count + 1))
}

run bash -n install.sh
run bash -n uninstall.sh
for f in bin/*; do run bash -n "$f"; done
run bash -n lib/theme-lib.sh
run python3 -m py_compile lib/check-contrast.py

run bash tests/test-config-consistency.sh
run bash tests/test-theme-lib.sh
run python3 tests/test_check_contrast.py -v
run bash tests/test-skwd-theme-validate.sh
run bash tests/test-install-uninstall.sh
run bash tests/test-skwd-theme-current.sh

echo
if [ "$fail_count" -eq 0 ]; then
    echo "all test suites passed"
else
    echo "$fail_count test suite(s) failed"
fi
exit "$fail_count"
