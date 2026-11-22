import jpeg from 'npm:jpeg-js@0.4.4';
import { PNG } from 'npm:pngjs@7.0.0';
import { Buffer } from 'node:buffer';

export const MAX_BYTES = 5 * 1024 * 1024;
export const VERSION = 'pixels-v1';
const MAX_EDGE = 1600, MAX_PIXELS = 1600 * 1600;
export class PhotoRejected extends Error {
  constructor() { super('PHOTO_REJECTED'); }
}
const reject = () => { throw new PhotoRejected(); };
const dimensions = (width, height) => {
  if (width < 1 || height < 1 || width > MAX_EDGE || height > MAX_EDGE ||
      width * height > MAX_PIXELS) reject();
};

// Header bounds are a pre-allocation guard, NOT a substitute for decoding.
function inspectPng(bytes) {
  if (bytes.length < 45 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') reject();
  let offset = 8, header = false, data = false, end = false;
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) reject();
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    if (length > MAX_BYTES || offset + length + 12 > bytes.length) reject();
    if (!header && type !== 'IHDR') reject();
    if (type === 'IHDR') {
      if (header || length !== 13) reject();
      dimensions(bytes.readUInt32BE(offset + 8), bytes.readUInt32BE(offset + 12));
      // Still, non-interlaced 8-bit RGB/RGBA only; matches app-prepared inputs.
      if (bytes[offset + 16] !== 8 || ![2, 6].includes(bytes[offset + 17]) ||
          bytes[offset + 18] !== 0 || bytes[offset + 19] !== 0 || bytes[offset + 20] !== 0) reject();
      header = true;
    } else if (['acTL', 'fcTL', 'fdAT'].includes(type)) reject();
    else if (type === 'IDAT') data = true;
    else if (type === 'IEND') {
      if (length !== 0 || !data || offset + 12 !== bytes.length) reject();
      end = true;
    } else if ((bytes[offset + 4] & 32) === 0 && type !== 'PLTE') reject();
    offset += length + 12;
  }
  if (!header || !data || !end) reject();
}
function inspectJpeg(bytes) {
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216 ||
      bytes.at(-2) !== 255 || bytes.at(-1) !== 217) reject();
  let offset = 2, frame = false;
  while (offset < bytes.length - 2) {
    if (bytes[offset++] !== 255) reject();
    while (bytes[offset] === 255) offset++;
    const marker = bytes[offset++];
    if (marker === 218) break; // Decode all entropy-coded scans below.
    if (offset + 2 > bytes.length) reject();
    const length = bytes.readUInt16BE(offset);
    if (length < 2 || offset + length > bytes.length) reject();
    if ([192, 193, 194].includes(marker)) {
      if (frame || length < 8 || bytes[offset + 2] !== 8) reject();
      dimensions(bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3));
      frame = true;
    } else if (marker >= 195 && marker <= 207 && ![196, 200, 204].includes(marker)) reject();
    offset += length;
  }
  if (!frame) reject();
}
export async function digest(bytes) {
  return Buffer.from(await crypto.subtle.digest('SHA-256', bytes)).toString('hex');
}
export function canonicalize(source, extension) {
  try {
    if (!(source instanceof Uint8Array) || !source.length || source.length > MAX_BYTES) reject();
    const bytes = Buffer.from(source.buffer, source.byteOffset, source.byteLength);
    let pixels, encoded, mime;
    if (extension === 'jpg') {
      inspectJpeg(bytes);
      pixels = jpeg.decode(bytes, { useTArray: true, formatAsRGBA: true,
        tolerantDecoding: false, maxResolutionInMP: 2.56, maxMemoryUsageInMB: 64 });
      dimensions(pixels.width, pixels.height);
      // Copy only pixels/dimensions, NEVER decoder EXIF, comments or thumbnails.
      encoded = jpeg.encode({ width: pixels.width, height: pixels.height, data: pixels.data }, 80).data;
      mime = 'image/jpeg';
    } else if (extension === 'png') {
      inspectPng(bytes);
      pixels = PNG.sync.read(bytes, { checkCRC: true, skipRescale: false });
      dimensions(pixels.width, pixels.height);
      encoded = PNG.sync.write({ width: pixels.width, height: pixels.height, data: pixels.data },
        { colorType: 6, inputColorType: 6, bitDepth: 8, deflateLevel: 6 });
      mime = 'image/png';
    } else reject();
    if (!encoded.length || encoded.length > MAX_BYTES) reject();
    return { bytes: new Uint8Array(encoded), width: pixels.width, height: pixels.height, mime };
  } catch (_) { throw new PhotoRejected(); }
}


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


export function createBackend({ url, anonKey, serviceKey, fetchImpl = fetch }) {
  if (!/^https:\/\/[a-z]{20}\.supabase\.co$/.test(url ?? '') || !anonKey || !serviceKey) {
    throw new Error('SERVER_CONFIGURATION_REQUIRED');
  }
  const request = (path, { bearer, method = 'POST', json, bytes, mime } = {}) => fetchImpl(`${url}${path}`, {
    method, headers: { apikey: bearer ? anonKey : serviceKey,
      Authorization: bearer ?? `Bearer ${serviceKey}`,
      'Content-Type': mime ?? 'application/json', 'Cache-Control': 'no-store',
      ...(bytes ? { 'x-upsert': 'false' } : {}) },
    body: bytes ?? (json === undefined ? undefined : JSON.stringify(json)),
    redirect: 'error', signal: AbortSignal.timeout(15000),
  });
  const rpc = async (name, json) => {
    const res = await request(`/rest/v1/rpc/${name}`, { json });
    if (!res.ok) {
      const error = new Error('BACKEND_REQUEST_FAILED');
      if (res.status === 403) error.code = 'NOT_ALLOWED';
      throw error;
    }
    return res.status === 204 ? undefined : res.json();
  };
  return {
    authenticate: async (bearer) => {
      const res = await request('/auth/v1/user', { bearer, method: 'GET' });
      if ([401, 403].includes(res.status)) return null;
      if (!res.ok) throw new Error('AUTH_UNAVAILABLE');
      return (await res.json()).id;
    },
    claim: (bookingId, uploadId, userId) => rpc('claim_evidence_validation', {
      p_booking_id: bookingId, p_upload_id: uploadId, p_provider_id: userId,
    }),
    put: async (path, bytes, mime, hash) => {
      // Never trust a path from a request, allow an overwrite or publish a URL.
      if (!/^[a-f0-9-]{36}\/(before|after)_[a-f0-9-]{36}\.(jpg|png)$/.test(path)) throw new Error('INVALID_PATH');
      const endpoint = `/storage/v1/object/cleaning-evidence/${path}`;
      const res = await request(endpoint, { bytes, mime });
      if (res.ok) return;
      // A previous attempt may have committed its immutable object but lost
      // the response. Compare actual bytes, not metadata or an error string.
      if (![400, 409].includes(res.status)) throw new Error('STORAGE_UNAVAILABLE');
      const previous = await request(`/storage/v1/object/authenticated/cleaning-evidence/${path}`, { method: 'GET' });
      if (!previous.ok) throw new Error('STORAGE_UNAVAILABLE');
      const existing = await readBounded(previous.body, MAX_BYTES);
      if (existing.length !== bytes.length || await digest(existing) !== hash) throw new Error('IMMUTABLE_OBJECT_MISMATCH');
    },
    finish: (id, token, sourceHash, hash, photo) => rpc('finish_evidence_validation', {
      p_upload_id: id, p_token: token, p_source_sha256: sourceHash,
      p_canonical_sha256: hash, p_size: photo.bytes.length,
      p_width: photo.width, p_height: photo.height, p_mime: photo.mime,
    }),
    fail: (id, token, rejected) => rpc('fail_evidence_validation', {
      p_upload_id: id, p_token: token, p_rejected: rejected,
    }),
  };
}


// Server process environment ONLY. Never copy the service credential to
// Flutter/Dart defines, Web assets, a URL, a browser or a committed config file.
const backend = createBackend({
  url: Deno.env.get('SUPABASE_URL'),
  anonKey: Deno.env.get('SUPABASE_ANON_KEY'),
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
});
const allowedOrigins = (Deno.env.get('EVIDENCE_ALLOWED_ORIGINS') ?? '')
  .split(',').map((value) => value.trim()).filter(Boolean);
Deno.serve(createHandler({ backend, allowedOrigins }));
