---
title: Prove P2SH multisig key control
description: Generate independent custodian proofs and verify a 2-of-3 pair.
outline: deep
---

# Prove P2SH multisig key control

This workflow proves capability for a canonical legacy P2SH 2-of-3 script.
Each custodian has one private key and the common redeem script. The auditor
gets only the proofs, the public positions, and the public P2SH hash. See the
[exact relation and security limits](../technical/p2sh-multisig.md).

## Build and generate a disposable demonstration

For a narrated comparison with the original P2WPKH workflow, run
`bash scripts/walkthrough.sh --bitcoin-bin /path/to/bitcoin/bin` after building
the RPC-enabled CLI and running `npm ci`. It pauses for Enter between steps;
the [interactive walkthrough instructions](./getting-started.md#compare-both-workflows-interactively)
describe its isolated regtest setup, proof checks and replay demonstrations.

Build QuietProof using the [existing SDK setup](./getting-started.md). From
the repository root, with the pinned sibling `vite-theme` checkout required
by the existing documentation package:

```sh
npm ci
scripts/run_p2sh_demo.sh /absolute/path/to/build/quietproof
```

The script invokes three separate Node/OpenSSL key-generation processes,
creating a random keypair in each custodian directory. Assembly reads only
the three public files and uses `bitcoinjs-lib` to create the canonical script
and its P2SH hash. Two separate CLI prover processes each receive only one
scalar on stdin and the common script file. The auditor verifies the pair
and checks that repeating one proof is rejected. Successful verification
prints `{"valid":true,"hash":"..."}`. The script prints the owner-only
temporary directory holding its artifacts, including disposable secrets;
remove that directory after review. These keys must never hold real funds.

## Generate two independent proofs

For an existing script, provide an owner-only `redeem.hex` file containing
exactly 210 hexadecimal characters (105 script bytes), optionally followed
by one newline. Key order is retained; positions are zero-based. Each
custodian runs its own command on its own machine:

```sh
# Custodian holding the scalar for the first key in the script:
build/quietproof p2sh prove --redeem-script redeem.hex --position 0 --output signer0.qpm
# Custodian holding the scalar for the third key in the same script:
build/quietproof p2sh prove --redeem-script redeem.hex --position 2 --output signer2.qpm
```

Each command prompts for its own 64-character hexadecimal private scalar;
terminal echo is disabled. For automated use, supply that one line through
protected stdin. Do not put production secrets in argv, environment variables,
shell history, demo files, or chat. No other custodian's scalar is needed.
Proof creation prints elapsed progress to stderr and result JSON to stdout.
Outputs are created with mode `0600` and an existing destination is rejected.
A failed key/script/position match produces no proof.

## Verify the pair

Obtain the exact 20-byte hash from the trusted on-chain P2SH scriptPubKey
`a9 14 <20-byte hash> 87`. Transfer only `signer0.qpm` and `signer2.qpm` to the
auditor, then run:

```sh
# Assign the independently obtained, 40-character hexadecimal on-chain hash.
# In the disposable demo only: HASH=$(cat "$DEMO/hash.hex")
build/quietproof p2sh verify --proof-a signer0.qpm --proof-b signer2.qpm --hash "$HASH"
```

Exit 0 and `"valid":true` mean both proofs verified, both hashes matched the
expected hash, and the positions differed. All pairs `(0,1)`, `(0,2)`, `(1,2)`
are supported. A repeated position, mismatch, malformed proof, or invalid
proof is rejected. The expected hash is mandatory; a prover-selected hash
alone is insufficient to bind an attestation to the auditor's intended output.
The disposable demonstration's hash comes from its local reference script;
it is not a claim that the demo output has been funded on chain.

The auditor does not receive the redeem script or keys. These static proofs
are replayable and do not prove current UTXO state, freshness, identity, or
willingness to sign. This command is distinct from the existing challenge-bound
P2WPKH `verify` command and its `valid_current` result.

## Run the checks

After the normal CMake build and `npm ci`:

```sh
ctest --test-dir build --output-on-failure -R '^p2sh-'
node tests/quietproof/p2sh_reference.mjs build/p2sh-multisig-test
```

The proof test writes `build/p2sh-benchmark.csv`. It runs real proof generation
and verification and may use substantial CPU and memory. All examples assume
the actual build directory is `build`; replace that path consistently if you
configured CMake elsewhere. The [performance page](../performance.md#independent-p2sh-2-of-3)
describes the timing method and measurements.
