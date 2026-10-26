---
title: Independent P2SH 2-of-3 proofs
description: Exact relation, constraint enforcement, independent proving, and auditor verification for canonical P2SH multisig.
outline: deep
---

# Independent P2SH 2-of-3 proofs

QuietProof can prove key control at one position of a canonical Bitcoin P2SH
2-of-3 redeem script. Each prover needs only its own scalar and the common
redeem script. The auditor receives two independent proofs and supplies the
expected on-chain script hash. No private-key exchange, MPC, Co-SNARK, joint
witness, or communication between provers is required.

This is a separate `QPM1` proof family. Existing P2WPKH PoKC v1 requests,
proofs, circuits, policy checks, RPC workflows, and wire formats are unchanged.
The multisig extension establishes the cryptographic capability to produce two
valid signatures. It does not establish independent real-world custodians,
exclusive control, availability, willingness to sign, or current unspent funds.

## Exact NP relation

The public instance is `(h, i)`, where `h` is a 20-byte P2SH HASH160 and
`i` is a position in `{0, 1, 2}`. The private witness is
`(S, x, P0, P1, P2)` with the following relation:

```text
1 <= x < n
P0, P1, P2 are finite secp256k1 points, in canonical compressed SEC encoding
P0 != P1 and P0 != P2 and P1 != P2
S = 0x52 || 0x21 || SEC(P0) || 0x21 || SEC(P1) || 0x21 || SEC(P2) || 0x53 || 0xae
HASH160(S) = RIPEMD160(SHA256(S)) = h
SEC(xG) = SEC(Pi)
```

`G`, the curve, its base-field prime `p`, and its order `n` are the standard
secp256k1 parameters from the pinned Longfellow SDK. The order is
`fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141`.
The implementation constructs `S` directly from the private points; it does
not allocate a redundant, independently supplied script byte array in the
circuit. This is the same existential relation. Native prover input is the
105-byte script plus one 32-byte, big-endian scalar and a position.

The circuit has **22 public field inputs**: Longfellow's constant one,
20 encoded hash bytes, and one ordinary field element for `i`. Byte inputs use
the existing 8-bit `BitPlucker` representation, not an unconstrained field
encoding. All point coordinates, bit decompositions, selectors, scalar trace,
and both SHA block traces are private auxiliary witnesses. No public key or
redeem script is included in a proof envelope.

## Exact Bitcoin serialization

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | `52` | `OP_2` |
| 1 | `21` | Push exactly 33 bytes |
| 2–34 | `02/03` + 32-byte big-endian X | `P0` |
| 35 | `21` | Push exactly 33 bytes |
| 36–68 | `02/03` + 32-byte big-endian X | `P1` |
| 69 | `21` | Push exactly 33 bytes |
| 70–102 | `02/03` + 32-byte big-endian X | `P2` |
| 103 | `53` | `OP_3` |
| 104 | `ae` | `OP_CHECKMULTISIG` |

Ordering is preserved; keys are **not sorted**. Position is the zero-based
position in this script. Nonminimal push forms, uncompressed keys, other
thresholds, extra opcodes, and trailing bytes are outside this relation.
The corresponding on-chain scriptPubKey is `a9 14 <h:20 bytes> 87`
(`OP_HASH160 PUSH20 h OP_EQUAL`). This extension covers legacy P2SH;
it does not cover P2WSH, nested witness programs, or arbitrary scripts.

## Enforcement inside the unified circuit

`include/circuit/p2sh_multisig.h` implements a single relation with one scalar
multiplication and one complete script hash:

1. **Scalar and derived key.** `KeyOwnershipCircuit` enforces boolean scalar
   bits, exact scalar reconstruction, `x < n`, and `x * x_inverse = 1`.
   The SDK's complete projective formulas constrain the entire scalar
   multiplication trace and finite affine normalization. Canonical coordinate
   bits constrain the derived compressed SEC bytes.
2. **All script keys.** Each private point satisfies `y² = x³ + 7` and has
   canonical coordinate bits strictly below `p`. Affine representation excludes
   the point at infinity. Secp256k1 has cofactor one, so these finite curve
   points are in the prime-order group. The SEC prefix is constructed as
   `2 + parity(y)`, with canonical big-endian X bytes.
3. **Position and one-hot selection.** Three private selectors `s0, s1, s2`
   are individually constrained to bits. The circuit asserts
   `s0 + s1 + s2 = 1` and `i = s1 + 2*s2`. Thus the public `i` cannot be
   outside `{0,1,2}` and cannot disagree with the selected script position.
   For each of all 33 SEC bytes, it asserts
   `SEC(xG)[b] = sum_j sj * SEC(Pj)[b]`.
4. **Distinctness.** For each of the three pairs, the circuit rejects equality
   of both canonical X bits and Y parity. These are exactly compressed-SEC
   equality tests, including the prefix; native duplicate detection is only
   an early error check.
5. **Complete HASH160.** The circuit builds all 105 script bytes with constant
   opcodes and direct connections to the constrained key bits. SHA-256 uses
   two chained `FlatSHA256Circuit` blocks. Padding is fixed to `80`, 14 zero
   bytes, and the 8-byte big-endian length `0000000000000348` (840 bits).
   The final constrained SHA state feeds the existing fixed-32-byte RIPEMD-160
   gadget. Every result byte equals the corresponding public hash byte.

Native decoding, selector construction, curve checks and hashing in
`p2sh_multisig_witness.h` supply advice and useful early errors. None replaces
these circuit constraints.

## Why two independent proofs suffice

The auditor verifies both proofs, requires both public hashes to equal its
expected P2SH hash, and requires distinct positions. Under script-hash binding
and proof knowledge soundness, the proofs attest to scalars for two different
positions in the same script. The circuit's pairwise-distinctness requirement
makes those two SEC keys different. Those scalars provide enough signing
capability for that 2-of-3 script.

A proof at position 0 cannot be relabeled as position 1: the public position
is both a circuit input and bound into the Fiat–Shamir transcript. Copying
one key into two positions also fails because distinctness is constrained.
The auditor does not need to see the script or either public key.

This is computational script binding, not an injective hash. Against a fixed,
trusted on-chain hash, alternate-script attacks require a suitable HASH160
second preimage. If the adversary chooses both scripts and their hash, generic
collision resistance is at most 80 bits. These are HASH160 assumptions in
addition to the SDK proof system and discrete-log assumptions.

Distinct keys do **not** prove independent key generation. For example, a
holder of `x` also knows `n-x`, whose public key is `-xG`; the two SEC keys are
distinct. One seed may also derive many keys. The one-key attack tests concern
reusing the same scalar against other positions of a fixed independently
provisioned script. No circuit for this relation can establish custodian
identity or exclude algebraically related secrets. Capability remains the
claim even when one person knows multiple signing scalars.

## C++ API

Include `pokc/p2sh_multisig.h` and link the existing core-only
`LongfellowZKQuietProof::quietproof` target:

```cpp
proofs::P2shSecret my_secret;    // exactly 32 bytes, big-endian, from protected storage
proofs::P2shScript script;      // exactly 105 bytes, private to custodians
proofs::P2shMultisigProof mine;
bool generated = proofs::P2shProve(my_secret, script, 0, &mine);
// Transfer only the encoded proof to the auditor.
std::vector<uint8_t> wire;
bool encoded = generated && proofs::EncodeP2shProof(mine, &wire);
```

Each custodian invokes this independently with its own position and scalar.
Auditor code, after decoding both envelopes:

```cpp
bool sufficient = proofs::P2shVerifyPair(first, second, expected_on_chain_hash);
```

`P2shVerify` verifies a single relation. `P2shVerifyPair` additionally checks
hash equality against the auditor-supplied hash and distinct positions. It
returns false on any failure. The public API never accepts serialized
prover-supplied circuits: the verifier builds its pinned circuit and checks
the expected circuit digest. `EncodeP2shProof` and `DecodeP2shProof` are
serialization helpers, not cryptographic verification.

## Wire format and compatibility

`QPM1` envelopes have a fixed 61-byte header:

```text
"QPM1" [4] || circuit_digest [32] || h [20] || i [1]
           || proof_length [4, little-endian] || proof [proof_length]
```

The format fixes version 1, rate 4, and 128 queries. The digest is the tagged
hash `QuietProof/P2SH-2of3/circuit/v1` of the SDK circuit digest (including the
fixed version/rate/query tuple). The transcript seed is the tagged hash
`QuietProof/P2SH-2of3/proof/v1` of `circuit_digest || h || i`.
Parsers reject wrong magic, unknown circuit identity, invalid positions,
empty proofs, lengths over 128 MiB, and trailing bytes. Verifiers also require
complete consumption of the internal Longfellow proof.

P2WPKH v1 `QPE1`/request formats and their challenge/replay policies are unchanged.
`QPM1` is a static knowledge attestation for exactly `(h,i)`: it has **no
challenge, expiration, nonce-consumption policy, RPC discovery, UTXO lookup,
network identifier, or freshness guarantee**. A proof is replayable. The
`p2sh verify` command establishes key capability only, not a `valid_current`
funds authorization. The auditor must obtain the expected hash from a trusted
on-chain scriptPubKey and apply any external freshness or business policy.
Adding a challenge-bound multisig relation/protocol is outside this format.

## Reproduction, adversarial tests and benchmarks

See the [multisig walkthrough](../guide/p2sh-multisig.md) for working CLI
commands and the [performance page](../performance.md#independent-p2sh-2-of-3)
for measured results and exact reproduction commands.

`p2sh-multisig-test` evaluates the **compiled circuit** with raw mutated witness
vectors, bypassing the native builder. Tests include every position, every
same-scalar/other-position attack, all three duplicate-key pairs, malformed
one-hot vectors, invalid public positions, nonboolean/noncanonical coordinate
advice, off-curve points, invalid scalar advice, altered complete scripts,
wrong public hashes, and tampered SHA schedules/chaining states.
Consistently rehashed off-curve keys, coordinate aliases `x+p`, the scalar
alias `n+1`, and altered SHA padding/lengths isolate those constraints from
otherwise stale advice. Opposite-parity keys with the same X and scalar
`n-1` are positive boundary cases.
`p2sh-multisig-proof-test` generates three independent real proofs, verifies all
three valid pairs, rejects repeated positions, wrong expected hashes,
tampered statements, proofs and circuit identities, and attempts an actual
low-level second-position proof using only the first key. It also measures
the original one-key PoKC API on the same machine.

`p2sh-bitcoin-reference-test` independently cross-checks SEC derivation against
Node/OpenSSL and canonical script serialization and HASH160 against pinned
`bitcoinjs-lib` 7.0.1. It requires `npm ci`; it reports an explicit skip if
that reference dependency is unavailable. The native CI job installs it and
runs the cross-check and separate-process CLI demonstration explicitly.

## Security and operational limits

The proof system, circuit composition, Fiat–Shamir/domain separation, secure
prover randomness, standard secp256k1 assumptions, and HASH160 binding are
trusted. This implementation is experimental and has not received an
independent cryptographic audit. Constraints and adversarial tests are
engineering evidence, not a formal knowledge-soundness proof of the SDK.

The public hash and positions are disclosed and linkable. The proof hides
scalars, SEC keys, and the script, but cannot hide them if the script has
already appeared in a Bitcoin spend or is otherwise known. Arbitrary
scripts, noncompressed keys, and duplicate-key scripts are intentionally
unsupported. These attestations are not signatures and cannot be broadcast as
transactions. They do not lock funds or prove exclusive control, legal title,
liabilities, identity, custodian independence, liveness, or willingness.

The CLI accepts the scalar only through protected stdin, disables terminal
echo using the existing helper, and writes proof files owner-only without
replacing existing files. The script file is also sensitive and must be
protected locally. Owned CLI input buffers are cleared on the normal path;
SDK witnesses, library copies, allocator state, swap and the OS may retain
secret material. Complete memory erasure and constant-time witness generation
are not guaranteed. The demo stores **disposable** secret fixtures in an
owner-only temporary directory; production keys should use protected storage.

The documentation website is built from this repository's `docs/` tree.
Publishing these changes at the Plan ₿ domain requires the site's maintainers
to deploy them; pushing this feature branch to a fork does not update the
upstream website.

## Validation record (2026-10-26)

The Release build used pinned SDK
`d2b0fc515f8663e38c79a28e8900ce8438e0106e` and upstream base
`821ae6d57216c76a6c96d3c55ac160a9c8d0c5f3` on Apple M4 Pro/macOS arm64.
The implementation is on the fork branch `feature/independent-p2sh-2of3`.

- The three new CTest entries passed: compiled adversarial constraints,
  independent real proofs / all three pairs / attempted one-key forgery, and
  the independent Bitcoin serialization/hash reference.
- Original `pokc-test` passed, including the one/two-key circuit family and
  its real proof gate. Installed-package and offline/RPC compatibility checks
  passed.
- The complete Release suite had 20 passes, one failure, and one explicitly
  skipped opt-in live-Core integration test. The failure was
  `quietproof-rpc-test: invalid URL accepted`, using the host's system libcurl
  8.7.1. The same test failed with the same message on an untouched worktree of
  the upstream base and the same SDK/toolchain. It remains an existing RPC
  portability/validation issue; this extension does not change those files.
- Clang's static analyzer reported no diagnostics for the new proof-test
  translation unit or the CLI. This is narrower than the optional complete
  static-analysis script, which also requires cppcheck and shellcheck.
- The separate-process CLI demonstration passed with three random keypairs,
  independent proofs at positions 0 and 2, successful pair verification, and
  rejection of a repeated position. All seven documentation tests and the
  VitePress production build passed.

Benchmark observations and reproduction commands are on the
[performance page](../performance.md#independent-p2sh-2-of-3). Live Bitcoin Core
integration and the optional Sage runtime were not enabled for this run;
deterministic Sage vectors remained part of the normal suite.
