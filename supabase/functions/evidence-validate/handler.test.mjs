import test from 'node:test';
import assert from 'node:assert/strict';
import { PNG } from 'pngjs';
import { createHandler, readBounded } from './handler.mjs';
import { digest, PhotoRejected } from './codec.mjs';

const booking = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', upload = '11111111-1111-4111-8111-111111111111';
const user = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const raw = PNG.sync.write({ width: 2, height: 2, data: Buffer.alloc(16, 255) });
function request(bytes = raw, headers = {}) {
  return new Request('https://local.invalid/evidence-validate', { method: 'POST', body: bytes,
    headers: { Authorization: 'Bearer SYNTHETIC', 'Content-Type': 'application/octet-stream',
      'x-booking-id': booking, 'x-upload-id': upload, ...headers } });
}
async function setup(overrides = {}) {
  const calls = [], sourceHash = await digest(raw);
  const backend = {
    authenticate: async () => { calls.push('auth'); return user; },
    claim: async (b, u, actor) => {
      assert.equal(b, booking); assert.equal(u, upload); assert.equal(actor, user); calls.push('claim');
      return { state: 'processing', token: 'SYNTHETIC_LEASE', path: `${booking}/before_${upload}.png`,
        source_size: raw.length, source_sha256: sourceHash, extension: 'png' };
    },
    put: async (_, bytes) => { calls.push('put'); assert.ok(PNG.sync.read(Buffer.from(bytes))); },
    finish: async () => { calls.push('finish'); return true; },
    fail: async (_, __, rejected) => calls.push(rejected ? 'reject' : 'retry'), ...overrides,
  };
  return { calls, handle: createHandler({ backend, allowedOrigins: ['https://app.invalid'] }) };
}
test('authenticates, claims, decodes, publishes then attests; never returns bytes/secret', async () => {
  const { handle, calls } = await setup();
  const result = await handle(request());
  assert.equal(result.status, 200); assert.equal((await result.json()).verified, true);
  assert.deepEqual(calls, ['auth', 'claim', 'put', 'finish']);
  assert.equal(result.headers.get('Cache-Control'), 'no-store');
});
test('unauthenticated/other actor cannot decode or upload', async () => {
  const { handle, calls } = await setup({ authenticate: async () => null });
  assert.equal((await handle(request())).status, 401); assert.deepEqual(calls, []);
  const other = await setup({ claim: async () => { const e = new Error('PRIVATE ADDRESS'); e.code = 'NOT_ALLOWED'; throw e; } });
  const rejected = await other.handle(request());
  assert.equal(rejected.status, 403); assert.equal((await rejected.text()).includes('PRIVATE'), false);
});
test('mismatched source hash or size never publishes and definitively rejects token', async () => {
  const { handle, calls } = await setup();
  const changed = Buffer.from(raw); changed[20] ^= 1;
  assert.equal((await handle(request(changed))).status, 422);
  assert.deepEqual(calls, ['auth', 'claim', 'reject']);
});
test('decoder rejects claimed file even when its hash matches', async () => {
  const bytes = new Uint8Array([137,80,78,71,13,10,26,10,0]);
  const s = await setup({ claim: async () => ({ state: 'processing', token: 'T',
    path: `${booking}/before_${upload}.png`, extension: 'png', source_size: bytes.length, source_sha256: await digest(bytes) }) });
  assert.equal((await s.handle(request(bytes))).status, 422);
  assert.deepEqual(s.calls, ['auth', 'reject']);
});
test('busy and terminal ticket states never read/publish input', async () => {
  for (const [state, status] of [['busy',409],['photo_rejected',422],['attempts_exhausted',422],['expired_or_closed',409]]) {
    const { handle, calls } = await setup({ claim: async () => ({ state }) });
    assert.equal((await handle(request())).status, status); assert.deepEqual(calls, ['auth']);
  }
});
test('lost response retry returns prior verification without another decode/write', async () => {
  const { handle, calls } = await setup({ claim: async () => ({ state: 'verified', path: `${booking}/before_${upload}.png` }) });
  assert.equal((await handle(request())).status, 200); assert.deepEqual(calls, ['auth']);
});
test('storage failure releases attempt as retry, not validation/attachment success', async () => {
  const { handle, calls } = await setup({ put: async () => { throw new Error('SECRET_UPSTREAM'); } });
  const result = await handle(request());
  assert.equal(result.status, 503); assert.equal((await result.text()).includes('SECRET'), false);
  assert.deepEqual(calls, ['auth', 'claim', 'retry']);
});
test('failed final attestation never reports verified', async () => {
  const { handle } = await setup({ finish: async () => false });
  assert.equal((await handle(request())).status, 409);
});
test('strict CORS and binary protocol, including preflight, reject unexpected origins', async () => {
  const { handle, calls } = await setup();
  assert.equal((await handle(request(raw, { Origin: 'https://evil.invalid' }))).status, 403);
  assert.equal((await handle(request(raw, { 'x-upload-id': '../other' }))).status, 400);
  assert.equal((await handle(request(raw, { 'Content-Type': 'application/json' }))).status, 400);
  assert.deepEqual(calls, []);
  const result = await handle(new Request('https://local.invalid', { method: 'OPTIONS', headers: { Origin: 'https://app.invalid' } }));
  assert.equal(result.headers.get('Access-Control-Allow-Origin'), 'https://app.invalid');
});
test('oversized bodies are bounded with and without content-length', async () => {
  const { handle } = await setup();
  assert.equal((await handle(request(raw, { 'Content-Length': '99999999' }))).status, 413);
  const stream = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(10)); c.close(); } });
  await assert.rejects(readBounded(stream, 9), PhotoRejected);
});
test('slow streams time out and release the reader', async () => {
  let cancelled = false;
  const stream = new ReadableStream({ cancel() { cancelled = true; } });
  await assert.rejects(readBounded(stream, 50, 10), /READ_TIMEOUT/);
  assert.equal(cancelled, true);
});
test('one isolate does not retain multiple photo buffers concurrently', async () => {
  let release;
  const { handle } = await setup({ authenticate: () => new Promise(resolve => { release = () => resolve(user); }) });
  const first = handle(request());
  assert.equal((await handle(request())).status, 503);
  release(); assert.equal((await first).status, 200);
});
