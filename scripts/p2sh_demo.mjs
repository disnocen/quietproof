#!/usr/bin/env node
// Disposable demo tooling. Each keygen invocation creates exactly one keypair.
import { createECDH } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { payments } from 'bitcoinjs-lib';

const [command, directory] = process.argv.slice(2);
const write = (path, value) => writeFileSync(path, value + '\n', { mode: 0o600, flag: 'wx' });
if (!directory || !['keygen', 'assemble'].includes(command)) {
  console.error('usage: node scripts/p2sh_demo.mjs keygen|assemble DIRECTORY');
  process.exit(64);
}
if (command === 'keygen') {
  mkdirSync(directory, { mode: 0o700 });
  const key = createECDH('secp256k1');
  key.generateKeys();
  const secret = key.getPrivateKey();
  write(join(directory, 'secret.hex'), secret.toString('hex').padStart(64, '0'));
  secret.fill(0);
  write(join(directory, 'public.hex'), key.getPublicKey('hex', 'compressed'));
} else {
  // Assembly reads only public keys. Ordering is retained, never sorted.
  const pubkeys = [0, 1, 2].map(i => Uint8Array.from(Buffer.from(
    readFileSync(join(directory, `custodian${i}`, 'public.hex'), 'utf8').trim(), 'hex')));
  const redeem = payments.p2ms({ m: 2, pubkeys });
  const p2sh = payments.p2sh({ redeem });
  write(join(directory, 'redeem.hex'), Buffer.from(redeem.output).toString('hex'));
  write(join(directory, 'hash.hex'), Buffer.from(p2sh.hash).toString('hex'));
  console.log(JSON.stringify({ hash: Buffer.from(p2sh.hash).toString('hex'), script_bytes: redeem.output.length }));
}
