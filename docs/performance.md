---
title: Performance and portability
description: Current proof family, measurement method, resource boundary, and supported platform.
---

# QuietProof performance and portability

PoKC v1 has two fixed native circuit shapes: one or two distinct P2WPKH
witness programs.  A statement may contain up to 16 public claims, but claims
sharing a program reuse its relation; more than two distinct programs are
rejected before circuit allocation.  Four relations exceed Longfellow's CRT
block-encoding guard and are deliberately unsupported.

## Reproducing native metrics

Run `make pokc-test` twice on an otherwise idle machine.  Each run writes
`tests/results/native_pokc_metrics.csv` with one row per real
prove/verify round:

```
target,circuit,build_ms,prove_ms,verify_ms,proof_bytes,public_inputs,total_inputs,quad_terms,crt_block_enc
```

The values are descriptive, not timing thresholds.  Record the commit SHA,
compiler/version and flags, CPU/OS, elapsed wall time and peak resident memory
next to a release candidate. The deterministic columns (input
and term counts, CRT block encoding) must agree across the two runs; the
timing columns and proof sizes are expected to vary. The circuit digest is independently
checked by `pokc_test`, and changing a circuit shape changes the digest.

## Current support boundary

The project requires C++20. The original release measurements target a native
64-bit Linux/x86_64 host using hardened flags (`-O3 -fstack-protector-all
-D_FORTIFY_SOURCE=2 -fno-strict-overflow`). The checked envelope ceiling is
128 MiB, selected to bound allocation while admitting the supported proof
family.  32-bit and wasm builds are not release-supported QuietProof targets in
this repository; operators must not infer portability from the presence of a
generic wasm build target.  Re-run the compatibility and metric checks before
accepting any parameter, compiler, or circuit-digest change.

## Independent P2SH 2-of-3

The multisig circuit adds a hidden canonical 105-byte script and a public key
position to one key-ownership relation. It has 22 public inputs, 6,027 private
inputs, 2,353,876 quadratic terms, and CRT block encoding 2,359,904, below the
SDK's 4,194,304 limit. Its serialized circuit is 28,312,946 bytes versus
24,876,346 bytes for the original one-key PoKC circuit (about 13.8% larger).
Two independent proofs use this same circuit twice; there is no joint circuit.

Measurements below are from 2026-10-26 on an Apple M4 Pro, 48 GiB RAM,
macOS/Darwin 25.6.0 arm64, AppleClang 21.0.0.21000334, C++20, Release
`-O3 -DNDEBUG`. The SDK is pinned at
`d2b0fc515f8663e38c79a28e8900ce8438e0106e`; the upstream baseline is
`821ae6d57216c76a6c96d3c55ac160a9c8d0c5f3`.
These are same-machine measurements of the implemented API, separate from
the older Linux measurements in the README.

| Relation / position | Prove API | Verify API | Raw proof | Serialized circuit |
| --- | ---: | ---: | ---: | ---: |
| Original one-key PoKC v1 | 15.1312 s | 9.92679 s | 46,880,140 B | 24,876,346 B |
| P2SH signer 0 | 22.9731 s | 17.6262 s | 53,054,668 B | 28,312,946 B |
| P2SH signer 1 | 21.8750 s | 18.0050 s | 53,054,316 B | 28,312,946 B |
| P2SH signer 2 | 21.8499 s | 18.3666 s | 53,055,084 B | 28,312,946 B |

The three multisig observations average **22.23 s proving, 18.00 s verification,
and 50.60 MiB per raw proof**, versus **15.13 s, 9.93 s and 44.71 MiB** for the
original single-key API. Raw proof bytes increase about 13.2%. Two independent
multisig proofs transfer approximately 101.19 MiB, plus two 61-byte headers.
The [recorded CSV](/benchmarks/p2sh-2026-10-26.csv) contains all observations.

The block encoding grows from 2,070,533 to 2,359,904. It crosses the SDK CRT
convolution's power-of-two padding boundary: its transform pads to 4,194,304
instead of 2,097,152. CPU cost therefore need not scale in proportion to the
13.8% increase in serialized circuit size. This version prioritizes constraint
coverage over reducing that transform size.

Times are wall-clock, one call at a time. Proving includes native witness
preparation, circuit compilation, commitment, proving and serialization.
Verification includes building the pinned circuit, parsing the proof and
cryptographic verification, with the static expected-circuit-digest cache warm
from proving in the same process. The first prover call in each family also
constructs the identity circuit; later multisig prover samples reuse its digest.
The three multisig rows are one observation at each position, not a statistical
performance study; the baseline is one original `PoKCProveKeys<1>` /
`PoKCVerifyProof` observation. Prover randomness causes small proof-size
variation. A `QPM1` envelope adds exactly 61 bytes to the raw proof. No RPC,
UTXO lookup, challenge creation or policy verification is included.

Reproduce from a configured Release build, after `npm ci`:

```sh
cmake --build build --target p2sh-multisig-test --parallel 2
ctest --test-dir build --output-on-failure -R '^p2sh-multisig-proof-test$'
cat build/p2sh-benchmark.csv
node tests/quietproof/p2sh_reference.mjs build/p2sh-multisig-test
scripts/run_p2sh_demo.sh build/quietproof
```

The proof test regenerates three separate proofs, exercises all three auditor
pairs and the adversarial proof path, then measures the original one-key API.
Run it on an otherwise idle host for comparable timing. Fresh-process
verification pays the extra circuit-identity construction cost. An auditor
checks two full proofs, so CPU cost and transferred proof bytes are roughly
twice a single multisig proof; key generation remains completely independent.
The comparison is to one original key-ownership relation, not a claim that one
P2WPKH key and two multisig signing keys express the same authority policy.
