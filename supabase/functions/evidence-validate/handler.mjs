import { canonicalize, digest, MAX_BYTES, PhotoRejected } from './codec.mjs';

const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
export async function readBounded(body, max = MAX_BYTES, timeoutMs = 10000) {
  if (!body) throw new PhotoRejected();
  const reader = body.getReader(), chunks = [];
  let size = 0, timer;
  const deadline = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('READ_TIMEOUT')), timeoutMs); });
  try {
    while (true) {
      const { value, done } = await Promise.race([reader.read(), deadline]);
      if (done) break;
      size += value.byteLength;
      if (size > max) throw new PhotoRejected();
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return bytes;
  } finally { clearTimeout(timer); await reader.cancel().catch(() => {}); }
}

export function createHandler({ backend, allowedOrigins = /** @type {string[]} */ ([]), decode = canonicalize }) {
  // Bound per-isolate live buffers. DB claim/attempt limits are cross-isolate.
  let active = false;
  return async function handle(request) {
    const origin = request.headers.get('origin');
    const cors = origin && allowedOrigins.includes(origin) ? {
      'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Headers': 'authorization,apikey,x-client-info,content-type,x-booking-id,x-upload-id',
      'Access-Control-Allow-Methods': 'POST,OPTIONS',
    } : {};
    const response = (status, code, extra = {}) => new Response(JSON.stringify({ code, ...extra }), {
      status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff', Vary: 'Origin' },
    });
    if (origin && !allowedOrigins.includes(origin)) return response(403, 'ORIGIN_NOT_ALLOWED');
    if (request.method === 'OPTIONS') return response(200, 'PREFLIGHT');
    if (request.method !== 'POST') return response(405, 'METHOD_NOT_ALLOWED');
    const bookingId = request.headers.get('x-booking-id'), uploadId = request.headers.get('x-upload-id');
    if (!UUID.test(bookingId ?? '') || !UUID.test(uploadId ?? '') ||
        request.headers.get('content-type')?.split(';')[0].trim() !== 'application/octet-stream') {
      return response(400, 'INVALID_REQUEST');
    }
    const declared = request.headers.get('content-length');
    if (declared && (!/^\d+$/.test(declared) || Number(declared) > MAX_BYTES)) return response(413, 'PHOTO_REJECTED');
    const bearer = request.headers.get('authorization');
    if (!bearer?.startsWith('Bearer ') || bearer.length > 8192) return response(401, 'AUTH_REQUIRED');
    if (active) return response(503, 'VALIDATION_BUSY');
    active = true;
    let ticket;
    try {
      const userId = await backend.authenticate(bearer);
      if (!UUID.test(userId ?? '')) return response(401, 'AUTH_REQUIRED');
      ticket = await backend.claim(bookingId, uploadId, userId);
      if (ticket.state === 'verified') return response(200, 'VERIFIED', { verified: true, path: ticket.path });
      if (ticket.state === 'busy') return response(409, 'VALIDATION_BUSY');
      if (['photo_rejected', 'attempts_exhausted'].includes(ticket.state)) return response(422, 'NEW_PHOTO_REQUIRED');
      if (ticket.state !== 'processing') return response(409, 'UPLOAD_CLOSED');
      const expectedPath = `${bookingId}/${ticket.path?.split('/')[1]}`;
      if (ticket.path !== expectedPath || !new RegExp(`^${bookingId}/(before|after)_${uploadId}\\.(jpg|png)$`).test(ticket.path) ||
          !['jpg', 'png'].includes(ticket.extension)) throw new Error('INVALID_TICKET');
      const source = await readBounded(request.body);
      const sourceHash = await digest(source);
      if (source.length !== ticket.source_size || sourceHash !== ticket.source_sha256) throw new PhotoRejected();
      const photo = decode(source, ticket.extension);
      const canonicalHash = await digest(photo.bytes);
      await backend.put(ticket.path, photo.bytes, photo.mime, canonicalHash);
      if (!await backend.finish(uploadId, ticket.token, sourceHash, canonicalHash, photo)) return response(409, 'UPLOAD_CLOSED');
      return response(200, 'VERIFIED', { verified: true, path: ticket.path });
    } catch (error) {
      if (ticket?.state === 'processing') {
        await backend.fail(uploadId, ticket.token, error instanceof PhotoRejected).catch(() => {});
      }
      if (error instanceof PhotoRejected) return response(422, 'PHOTO_REJECTED');
      if (error?.code === 'NOT_ALLOWED') return response(403, 'NOT_ALLOWED');
      // Never serialize/log credentials, file contents, addresses or upstream errors.
      return response(503, 'VALIDATION_UNAVAILABLE');
    } finally { active = false; }
  };
}
