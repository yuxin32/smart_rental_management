# Tenant invitation email

The prepared `invite-tenant` function creates an email-confirmed tenant identity
with the administrator-entered temporary password, then sends a plain-text
welcome message through Gmail SMTP. It does not send a Supabase activation link.
The password appears only in the Auth password operation and the outgoing email;
it is not stored in user metadata, application tables, or audit logs.

Sender configuration is required before deploying this replacement:

- `SMTP_USER`: management's Gmail sender address.
- `SMTP_PASSWORD`: that Gmail account's Google App Password, entered directly in
  Supabase Edge Function Secrets. Never commit it or send it through chat.

Google requires 2-Step Verification for App Passwords. The function uses
`smtp.gmail.com`, port 465, TLS. Supabase Auth SMTP settings alone do not populate
these Edge Function secrets. No download URL is currently configured; the email
asks the tenant to obtain the installation file from apartment management.

Deploy the source folder with `supabase functions deploy invite-tenant --no-verify-jwt`.
The handler independently validates the caller's JWT and administrator account.
For dashboard deployment use `supabase/deploy/invite-tenant.bundle.ts` as the entry
file. This bundle includes the email text helper.

No custom SMTP secrets were present when inspected on 26 November 2026. The
replacement email function is prepared locally, not deployed. Existing deployed
invitations continue using the earlier Supabase email until the replacement is
configured and deployed. Do not claim a successful email delivery without testing
an explicitly authorized test invitation.

On delivery failure, the API reports failure, records a failure audit event and
keeps the prepared pending account so Admin can resend. Resend updates a pending
account's temporary password without deleting its identity. Accepted accounts
remain ineligible for invitation resend.

References:
- https://support.google.com/accounts/answer/185833
- https://developers.google.com/workspace/gmail/imap/imap-smtp
