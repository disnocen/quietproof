---
title: Security claim matrix
description: The enforcing component, evidence, and residual limitation for each QuietProof v1 claim.
outline: deep
---

# QuietProof v1 security-claim matrix

This matrix is the review map for the current QuietProof implementation.  It
separates a statement that is enforced by the arithmetic circuit from one
enforced by the envelope, verifier policy, or an external Bitcoin/bridge
system.  A successful proof is **not** by itself proof that an output exists,
is unspent, is locked, or is a proof of solvency.

The named tests are in `tests/quietproof/` unless noted otherwise.  A negative
test means an expected rejection, not merely a host-side precondition.

| Claim and attacker strategy | Trusted/enforcing component | Source constraint or check | Positive / negative evidence | Residual limitation |
| --- | --- | --- | --- | --- |
| The prover knows a nonzero scalar in `[1,n-1]`; try `0`, `n`, or non-bit advice. | Arithmetic circuit and its soundness assumptions. | `Secp256k1EcGadget::assert_canonical_scalar` and `assert_nonzero_scalar`; `KeyOwnershipCircuit::derive`. | `key_ownership_test`: valid scalar; zero/order/non-bit mutations. Sage oracle: primality, group order, negation, and `-1,0,n,n+1` rejection; `pokc_sage_vector_test` consumes those boundaries directly. | Soundness depends on the proof system and field/CRT assumptions, not an independent audit. |
| The hidden point is `P=xG`, finite, and on the curve; substitute a point or infinity. | Arithmetic circuit. | `Secp256k1EcGadget::scalar_mult`, `Secp256k1Affine::assert_normalized`, and `KeyOwnershipCircuit::derive`. | `ec_gadget_test`, `key_ownership_test`: altered scalar-multiplication/point witness rejected. | The point is deliberately not a public output. |
| Coordinates and SEC encoding are canonical; use values equal only modulo `p`, a wrong prefix, parity, or byte order. | Arithmetic circuit. | `Secp256k1Encoding::assert_canonical` / `Secp256k1Encoding::compressed`; `KeyOwnershipCircuit::derive`. | `ec_gadget_test`, `key_ownership_test`: `p-1,p,p+1`, parity, prefix and reversed-byte cases. | Canonicality applies to the relation, not to arbitrary external SEC parsers. |
| The program equals `RIPEMD160(SHA256(SEC_compressed(xG)))`; alter a SEC, SHA, RIPEMD, or public-program byte. | Arithmetic circuit. | `CompressedKeySha256Circuit::derive`, `Ripemd160Fixed32::derive`, `Hash160Circuit::assert_hash160`, `PoKCCircuitV1::assert_program`. | `compressed_key_sha256_test`, `ripemd160_test`, `pokc_test`: byte and digest/program mutations. Sage oracle: independent curve/SEC and local hash-compression vectors cross-checked with Python; `pokc_sage_vector_test` checks every Sage result natively and through the circuit. | SHA/RIPEMD design security is assumed; no digest or SEC byte is exposed by the proof. |
| A proof uses exactly the selected one- or two-claim circuit; add inactive relations or swap the circuit. | Circuit construction and proof identity check. | `PoKCBuildCircuit`, `PoKCMultiCircuitV1::assert_programs`, `PoKCCircuitDigest`, `PoKCProofIdentityMatches`, `PoKCVerifyProof`. | `pokc_test`: one/two-claim proof, duplicate-program and digest/version mutations. | v1 intentionally supports at most two distinct programs. |
| Public statement fields cannot be replayed across verifier, purpose, network, nonce, expiry, circuit, or proof parameters. | Canonical statement/envelope, verifier policy, and durable nonce store. | `QuietProofStatementValid`, `Encode/DecodeQuietProofStatement`, `PoKCTranscriptSeed`, `QuietProofCheckPolicy`, `QuietProofConsumeNonce`, `QuietProofConsumeNonceFile`. | `protocol_test`: canonical round-trip and expiry/replay cases; `integration_test`: durable replay and insecure-permission rejection. | Distributed deployments must provide an equivalently atomic shared nonce store. |
| Parser inputs are bounded and canonical; use truncation, length overflow, bad UTF-8, reserved values, or trailing bytes. | Local parser implementation. | `QuietProofReader::{bytes,text,u8,u16,u32,u64}`, `DecodeQuietProofStatement`, `DecodeQuietProofEnvelope`. | `protocol_test`: statement/envelope truncation, malformed lengths/UTF-8/network/version cases. | Parser testing cannot establish absence of all implementation defects. |
| A claimed outpoint has the exact P2WPKH program and amount at the selected snapshot/current tip; race, substitute script/value/network, or report spent. | Independently selected chain provider. | `QuietProofChainProvider::Lookup`, `QuietProofIsP2wpkh`, `VerifyQuietProof`, `BitcoinCoreCurrentTipProvider`. | `integration_test`: exact decimal amounts, all network mappings, wrong node network, tip race, null, script/amount and confirmation cases. | The bundled provider is current-tip only. A null `gettxout` is inconclusive; authenticated historical state remains an external provider responsibility. |
| Total claimed value is the checked sum of accepted chain evidence; overflow or claim an insufficient total. | Verifier implementation and chain provider. | `VerifyQuietProof` checked `uint64_t` addition and `minimum_total_sats` comparison. | `integration_test`: multi-claim totals, threshold and overflow/inconclusive cases. | This is not a liability proof and therefore not solvency. |
| A bridge claim has a destination/asset/lock binding and cannot mint without bridge authorization. | Bridge operator/destination-chain callback. | `QuietProofStatementValid` bridge validation and `QuietProofVerifierConfig::bridge_authorized`. | `protocol_test` bridge encoding/mutations; `integration_test` accepted/rejected bridge callback. | QuietProof does not prove a Bitcoin lock, custody, destination finality, or one-time mint by itself. |
| The BIP-322 companion has the documented message binding but is not a standard BIP-322 signature. | Companion-format consumers. | `QuietProofBip322MessageHash` and statement `bip322_message_hash` binding. | `protocol_test`: tagged-message and companion binding cases. | An unmodified BIP-322 script verifier must reject/does not understand a PoKC proof. |

## Normative coverage and review boundaries

The MUST/REJECT requirements in
[the v1 specification](../spec/quietproof-v1.md) map to
the rows above: sections 1 and 3 to the first four rows, sections 4 through 6
to the circuit-ID/replay/parser/bridge rows, section 7 to the chain and total
rows, and section 8 to the corresponding negative-test corpus. The
implementation intentionally performs host-side validation in addition to
the circuit.  Those validations are defense in depth only; the scalar, point,
canonical SEC, SHA-256, RIPEMD-160, and public-program relation are circuit
constraints.

Before relying on a deployment, an independent reviewer must assess the proof
system, circuit implementation, parameter generation, nonce-store atomicity,
Bitcoin provider/snapshot/finality policy, and any bridge lock and mint
system.  No row in this document turns those external assumptions into a
cryptographic guarantee.

## Independent P2SH 2-of-3 extension

The [multisig specification](/technical/p2sh-multisig) describes the separate
`QPM1` relation. The P2WPKH v1 challenge/replay/evidence policies above are not
part of this static multisig format.

| Claim / attack | Enforcement | Evidence | Limit |
| --- | --- | --- | --- |
| A valid scalar derives exactly the selected script key. | Reused `KeyOwnershipCircuit`; bytewise equality to the circuit-selected compressed key. | `p2sh_multisig_test`: actual compiled-circuit evaluation, six same-scalar/other-position attempts; scalar/trace mutation; `n+1` alias; real low-level forged-proof attempt. | Discrete-log and proof-system knowledge-soundness assumptions. |
| The public position is in range and bound to selection. | Bit selectors, one-hot sum, `i = s1 + 2*s2`, 33 selected-byte equalities. | Invalid field/byte positions, non-bit/non-one-hot selectors, relabeled real proofs. | Position is disclosed and linkable. |
| All keys are valid and pairwise distinct. | Curve equations; canonical coordinates; three compressed-key inequality constraints. | Consistently encoded off-curve point; noncanonical coordinate alias; all duplicate pairs; opposite-parity valid pair. | Different SEC keys do not imply different people or unrelated secrets. |
| The exact script hashes to the public P2SH hash. | Circuit-built 105-byte serialization, two chained SHA blocks, fixed padding/length, RIPEMD-160, public-byte equality. | Rehashed altered scripts; schedules, chaining states, alternate padding and lengths; independent bitcoinjs-lib/OpenSSL cross-check. | HASH160 binding is computational; chosen collisions have a generic 80-bit bound. |
| Two proofs establish sufficient capability for the intended hash. | `P2shVerifyPair`: both proofs valid, expected hash equal, positions different. | Real proofs for all three valid pairs, repeated positions and mismatched/tampered hashes rejected. | Auditor must obtain the expected hash independently; no current UTXO or freshness check. |
| Proof inputs, family and wire format are bound. | Pinned circuit digest, separate transcript domains, public circuit inputs, bounded strict `QPM1` parser. | Tampered proof/statement/digest, truncated/oversized-length/trailing encodings, real proof relabeling. | Static proofs are intentionally replayable; no challenge or custodian identity binding. |
