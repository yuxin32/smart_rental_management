import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

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

    // Only the unaccepted pending identity is replaced. Accepted and active
    // accounts are rejected above and are never overwritten by a resend.
    const { error: pendingTenancyDeleteError } = await serviceClient
      .from("tenancy")
      .delete()
      .eq("tenant_id", registration.auth_user_id)
      .eq("tenancy_status", "pending");

    if (pendingTenancyDeleteError) {
      return json({ error: pendingTenancyDeleteError.message }, 400);
    }

    const { error: deleteUserError } = await serviceClient.auth.admin.deleteUser(
      registration.auth_user_id,
    );

    if (deleteUserError) {
      return json(
        {
          error:
            "The previous pending invitation could not be reset safely. No new invitation was sent.",
        },
        409,
      );
    }

    const { error: resetRegistrationError } = await serviceClient
      .from("tenant_registration")
      .update({
        auth_user_id: null,
        registration_status: "draft",
        invited_at: null,
        accepted_at: null,
      })
      .eq("registration_id", registration.registration_id);

    if (resetRegistrationError) {
      return json({ error: resetRegistrationError.message }, 400);
    }
  } else if (!["draft", "assigned", "expired"].includes(registration.registration_status)) {
    return json({ error: "This tenant registration cannot be invited again." }, 400);
  }

  const inviteOptions = {
    data: {
      role: "tenant",
      registration_id: registration.registration_id,
    },
  };

  const { data: invitation, error: invitationError } =
    await serviceClient.auth.admin.inviteUserByEmail(
      registration.email,
      inviteOptions,
    );

  if (invitationError || !invitation.user) {
    return json(
      { error: invitationError?.message ?? "Unable to send the invitation email." },
      400,
    );
  }

  const invitedUser = invitation.user;
  const invitedAt = new Date().toISOString();

  // Demonstration workflow: the Auth identity receives a temporary password
  // supplied by the administrator. The Flutter app uses invitation_status to
  // force the tenant to replace it immediately after the first sign-in. The
  // password is never persisted in an application table or audit record.
  const { error: temporaryPasswordError } =
    await serviceClient.auth.admin.updateUserById(invitedUser.id, {
      password: temporaryPassword,
      email_confirm: true,
    });

  if (temporaryPasswordError) {
    await serviceClient.auth.admin.deleteUser(invitedUser.id);
    return json(
      { error: "The temporary tenant login could not be configured." },
      400,
    );
  }

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
    await serviceClient.auth.admin.deleteUser(invitedUser.id);
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
    await serviceClient.auth.admin.deleteUser(invitedUser.id);
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
      delivery_mode: "supabase_invite_with_temporary_password",
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
