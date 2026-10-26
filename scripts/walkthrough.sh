#!/usr/bin/env bash
# Copyright (C) 2026 Plan-B Foundation
# SPDX-License-Identifier: GPL-3.0-or-later
# A real, isolated regtest walkthrough. Never use its disposable keys for funds.
set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
QP=
BITCOIN_BIN=
PAUSE=1
STEP=0
NODE_PID=
DEMO=

usage() {
  cat <<'TEXT'
Usage: bash scripts/walkthrough.sh [OPTIONS]
  --quietproof FILE  RPC-enabled quietproof executable (auto-detect build/ or ../build/)
  --bitcoin-bin DIR Bitcoin Core 28+ binaries (auto-detect prepared Core or PATH)
  --no-pause        Run without the default "Press Enter" pauses
  --help            Show this help

Requires Bash, Node.js, npm ci, and Bitcoin Core 28+ binaries.
Creates a private, peerless regtest node and disposable keys. It never uses your
normal Bitcoin datadir or wallet. Artifacts are retained; its node stops on exit.
TEXT
}
die() { printf 'ERROR: %s\n' "$*" >&2; exit 64; }
while (($#)); do
  case "$1" in
    --quietproof|--bitcoin-bin)
      (($# >= 2)) || die "missing value for $1"
      if [[ $1 == --quietproof ]]; then QP=$2; else BITCOIN_BIN=$2; fi
      shift 2 ;;
    --no-pause) PAUSE=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done
command -v node >/dev/null || die 'Node.js is required'
if [[ -z $QP ]]; then
  for candidate in "$ROOT/build/quietproof" "$ROOT/../build/quietproof"; do
    if [[ -x $candidate ]]; then QP=$candidate; break; fi
  done
fi
[[ -n $QP && -x $QP ]] || die 'build QuietProof with RPC ON, or pass --quietproof FILE'
QP=$(cd -- "$(dirname -- "$QP")" && pwd -P)/$(basename -- "$QP")
core_supported() {
  local directory=$1 version major
  [[ -x $directory/bitcoind && -x $directory/bitcoin-cli ]] || return 1
  version=$("$directory/bitcoind" --version 2>/dev/null) || return 1
  major=$(printf '%s\n' "$version" | sed -n '1s/.*version v\([0-9][0-9]*\).*/\1/p')
  [[ -n $major && $major -ge 28 ]]
}
if [[ -z $BITCOIN_BIN ]]; then
  # Prefer the prepared, pinned demo binaries over an older system installation.
  CORE_CANDIDATES=("$ROOT/../bitcoin-28.3/bin" "$ROOT/bitcoin-28.3/bin"
    "$ROOT/../bitcoin-30.3/bin" "$ROOT/bitcoin-30.3/bin")
  if command -v bitcoind >/dev/null; then
    CORE_CANDIDATES+=("$(dirname -- "$(command -v bitcoind)")")
  fi
  for candidate in "${CORE_CANDIDATES[@]}"; do
    if core_supported "$candidate"; then BITCOIN_BIN=$candidate; break; fi
  done
  [[ -n $BITCOIN_BIN ]] || die 'no supported Bitcoin Core pair found; pass --bitcoin-bin /path/to/bitcoin-28-or-newer/bin'
fi
[[ -d $BITCOIN_BIN ]] || die "Bitcoin binary directory does not exist: $BITCOIN_BIN"
BITCOIN_BIN=$(cd -- "$BITCOIN_BIN" && pwd -P)
BITCOIND=$BITCOIN_BIN/bitcoind
BITCOIN_CLI=$BITCOIN_BIN/bitcoin-cli
[[ -x $BITCOIND && -x $BITCOIN_CLI ]] || die '--bitcoin-bin must contain bitcoind and bitcoin-cli'
CORE_VERSION=$("$BITCOIND" --version)
CORE_MAJOR=$(printf '%s\n' "$CORE_VERSION" | sed -n '1s/.*version v\([0-9][0-9]*\).*/\1/p')
[[ -n $CORE_MAJOR && $CORE_MAJOR -ge 28 ]] || die "Bitcoin Core 28+ is required; $BITCOIND reports ${CORE_VERSION%%$'\n'*}. Select a supported pair with --bitcoin-bin"
if ((PAUSE)) && [[ ! -t 0 ]]; then die 'interactive pauses need a terminal; use --no-pause for automation'; fi
cd -- "$ROOT"
node --input-type=module -e "await import('bitcoinjs-lib')" >/dev/null 2>&1 || die 'run npm ci in the repository first'
"$QP" --help | grep -q 'quietproof p2sh prove' || die 'select the feature-branch quietproof build with --quietproof'

pause() {
  if ((PAUSE)); then
    printf '\nPress Enter to continue (Ctrl-C stops the demo)... '
    IFS= read -r _ || die 'input closed; use --no-pause for automation'
  fi
}
step() { pause; STEP=$((STEP + 1)); printf '\n========== %s. %s ==========\n\n' "$STEP" "$1"; }
show() { printf '\n $' >&2; printf ' %q' "$@" >&2; printf '\n' >&2; }
run() { show "$@"; "$@"; }
json() {
  node -e 'const fs=require("node:fs"); let x=JSON.parse(fs.readFileSync(0,"utf8")); for(const k of process.argv[1].split(".")) x=x[k]; if(x===undefined || x===null) throw Error("missing JSON field"); console.log(typeof x==="object"?JSON.stringify(x):x)' "$1"
}
core() { "$BITCOIN_CLI" -regtest -datadir="$DEMO/node" -rpcconnect=127.0.0.1 -rpcport="$RPC_PORT" "$@"; }
stop_node() {
  if [[ -n $NODE_PID ]]; then
    if kill -0 "$NODE_PID" 2>/dev/null; then
      core stop >/dev/null 2>&1 || kill "$NODE_PID" 2>/dev/null || true
    fi
    wait "$NODE_PID" 2>/dev/null || true
    NODE_PID=
  fi
}
cleanup() {
  local status=$?
  trap - EXIT
  stop_node
  if [[ -n $DEMO ]]; then
    printf '\nArtifacts retained in: %s\n' "$DEMO"
    printf 'This directory includes DISPOSABLE private keys. The private node is stopped.\n'
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
start_node() {
  [[ -z $NODE_PID ]] || die 'owned node already running'
  "$BITCOIND" -regtest -server=1 -datadir="$DEMO/node" -rpcport="$RPC_PORT" \
    -rpcbind=127.0.0.1 -rpcallowip=127.0.0.1 -listen=0 -connect=0 \
    -dnsseed=0 -discover=0 -natpmp=0 -fallbackfee=0.0002 -printtoconsole=0 \
    >>"$DEMO/node-process.log" 2>&1 &
  NODE_PID=$!
  for ((attempt=0; attempt<300; attempt++)); do
    kill -0 "$NODE_PID" 2>/dev/null || die "private node exited; inspect $DEMO/node-process.log"
    if core getblockchaininfo >"$DEMO/chain.json" 2>/dev/null; then
      [[ $(json chain <"$DEMO/chain.json") == regtest ]] || die 'unexpected chain'
      return
    fi
    sleep 0.1
  done
  die "private node did not become ready; inspect $DEMO/node-process.log"
}
expect_exit() {
  local expected=$1 status=0
  shift
  show "$@"
  "$@" || status=$?
  [[ $status -eq $expected ]] || die "expected exit $expected, received $status"
  printf 'Expected rejection observed (exit %s).\n' "$status"
}

cat <<'TEXT'
QUIETPROOF: original P2WPKH and independent P2SH 2-of-3, side by side

This runs real proofs and real Bitcoin Core RPC on a fresh private regtest chain.
The original flow is challenge -> offline proof -> current-UTXO + nonce checks.
The new flow is one independent proof per signer -> verify two (hash,position) proofs.
Expect several minutes of computation, plus as much reading time as you need.
Keys and scripts shown here are disposable teaching material; never fund them.
The demo deliberately shows PUBLIC keys/scripts so you can follow the hashes.
The actual proof files do not disclose those public keys or the redeem script.
TEXT
printf '\nQuietProof: %s\nBitcoin binary: %s\nBitcoin: %s\n' "$QP" "$BITCOIND" "${CORE_VERSION%%$'\n'*}"
DEMO=$(mktemp -d "${TMPDIR:-/tmp}/quietproof-walkthrough.XXXXXX")
mkdir "$DEMO/node" "$DEMO/old" "$DEMO/new"
# Bind port zero to choose a free local RPC port; no default node is contacted.
RPC_PORT=$(node --input-type=module -e 'import net from "node:net"; const s=net.createServer(); s.listen(0,"127.0.0.1",()=>{ console.log(s.address().port); s.close(); });')
RPC_URL=http://127.0.0.1:$RPC_PORT/

step 'Generate three independent keys and inspect the two hash preimages'
for i in 0 1 2; do run node scripts/p2sh_demo.mjs keygen "$DEMO/custodian$i"; done
run node scripts/p2sh_demo.mjs assemble "$DEMO"
node --input-type=module - "$DEMO" <<'NODE'
import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {payments, networks} from 'bitcoinjs-lib';
const d=process.argv[2], network=networks.regtest;
const hex=x=>Buffer.from(x).toString('hex');
const sha=x=>createHash('sha256').update(x).digest('hex');
const keys=[0,1,2].map(i=>Buffer.from(fs.readFileSync(`${d}/custodian${i}/public.hex`,'utf8').trim(),'hex'));
const old=payments.p2wpkh({pubkey:keys[0],network});
const redeem=payments.p2ms({m:2,pubkeys:keys,network});
const newer=payments.p2sh({redeem,network});
const script=fs.readFileSync(`${d}/redeem.hex`,'utf8').trim();
if(script!==hex(redeem.output) || redeem.output.length!==105) throw Error('script reference mismatch');
const fixture={old:{address:old.address,hash:hex(old.hash),script:hex(old.output)},
  new:{address:newer.address,hash:hex(newer.hash),script:hex(newer.output)}};
fs.writeFileSync(`${d}/fixture.json`,JSON.stringify(fixture,null,2)+'\n',{flag:'wx',mode:0o600});
console.log('\nORIGINAL: h_key = RIPEMD160(SHA256(SEC(x0 G)))');
console.log(`  SEC(x0 G), 33 bytes: ${hex(keys[0])}`);
console.log(`  SHA256(SEC):         ${sha(keys[0])}`);
console.log(`  h_key:               ${fixture.old.hash}`);
console.log(`  scriptPubKey:        OP_0 PUSH20 ${fixture.old.hash}`);
console.log(`  raw scriptPubKey:    ${fixture.old.script}`);
console.log(`  regtest address:     ${old.address}`);
console.log('\nNEW: h_script = RIPEMD160(SHA256(S)), with S exactly 105 bytes');
console.log('  S: OP_2');
keys.forEach((key,i)=>console.log(`     PUSH33 ${hex(key)}  (position ${i})`));
console.log('     OP_3 OP_CHECKMULTISIG');
console.log(`  raw S:               ${script}`);
console.log(`  SHA256(S):           ${sha(redeem.output)}`);
console.log(`  h_script:            ${fixture.new.hash}`);
console.log(`  scriptPubKey:        OP_HASH160 PUSH20 ${fixture.new.hash} OP_EQUAL`);
console.log(`  raw scriptPubKey:    ${fixture.new.script}`);
console.log(`  regtest address:     ${newer.address}`);
console.log('\nThe SAME scalar x0 can prove these two DIFFERENT relations.');
console.log('Private scalars stay in owner-only files and are never printed or put in argv.');
NODE
OLD_ADDRESS=$(json old.address <"$DEMO/fixture.json")
NEW_ADDRESS=$(json new.address <"$DEMO/fixture.json")
NEW_SCRIPT=$(json new.script <"$DEMO/fixture.json")

step 'Fund both script types on our own peerless regtest node'
cat <<'TEXT'
Core's funding wallet has its own unrelated keys. We import no custodian secret.
We mature coinbase funds, then send 1 regtest BTC to each of the two scripts.
These are separate outputs: a single-key P2WPKH output and a 2-of-3 P2SH output.
TEXT
start_node
run core createwallet funding
MINER=$(core -rpcwallet=funding getnewaddress '' bech32)
show core generatetoaddress 101 "$MINER"
core generatetoaddress 101 "$MINER" >"$DEMO/mature-blocks.json"
OLD_TX=$(core -rpcwallet=funding sendtoaddress "$OLD_ADDRESS" 1)
NEW_TX=$(core -rpcwallet=funding sendtoaddress "$NEW_ADDRESS" 1)
NEW_VOUT=$(core getrawtransaction "$NEW_TX" true | node -e 'const fs=require("node:fs");const tx=JSON.parse(fs.readFileSync(0,"utf8"));const v=tx.vout.find(v=>v.scriptPubKey.hex===process.argv[1]);if(!v)throw Error("P2SH output missing");console.log(v.n)' "$NEW_SCRIPT")
show core generatetoaddress 2 "$MINER"
core generatetoaddress 2 "$MINER" >"$DEMO/confirm-blocks.json"
printf 'P2WPKH funding transaction: %s\nP2SH funding outpoint: %s:%s\n' "$OLD_TX" "$NEW_TX" "$NEW_VOUT"
run core gettxout "$NEW_TX" "$NEW_VOUT" | tee "$DEMO/new/utxo.json"

step 'Original workflow: the auditor creates a fresh P2WPKH challenge'
cat <<'TEXT'
QuietProof discovers the P2WPKH output through native Core RPC. The request binds
network, verifier, purpose, message, nonce and expiry to the proof transcript.
The circuit itself checks the hidden scalar -> SEC key -> public key hash.
We use a one-day expiry only so the reading pauses do not rush this demo.
TEXT
run "$QP" challenge create --network regtest --address "$OLD_ADDRESS" \
  --verifier walkthrough.local --purpose proof-of-control --message 'QuietProof circuit walkthrough' \
  --expires-in 86400 --output "$DEMO/old/request.qpr" --rpc-url "$RPC_URL" --rpc-datadir "$DEMO/node"
run "$QP" inspect "$DEMO/old/request.qpr"

step 'Original circuit: prove key knowledge with Core stopped'
cat <<'TEXT'
Public circuit inputs: constant one + 20 encoded h_key bytes (21 field inputs).
Private advice: x0, scalar-multiplication trace, point/SEC bits and hash trace.
The circuit checks 1 <= x0 < n, derives x0 G, and hashes its 33-byte SEC encoding.
SHA-256 needs ONE padded block. The transcript also binds the public request.
Only custodian 0's scalar enters this prover, through stdin. Nothing is signed
for Bitcoin, and no transaction is broadcast. Core is stopped during proving.
TEXT
stop_node
started=$SECONDS
run "$QP" prove --request "$DEMO/old/request.qpr" --output "$DEMO/old/proof.qpf" <"$DEMO/custodian0/secret.hex"
OLD_PROVE_SECONDS=$((SECONDS-started))
run "$QP" inspect "$DEMO/old/proof.qpf"

step 'Original auditor: verify the proof, current funds, and consume its nonce'
cat <<'TEXT'
Restart only our private node. The native verifier checks the ZK proof and local
challenge policy, rechecks the exact UTXO and amount, and atomically consumes
the nonce. A successful complete workflow returns result = valid_current.
TEXT
start_node
OLD_VERIFY=("$QP" verify "$DEMO/old/proof.qpf" --network regtest --verifier walkthrough.local
  --purpose proof-of-control --max-lifetime 86400 --minimum-total-sats 100000000
  --nonce-store "$DEMO/old/nonces" --rpc-url "$RPC_URL" --rpc-datadir "$DEMO/node")
started=$SECONDS
run "${OLD_VERIFY[@]}" | tee "$DEMO/old/verified.json"
OLD_VERIFY_SECONDS=$((SECONDS-started))
[[ $(json result <"$DEMO/old/verified.json") == valid_current ]] || die 'original workflow was not valid_current'

step 'Original workflow: replay the same proof and observe rejection'
printf 'The same nonce store already consumed this challenge. Expected exit: 67.\n'
expect_exit 67 "${OLD_VERIFY[@]}"

step 'New circuit: custodian 0 proves control at position 0, offline'
cat <<'TEXT'
Public circuit inputs: constant one + h_script's 20 bytes + i (22 field inputs).
The witness contains x0 and all three script PUBLIC keys, not the other secrets.
The unified circuit enforces valid points, 1 <= x0 < n, pairwise-distinct keys,
boolean one-hot selectors, s0+s1+s2=1, and i=s1+2*s2. All 33 derived SEC bytes
must equal the selected key. It constructs the entire 105-byte script itself.
SHA-256 needs TWO chained padded blocks; RIPEMD-160 must produce h_script.
This proof alone supplies only one of the two required signing capabilities.
TEXT
stop_node
started=$SECONDS
run "$QP" p2sh prove --redeem-script "$DEMO/redeem.hex" --position 0 \
  --output "$DEMO/new/signer0.qpm" <"$DEMO/custodian0/secret.hex"
NEW_PROVE0_SECONDS=$((SECONDS-started))

step 'New circuit: custodian 2 independently proves control at position 2'
cat <<'TEXT'
This is a new prover process with only x2 and the shared script. It does not
read proof 0, x0 or x1. There is no MPC, joint witness, or prover-to-prover message.
It proves the SAME script hash with a DIFFERENT position. The circuit's key
selection and distinctness constraints prevent relabeling one unchanged key.
TEXT
started=$SECONDS
run "$QP" p2sh prove --redeem-script "$DEMO/redeem.hex" --position 2 \
  --output "$DEMO/new/signer2.qpm" <"$DEMO/custodian2/secret.hex"
NEW_PROVE2_SECONDS=$((SECONDS-started))

step 'New auditor: obtain the on-chain hash, then verify the two independent proofs'
cat <<'TEXT'
The auditor extracts h_script from Core's actual P2SH scriptPubKey:
  OP_HASH160 PUSH20 <h_script> OP_EQUAL
The pair verifier receives ONLY the two proofs and that expected hash. It checks
both proofs, equal hashes matching the expected output, and distinct positions.
Core's UTXO query is separate evidence: QPM1 itself does not bind an outpoint,
amount, network, current UTXO state, challenge or nonce.
TEXT
start_node
core gettxout "$NEW_TX" "$NEW_VOUT" >"$DEMO/new/auditor-utxo.json"
ONCHAIN_SCRIPT=$(json scriptPubKey.hex <"$DEMO/new/auditor-utxo.json")
[[ $ONCHAIN_SCRIPT =~ ^a914[0-9a-f]{40}87$ ]] || die 'unexpected on-chain P2SH script'
EXPECTED_HASH=${ONCHAIN_SCRIPT:4:40}
[[ $EXPECTED_HASH == $(json new.hash <"$DEMO/fixture.json") ]] || die 'on-chain hash differs from the reference'
printf 'Auditor obtained h_script = %s from %s:%s\n' "$EXPECTED_HASH" "$NEW_TX" "$NEW_VOUT"
NEW_VERIFY=("$QP" p2sh verify --proof-a "$DEMO/new/signer0.qpm"
  --proof-b "$DEMO/new/signer2.qpm" --hash "$EXPECTED_HASH")
started=$SECONDS
run "${NEW_VERIFY[@]}" | tee "$DEMO/new/verified.json"
NEW_VERIFY_SECONDS=$((SECONDS-started))
[[ $(json valid <"$DEMO/new/verified.json") == true ]] || die 'independent pair did not verify'

step 'New workflow: try repeated positions, a wrong output hash, and proof relabeling'
printf 'Attack A: submit signer 0 twice. Positions must differ.\n'
expect_exit 65 "$QP" p2sh verify --proof-a "$DEMO/new/signer0.qpm" \
  --proof-b "$DEMO/new/signer0.qpm" --hash "$EXPECTED_HASH"
WRONG_HASH=$(node -e 'const b=Buffer.from(process.argv[1],"hex");b[0]^=1;console.log(b.toString("hex"))' "$EXPECTED_HASH")
printf '\nAttack B: substitute a different expected on-chain hash.\n'
expect_exit 65 "$QP" p2sh verify --proof-a "$DEMO/new/signer0.qpm" \
  --proof-b "$DEMO/new/signer2.qpm" --hash "$WRONG_HASH"
node - "$DEMO/new/signer0.qpm" "$DEMO/new/relabeled.qpm" <<'NODE'
const fs=require('node:fs'), p=fs.readFileSync(process.argv[2]);
if(p.subarray(0,4).toString()!=='QPM1' || p[56]!==0) throw Error('unexpected QPM1 fixture');
p[56]=1; // fixed QPM1 header: magic[4] || digest[32] || h[20] || position[1]
fs.writeFileSync(process.argv[3],p,{mode:0o600,flag:'wx'});
NODE
printf '\nAttack C: edit proof 0 to claim position 1. Hashes still match and positions\n'
printf '1 and 2 differ, but cryptographic verification must reject the changed input.\n'
expect_exit 65 "$QP" p2sh verify --proof-a "$DEMO/new/relabeled.qpm" \
  --proof-b "$DEMO/new/signer2.qpm" --hash "$EXPECTED_HASH"
CONSTRAINT_TEST=$(dirname -- "$QP")/p2sh-multisig-test
if [[ -x $CONSTRAINT_TEST ]]; then
  printf '\nAlso run raw compiled-circuit attacks, bypassing native witness validation:\n'
  run "$CONSTRAINT_TEST"
else
  printf '\nFor raw witness attacks, build and run the p2sh-multisig-test CMake target.\n'
fi

step 'New workflow: replay the unchanged valid pair and observe acceptance'
cat <<'TEXT'
QPM1 is a static knowledge proof. Unlike the original challenge workflow, it has
no nonce store or expiry. The same valid pair verifies again. This is intentional,
not a new proof of freshness. The verdict means sufficient signing capability;
it does not prove independent people, key generation, availability or willingness.
TEXT
run "${NEW_VERIFY[@]}" | tee "$DEMO/new/replayed.json"
[[ $(json valid <"$DEMO/new/replayed.json") == true ]] || die 'static pair unexpectedly failed'

step 'Compare what you just ran'
cat <<'TEXT'
                         ORIGINAL P2WPKH              NEW P2SH 2-of-3
Hash preimage            one 33-byte SEC key           complete 105-byte script
Public circuit instance  h_key                        (h_script, position)
Who generates            one holder                   each signer independently
Auditor needs            one proof + policy + Core    two proofs + expected hash
Built-in freshness       challenge/expiry/nonce       none; valid proofs replay
Current-funds verdict    valid_current after Core     not provided by QPM1

Original v1 also supports two separate P2WPKH programs in ONE proof when one
prover knows both keys. That is different from a hidden 2-of-3 redeem script
and two independently generated custodian proofs.

Proofs hide keys/scripts, not their public hash or disclosed statement. This
teaching script revealed public keys/scripts on purpose. It never printed a
private scalar. No proof was a Bitcoin signature and no custody output was spent.
TEXT
printf '\nObserved whole-CLI wall seconds (not the controlled circuit benchmark):\n'
printf '  Old prove: %s; old verify including Core/policy: %s\n' "$OLD_PROVE_SECONDS" "$OLD_VERIFY_SECONDS"
printf '  New prove 0: %s; new prove 2: %s; pair verify: %s\n' "$NEW_PROVE0_SECONDS" "$NEW_PROVE2_SECONDS" "$NEW_VERIFY_SECONDS"
node - "$DEMO" <<'NODE'
const fs=require('node:fs'),d=process.argv[2];
for(const f of ['old/proof.qpf','new/signer0.qpm','new/signer2.qpm'])
  console.log(`  ${f}: ${fs.statSync(`${d}/${f}`).size.toLocaleString('en-US')} envelope bytes`);
NODE
printf '\nRead the requests, JSON evidence, proof files and node logs in the artifact directory.\n'
printf 'Controlled circuit metrics: docs/performance.md and docs/public/benchmarks/.\n'
printf '\nPASS: original workflow, independent multisig workflow, and expected rejections.\n'
