#!/bin/sh
# Usage:  sh run_tests.sh            compare every test with its .expected file
#         sh run_tests.sh --update   (re)generate the .expected files
# Run from anywhere; build the compiler first (cd compiler && make).
DIR=$(cd "$(dirname "$0")" && pwd)
BIN="$DIR/../compiler/runsyntax"
[ -x "$BIN" ] || BIN="$DIR/../compiler/runsyntax.exe"
[ -x "$BIN" ] || { echo "Compiler not built. Run: cd compiler && make"; exit 1; }

pass=0; fail=0
for f in "$DIR"/valid/*.rs "$DIR"/lexical_errors/*.rs "$DIR"/syntax_errors/*.rs "$DIR"/semantic_errors/*.rs; do
    exp="${f%.rs}.expected"
    "$BIN" "$f" >/tmp/rs_out.txt 2>/tmp/rs_err.txt
    { cat /tmp/rs_out.txt; echo "--- stderr ---"; cat /tmp/rs_err.txt; } | tr -d '\r' >/tmp/rs_actual.txt
    if [ "$1" = "--update" ]; then
        cp /tmp/rs_actual.txt "$exp"; echo "updated  ${f#$DIR/}"
    elif [ -f "$exp" ] && diff -q "$exp" /tmp/rs_actual.txt >/dev/null; then
        echo "PASS     ${f#$DIR/}"; pass=$((pass+1))
    else
        echo "FAIL     ${f#$DIR/}"; fail=$((fail+1))
    fi
done
[ "$1" = "--update" ] || echo "---- $pass passed, $fail failed ----"
[ "$fail" -eq 0 ]
