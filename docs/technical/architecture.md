---
title: Technical architecture
description: How QuietProof separates the PoKC relation, canonical attestation, verifier policy, and Bitcoin evidence.
---

# Technical architecture

QuietProof is organized in three layers. Keeping them separate is a security property as well as a documentation aid.

```text
APPLICATION
custody · audit · OTC · credit · collaborative protocols
                         │
                         ▼
ATTESTATION AND POLICY
canonical request · transcript · expiry · nonce · chain evidence
                         │
                         ▼
CRYPTOGRAPHIC PRIMITIVE
PoKC: ZK knowledge of one or two P2WPKH spend keys
```

## PoKC relation

For each distinct public 20-byte witness program `h`, the prover privately supplies a scalar `x` and proves:

```text
x ∈ [1, n−1]
P = xG
sec = SEC_compressed(P)
h = RIPEMD160(SHA256(sec))
```

The circuit constrains scalar validity, elliptic-curve multiplication, finite normalized coordinates, canonical compressed SEC encoding, fixed SHA-256, fixed RIPEMD-160, and equality with the public program.

The compressed public key is internal witness data, not a public output.

## Exact circuit family

V1 compiles one-key and two-key circuit shapes. There is no inactive padded relation. The canonical count of distinct programs selects the expected circuit identity, and mismatched circuit version, digest, Ligero rate, or query count is rejected before proof acceptance.

| Distinct programs | Public inputs | Private inputs | Quadratic terms | Serialized circuit |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 21 | 3,010 | 2,067,522 | 24,876,346 B |
| 2 | 41 | 6,020 | 4,133,092 | 49,663,186 B |

[Read the complete PoKC circuit documentation →](/technical/pokc)

## Canonical statement and envelope

The public statement binds network, verifier, purpose, message, timestamps, a 32-byte nonce, one to 16 output claims, and optional application bindings. The proof envelope binds the exact statement bytes, circuit digest, circuit version, Ligero rate, query count, and proof bytes.

The Fiat–Shamir transcript seed uses a tagged hash over the statement digest, circuit identity, and proof parameters. Unknown versions, unsupported parameters, malformed lengths, trailing bytes, and non-canonical fields are rejected.

[Read the normative QuietProof v1 protocol →](/technical/protocol)

## Policy and chain evidence

`PoKCVerifyProof(...)` checks only the zero-knowledge relation. Applications should normally use `VerifyQuietProof(...)`, which applies policy, proof verification, chain evidence, confirmation and value thresholds, optional bridge authorization, and atomic nonce consumption.

The chain provider is independently selected by the verifier. The bundled provider checks a stable current Bitcoin Core tip; authenticated historical state remains an external provider responsibility.

## Assurance material

The repository includes:

- deterministic protocol and circuit fixtures;
- positive and negative native tests;
- real one- and two-key proof round trips;
- an independent Sage 10.6 executable mathematical oracle;
- canonical encoding and circuit-digest anchors; and
- a claim-by-claim security review map.

These are evidence for review, not a substitute for an independent cryptographic and protocol audit.

## Independent P2SH multisig family

The [P2SH 2-of-3 circuit](/technical/p2sh-multisig) adds one independent key
relation against a hidden script hash and a public script position. Each
custodian invokes `P2shProve` separately; `P2shVerifyPair` verifies two proofs
with distinct positions and the auditor's expected hash. This is one unified
circuit per signer, with one scalar multiplication and all three private script
points, rather than three key-knowledge relations or joint generation.

`QPM1` serialization and transcript domains keep this family separate from
P2WPKH v1. The circuit handles all key validity, selection, distinctness, script
construction and HASH160 constraints. The pair verifier establishes static
spending capability only. Challenge policies, replay prevention, RPC discovery,
and current-funds authorization remain features of the existing P2WPKH v1
workflow and are not implied for `QPM1`.
