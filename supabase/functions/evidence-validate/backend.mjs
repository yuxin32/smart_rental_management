import { digest, MAX_BYTES } from './codec.mjs';
import { readBounded } from './handler.mjs';

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
