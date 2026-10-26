// Cross-check native SEC serialization and HASH160 against bitcoinjs-lib.
import assert from 'node:assert/strict';
import { createECDH } from 'node:crypto';
import { spawnSync } from 'node:child_process';
let bitcoin;
try { bitcoin = await import('bitcoinjs-lib'); }
catch (error) {
  if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error;
  console.error('SKIP: run npm ci for the pinned independent Bitcoin reference');
  process.exit(77);
}
const { payments } = bitcoin;
const result = spawnSync(process.argv[2], ['--vector'], { encoding: 'utf8' });
assert.equal(result.status, 0, result.stderr);
const native = JSON.parse(result.stdout);
const pubkeys = [1, 2, 3].map(scalar => {
  const key = createECDH('secp256k1');
  const secret = Buffer.alloc(32); secret[31] = scalar; key.setPrivateKey(secret);
  return Uint8Array.from(key.getPublicKey(undefined, 'compressed'));
});
assert.deepEqual(native.keys, pubkeys.map(k => Buffer.from(k).toString('hex')));
const redeem = payments.p2ms({ m: 2, pubkeys });
const p2sh = payments.p2sh({ redeem });
assert.equal(redeem.output.length, 105);
assert.equal(native.script, Buffer.from(redeem.output).toString('hex'));
assert.equal(native.hash, Buffer.from(p2sh.hash).toString('hex'));
console.log(JSON.stringify({ implementation: 'bitcoinjs-lib 7.0.1', ...native }));
