import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

import nodemailer from "npm:nodemailer@6.10.1";
function invitationText(name: string, email: string, password: string): string {
  return `Dear ${name},

Welcome to Smart Rental Management.

Your apartment administrator has created a tenant account for you. Please download and install the Smart Rental Management application using the installation file provided by apartment management.

Open the application, select Tenant Login, and sign in using the following details:

Email address: ${email}
Temporary password: ${password}

You will be asked to set a new password on your first sign-in. Once it is saved, sign in again with your new password and follow the instructions to submit your supporting documents.

Keep your password confidential. Do not share this email or your login details with anyone. Apartment management will never ask you to disclose your password.

If you were not expecting this invitation or need the application installation file, please contact your apartment administrator.

Kind regards,
Apartment Management
Smart Rental Management`;
}


const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Only POST requests are supported." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "The invitation service is not configured." }, 500);
  }

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication is required." }, 401);
  }

  const accessToken = authorization.replace("Bearer ", "");
  const { data: authData, error: authError } =
    await serviceClient.auth.getUser(accessToken);

  if (authError || !authData.user) {
    return json({ error: "The administrator session is invalid." }, 401);
  }

  const { data: administrator, error: administratorError } = await serviceClient
    .from("admin")
    .select("admin_id")
    .eq("admin_id", authData.user.id)
    .eq("is_active", true)
    .maybeSingle();

  if (administratorError || !administrator) {
    return json({ error: "Only an active administrator can send invitations." }, 403);
  }

  const smtpUser = Deno.env.get("SMTP_USER");
  const smtpPassword = Deno.env.get("SMTP_PASSWORD");
  if (!smtpUser || !smtpPassword) {
    return json({ error: "Invitation email is not configured. Configure the management Gmail sender before inviting tenants." }, 503);
  }
  const mailer = nodemailer.createTransport({
    host: "smtp.gmail.com", port: 465, secure: true,
    auth: { user: smtpUser, pass: smtpPassword },
    connectionTimeout: 15000, socketTimeout: 20000,
    logger: false, debug: false,
  });

  const body = await request.json().catch(() => ({}));
  const registrationId = body.registration_id;
  const resend = body.resend === true;
  const temporaryPassword = body.temporary_password;

  if (typeof registrationId !== "string" || registrationId.trim().length === 0) {
    return json({ error: "registration_id is required." }, 400);
  }

  if (
    typeof temporaryPassword !== "string" ||
    temporaryPassword.length < 8 ||
    temporaryPassword.length > 72
  ) {
    return json(
      { error: "The temporary password must contain 8 to 72 characters." },
      400,
    );
  }

  const { data: registration, error: registrationError } = await serviceClient
    .from("tenant_registration")
    .select("*")
    .eq("registration_id", registrationId)
    .maybeSingle();

  if (registrationError) {
    return json({ error: registrationError.message }, 400);
  }

  if (!registration) {
    return json({ error: "Tenant registration was not found." }, 404);
  }

  if (registration.created_by_admin_id !== authData.user.id) {
    return json({ error: "You cannot invite this tenant registration." }, 403);
  }

  if (resend) {
    if (
      registration.registration_status !== "invited" ||
      !registration.auth_user_id
    ) {
      return json(
        { error: "Only a previously sent, pending invitation can be resent." },
        400,
      );
    }

    const { data: existingAccount, error: existingAccountError } =
      await serviceClient
        .from("user_account")
        .select("user_id, account_status, invitation_status, accepted_at")
        .eq("user_id", registration.auth_user_id)
        .maybeSingle();

    if (existingAccountError) {
      return json({ error: existingAccountError.message }, 400);
    }

    if (
      !existingAccount ||
      existingAccount.account_status !== "pending" ||
      existingAccount.invitation_status !== "invited" ||
      existingAccount.accepted_at
    ) {
      return json(
        {
          error:
            "This invitation cannot be resent because the tenant account is no longer pending.",
        },
        409,
      );
    }

    const { data: existingTenancies, error: existingTenancyError } =
      await serviceClient
        .from("tenancy")
        .select("tenancy_id, tenancy_status")
        .eq("tenant_id", registration.auth_user_id);

    if (existingTenancyError) {
      return json({ error: existingTenancyError.message }, 400);
    }

    if (
      (existingTenancies ?? []).some(
        (tenancy) => tenancy.tenancy_status !== "pending",
      )
    ) {
      return json(
        {
          error:
            "This invitation cannot be resent because the tenant already has an active or completed tenancy.",
        },
        409,
      );
    }

    // Resending reuses the pending identity and updates its temporary password.
    // It does not delete the tenant's Auth user or related records.
  } else if (!["draft", "assigned", "expired"].includes(registration.registration_status)) {
    return json({ error: "This tenant registration cannot be invited again." }, 400);
  }

  const identity = resend
    ? await serviceClient.auth.admin.updateUserById(registration.auth_user_id, {
        password: temporaryPassword, email_confirm: true,
      })
    : await serviceClient.auth.admin.createUser({
        email: registration.email, password: temporaryPassword, email_confirm: true,
        user_metadata: { role: "tenant", registration_id: registration.registration_id },
      });
  if (identity.error || !identity.data.user) {
    return json({ error: "Unable to configure the tenant login. Check the email address and password requirements." }, 400);
  }
  const invitedUser = identity.data.user;
  const invitedAt = new Date().toISOString();

  const { error: accountError } = await serviceClient
    .from("user_account")
    .upsert(
      {
        user_id: invitedUser.id,
        full_name: registration.full_name,
        email: registration.email,
        contact_number: registration.contact_number,
        role: "tenant",
        account_status: "pending",
        invitation_status: "invited",
        invited_at: invitedAt,
      },
      { onConflict: "user_id" },
    );

  if (accountError) {
    if (!resend) await serviceClient.auth.admin.deleteUser(invitedUser.id);
    return json({ error: accountError.message }, 400);
  }

  const { error: tenantError } = await serviceClient.from("tenant").upsert(
    {
      tenant_id: invitedUser.id,
      ic_number: registration.ic_number,
      verification_status: "pending",
      is_verified: false,
      identity_document_path: null,
      employment_or_study_proof_path: null,
      verified_by_admin_id: null,
      verified_at: null,
    },
    { onConflict: "tenant_id" },
  );

  if (tenantError) {
    if (!resend) await serviceClient.auth.admin.deleteUser(invitedUser.id);
    return json({ error: tenantError.message }, 400);
  }

  const { error: registrationUpdateError } = await serviceClient
    .from("tenant_registration")
    .update({
      auth_user_id: invitedUser.id,
      registration_status: "invited",
      invited_at: invitedAt,
    })
    .eq("registration_id", registration.registration_id);

  if (registrationUpdateError) {
    return json({ error: registrationUpdateError.message }, 400);
  }

  try {
    await mailer.sendMail({
      from: { name: "Smart Rental Management", address: smtpUser },
      to: registration.email,
      subject: "Welcome to Smart Rental Management — Your Tenant Account",
      text: invitationText(registration.full_name, registration.email, temporaryPassword),
      disableFileAccess: true, disableUrlAccess: true,
    });
  } catch (_) {
    await serviceClient.from("audit_log").insert({
      actor_user_id: authData.user.id, action_type: "TENANT_INVITATION_DELIVERY_FAILED",
      entity_type: "tenant_registration", entity_id: registration.registration_id,
      outcome: "failure", metadata: { delivery_mode: "gmail_smtp" },
    });
    return json({ error: "The tenant account was prepared, but the email could not be delivered. Check the Gmail sender settings, then resend the invitation." }, 502);
  }

  const { error: auditError } = await serviceClient.from("audit_log").insert({
    actor_user_id: authData.user.id,
    action_type: resend
      ? "TENANT_INVITATION_RESENT"
      : "TENANT_INVITATION_SENT",
    entity_type: "tenant_registration",
    entity_id: registration.registration_id,
    outcome: "success",
    metadata: {
      email: registration.email,
      invitation_kind: resend ? "resend" : "initial",
      delivery_mode: "gmail_smtp_temporary_password",
    },
  });

  if (auditError) {
    console.error("Invitation sent but audit log could not be written", auditError);
  }

  return json({
    registration_id: registration.registration_id,
    user_id: invitedUser.id,
    status: resend ? "resent" : "invited",
  });
});
