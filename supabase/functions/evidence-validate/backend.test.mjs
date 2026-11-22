import test from 'node:test';
import assert from 'node:assert/strict';
import { createBackend } from './backend.mjs';
import { digest } from './codec.mjs';
const url = `https://${'a'.repeat(20)}.supabase.co`;
const path = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd/before_11111111-1111-4111-8111-111111111111.png';
function backend(fetchImpl) { return createBackend({ url, anonKey: 'SYNTHETIC_PUBLIC', serviceKey: 'SYNTHETIC_SERVER', fetchImpl }); }
test('Auth verification uses public key plus bearer, never the service credential', async () => {
  const b = backend(async (address, options) => {
    assert.equal(address, `${url}/auth/v1/user`); assert.equal(options.headers.apikey, 'SYNTHETIC_PUBLIC');
    assert.equal(options.headers.Authorization, 'Bearer SYNTHETIC_USER');
    return Response.json({ id: 'TEST_ID' });
  });
  assert.equal(await b.authenticate('Bearer SYNTHETIC_USER'), 'TEST_ID');
});
test('expired auth fails closed and upstream errors do not expose payload', async () => {
  assert.equal(await backend(async () => new Response('', { status: 401 })).authenticate('Bearer SYNTHETIC'), null);
  await assert.rejects(backend(async () => new Response('PRIVATE', { status: 503 })).authenticate('Bearer SYNTHETIC'), /AUTH_UNAVAILABLE/);
});
test('immutable retry checks stored bytes and never enables upsert', async () => {
  const bytes = new Uint8Array([1,2,3]), calls = [];
  const b = backend(async (address, options) => {
    calls.push(address); assert.equal(options.headers.apikey, 'SYNTHETIC_SERVER');
    if (options.method === 'POST') {
      assert.equal(options.headers['x-upsert'], 'false'); return new Response('', { status: 409 });
    }
    return new Response(bytes);
  });
  await b.put(path, bytes, 'image/png', await digest(bytes)); assert.equal(calls.length, 2);
  await assert.rejects(b.put(path, bytes, 'image/png', 'wrong'), /IMMUTABLE_OBJECT_MISMATCH/);
});
test('unsafe path and untrusted destination never receive service credentials', async () => {
  let calls=0; const b=backend(async () => { calls++; return new Response(); });
  await assert.rejects(b.put('../other',new Uint8Array([1]),'image/png','hash'), /INVALID_PATH/);
  assert.equal(calls,0);
  assert.throws(() => createBackend({url:'https://evil.invalid',anonKey:'X',serviceKey:'Y'}), /SERVER_CONFIGURATION_REQUIRED/);
});
test('successful RPC receives only allow-listed attestation fields', async () => {
  const b=backend(async (address, options) => {
    assert.equal(address,`${url}/rest/v1/rpc/finish_evidence_validation`);
    const body=JSON.parse(options.body); assert.equal(body.p_size,3); assert.equal(body.bytes,undefined);
    return Response.json(true);
  });
  assert.equal(await b.finish('ID','TOKEN','source','hash',{bytes:new Uint8Array(3),width:1,height:1,mime:'image/png'}),true);
});
