import { createBackend } from './backend.mjs';
import { createHandler } from './handler.mjs';

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
