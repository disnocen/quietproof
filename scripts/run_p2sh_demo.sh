#!/bin/sh
# Generates disposable random fixtures. Never use these files for real funds.
set -eu
CLI=${1:?usage: scripts/run_p2sh_demo.sh /path/to/quietproof}
DEMO=$(mktemp -d "${TMPDIR:-/tmp}/quietproof-p2sh.XXXXXX")
for i in 0 1 2; do
  node scripts/p2sh_demo.mjs keygen "$DEMO/custodian$i"
done
node scripts/p2sh_demo.mjs assemble "$DEMO"
# Separate processes; each prover sees just its secret and the common script.
for i in 0 2; do
  "$CLI" p2sh prove --redeem-script "$DEMO/redeem.hex" --position "$i" \
    --output "$DEMO/proof$i.qpm" < "$DEMO/custodian$i/secret.hex"
done
HASH=$(cat "$DEMO/hash.hex")
"$CLI" p2sh verify --proof-a "$DEMO/proof0.qpm" --proof-b "$DEMO/proof2.qpm" --hash "$HASH"
# Reusing the same signer must fail.
if "$CLI" p2sh verify --proof-a "$DEMO/proof0.qpm" --proof-b "$DEMO/proof0.qpm" --hash "$HASH"; then
  echo 'ERROR: same-position pair accepted' >&2
  exit 1
fi
printf 'Demo artifacts (disposable secrets included): %s\n' "$DEMO"
