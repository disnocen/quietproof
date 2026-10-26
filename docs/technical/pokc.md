---
title: PoKC v1 circuit
description: Complete circuit relation, one- and two-key family, scaling, witness construction, and validation notes.
outline: deep
---

<!--@include: ../../pokc.md-->

## Independent P2SH 2-of-3 extension

The original PoKC v1 relation and format above remain unchanged. The
[P2SH multisig relation](./p2sh-multisig.md) adds a separate proof family:
each custodian independently proves one scalar at one public position of a
private canonical 2-of-3 script. The circuit constrains all keys, distinctness,
position selection, and the complete 105-byte script HASH160. An auditor checks
two valid proofs with the expected script hash and distinct positions. See
the [CLI walkthrough](../guide/p2sh-multisig.md) and
[same-machine performance comparison](../performance.md#independent-p2sh-2-of-3).
