import test from 'node:test';
import assert from 'node:assert/strict';
import jpeg from 'jpeg-js';
import { PNG } from 'pngjs';
import { canonicalize, digest, PhotoRejected, MAX_BYTES } from './codec.mjs';

export function fixture(extension = 'jpg', width = 16, height = 12) {
  const data = Buffer.alloc(width * height * 4, 127);
  for (let i = 3; i < data.length; i += 4) data[i] = 255;
  return extension === 'jpg' ? jpeg.encode({ width, height, data }, 80).data :
    PNG.sync.write({ width, height, data }, { colorType: 6 });
}
// CRC helper is test-only, including forged IHDR / text / animation chunks.
export function chunk(type, data) {
  const block = Buffer.alloc(data.length + 12);
  block.writeUInt32BE(data.length); block.write(type, 4, 4, 'ascii'); data.copy(block, 8);
  let crc = 0xffffffff;
  for (const byte of block.subarray(4, -4)) {
    crc ^= byte;
    for (let i = 0; i < 8; i++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  block.writeUInt32BE((crc ^ 0xffffffff) >>> 0, block.length - 4);
  return block;
}
for (const extension of ['jpg', 'png']) {
  test(`actually decodes and deterministically re-encodes ${extension}`, async () => {
    const original = fixture(extension);
    const first = canonicalize(original, extension), second = canonicalize(original, extension);
    assert.equal(first.width, 16); assert.equal(first.height, 12);
    assert.deepEqual(first.bytes, second.bytes);
    assert.match(await digest(first.bytes), /^[a-f0-9]{64}$/);
    assert.doesNotThrow(() => canonicalize(first.bytes, extension));
  });
}
test('rejects magic-only, truncated, malformed, wrong-format and oversized input', () => {
  for (const [bytes, ext] of [
    [Buffer.from([255, 216, 255]), 'jpg'], [fixture('jpg').subarray(0, 40), 'jpg'],
    [fixture('png').subarray(0, 40), 'png'], [fixture('png'), 'jpg'], [fixture('jpg'), 'png'],
    [Buffer.alloc(MAX_BYTES + 1), 'png'], [Buffer.from('<script>private</script>'), 'jpg'],
    [Buffer.concat([fixture('png'), Buffer.from('trailing payload')]), 'png'],
  ]) assert.throws(() => canonicalize(bytes, ext), PhotoRejected);
});
test('rejects huge dimensions before decompression/allocation', () => {
  const png = fixture('png'), ihdr = Buffer.from(png.subarray(16, 29));
  ihdr.writeUInt32BE(100000, 0);
  assert.throws(() => canonicalize(Buffer.concat([png.subarray(0, 8), chunk('IHDR', ihdr), png.subarray(33)]), 'png'), PhotoRejected);
  assert.throws(() => canonicalize(fixture('jpg', 1601, 1), 'jpg'), PhotoRejected);
});
test('strips JPEG comments/EXIF and PNG ancillary text from fresh encoding', () => {
  const raw = fixture('jpg'), secret = Buffer.from('Exif\0\0SYNTHETIC GPS SECRET');
  const app = Buffer.alloc(secret.length + 4); app[0] = 255; app[1] = 225; app.writeUInt16BE(secret.length + 2, 2); secret.copy(app, 4);
  const jpg = Buffer.concat([raw.subarray(0, 2), app, raw.subarray(2)]);
  assert.equal(Buffer.from(canonicalize(jpg, 'jpg').bytes).includes(secret), false);
  const png = fixture('png'), text = Buffer.from('Comment\0SYNTHETIC PRIVATE ADDRESS');
  const withText = Buffer.concat([png.subarray(0, 33), chunk('tEXt', text), png.subarray(33)]);
  assert.equal(Buffer.from(canonicalize(withText, 'png').bytes).includes(text), false);
});
test('rejects bad CRC, APNG and interlaced PNG inputs', () => {
  const png = fixture('png'), broken = Buffer.from(png); broken[29] ^= 1;
  assert.throws(() => canonicalize(broken, 'png'), PhotoRejected);
  const animation = Buffer.concat([png.subarray(0, 33), chunk('acTL', Buffer.alloc(8)), png.subarray(33)]);
  assert.throws(() => canonicalize(animation, 'png'), PhotoRejected);
  const ihdr = Buffer.from(png.subarray(16, 29)); ihdr[12] = 1;
  assert.throws(() => canonicalize(Buffer.concat([png.subarray(0, 8), chunk('IHDR', ihdr), png.subarray(33)]), 'png'), PhotoRejected);
});
