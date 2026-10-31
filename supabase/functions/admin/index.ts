// Campus Recreation Center Booking — "admin" edge function
// © 2026 Services Squire LLC. All rights reserved.
//
// Handles the actions that need Supabase's service role:
//   bootstrap            create the first system admin (only while none exists)
//   createStaff         add a management account          (system admin only)
//   updateStaff          change name / role / active flag   (system admin only)
//   setStaffPassword     set a staff member's password      (system admin only)
//   deleteStaff          remove a management account        (system admin only)
//   resetStudentPassword issue a temporary student password (system admin only)
//   updateStudent        edit a student's name / ID / college / phone (system admin only)
//   deleteStudent        delete a student account and all its data   (system admin only)
// Roles: staff (reception), admin (system admin), developer (admin + name/logo),
// viewer (read-only follow-up). "system admin" above means admin or developer.
// A system admin may create the first developer account; after that only a
// developer may create, change or remove developer accounts.
// The function checks the caller itself, so deploy it with JWT verification off.

import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const STAFF_DOMAIN = Deno.env.get("STAFF_EMAIL_DOMAIN") ?? "staff.example.com";
const STUDENT_DOMAIN = Deno.env.get("STUDENT_EMAIL_DOMAIN") ?? "students.example.com";
const SID = /^[0-9]{4,12}$/;
const USERNAME = /^[a-z0-9._-]{3,24}$/;
const ROLES = ["staff", "admin", "developer", "viewer"];
const ADMIN_ROLES = ["admin", "developer"];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function tempPassword(): string {
  const A = "abcdefghjkmnpqrstuvwxyz23456789";
  const a = new Uint32Array(8);
  crypto.getRandomValues(a);
  return Array.from(a, (v) => A[v % A.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "bad_request" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const action = String(body.action ?? "");

  async function activeAdmins(): Promise<{ id: string }[]> {
    const { data } = await admin.from("staff").select("id").in("role", ["admin", "developer"]).eq("active", true);
    return data ?? [];
  }

  async function createStaff(b: Record<string, unknown>, role: string) {
    const username = String(b.username ?? "").trim().toLowerCase();
    const name = String(b.name ?? "").trim();
    const password = String(b.password ?? "");
    if (!USERNAME.test(username)) return json({ error: "bad_username" }, 400);
    if (name.length < 2) return json({ error: "bad_name" }, 400);
    if (password.length < 8) return json({ error: "weak_password" }, 400);
    const { data: taken } = await admin.from("staff").select("id").eq("username", username).maybeSingle();
    if (taken) return json({ error: "username_taken" }, 409);
    const { data, error } = await admin.auth.admin.createUser({
      email: `${username}@${STAFF_DOMAIN}`, password, email_confirm: true,
    });
    if (error || !data.user) return json({ error: "username_taken", detail: error?.message }, 409);
    const { error: e2 } = await admin.from("staff").insert({ id: data.user.id, username, name, role, active: true });
    if (e2) { await admin.auth.admin.deleteUser(data.user.id); return json({ error: "failed", detail: e2.message }, 500); }
    return json({ ok: true, id: data.user.id });
  }

  // First-run: allowed only while there is no active system admin.
  if (action === "bootstrap") {
    if ((await activeAdmins()).length > 0) return json({ error: "forbidden" }, 403);
    return await createStaff(body, "admin");
  }

  // Everything else: the caller must be an active system admin.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "forbidden" }, 403);
  const { data: who } = await admin.auth.getUser(jwt);
  if (!who?.user) return json({ error: "forbidden" }, 403);
  const { data: me } = await admin.from("staff").select("*").eq("id", who.user.id).maybeSingle();
  if (!me || !me.active || !ADMIN_ROLES.includes(me.role)) return json({ error: "forbidden" }, 403);
  const isDev = me.role === "developer";
  // A system admin may create the first developer account; after that only a developer may.
  const { count: devCount } = await admin.from("staff").select("id", { count: "exact", head: true }).eq("role", "developer").eq("active", true);
  const allowedRole = (r: unknown) =>
    typeof r === "string" && ROLES.includes(r) && (r !== "developer" || isDev || (devCount ?? 0) === 0);

  const id = String(body.id ?? "");
  // Only a developer may touch a developer account.
  if (["updateStaff", "setStaffPassword", "deleteStaff"].includes(action) && !isDev) {
    const { data: t } = await admin.from("staff").select("role").eq("id", id).maybeSingle();
    if (t && t.role === "developer") return json({ error: "forbidden" }, 403);
  }

  switch (action) {
    case "createStaff":
      if (body.role !== undefined && !allowedRole(body.role)) return json({ error: "forbidden" }, 403);
      return await createStaff(body, typeof body.role === "string" ? body.role : "staff");

    case "updateStaff": {
      const { data: target } = await admin.from("staff").select("*").eq("id", id).maybeSingle();
      if (!target) return json({ error: "not_found" }, 404);
      const patch: Record<string, unknown> = {};
      if (typeof body.name === "string" && body.name.trim().length >= 2) patch.name = body.name.trim();
      if (body.role !== undefined) {
        if (!allowedRole(body.role)) return json({ error: "forbidden" }, 403);
        patch.role = body.role;
      }
      if (typeof body.active === "boolean") patch.active = body.active;
      const losesAdmin = ADMIN_ROLES.includes(target.role) && target.active &&
        ((typeof patch.role === "string" && !ADMIN_ROLES.includes(patch.role)) || patch.active === false);
      if (losesAdmin && (await activeAdmins()).length <= 1) return json({ error: "last_admin" }, 409);
      const { error } = await admin.from("staff").update(patch).eq("id", id);
      if (error) return json({ error: "failed", detail: error.message }, 500);
      if (typeof patch.active === "boolean") {
        await admin.auth.admin.updateUserById(id, { ban_duration: patch.active ? "none" : "876000h" });
      }
      return json({ ok: true });
    }

    case "setStaffPassword": {
      const password = String(body.password ?? "");
      if (password.length < 8) return json({ error: "weak_password" }, 400);
      const { data: target } = await admin.from("staff").select("id").eq("id", id).maybeSingle();
      if (!target) return json({ error: "not_found" }, 404);
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: "failed", detail: error.message }, 500);
      return json({ ok: true });
    }

    case "deleteStaff": {
      const { data: target } = await admin.from("staff").select("*").eq("id", id).maybeSingle();
      if (!target) return json({ error: "not_found" }, 404);
      if (ADMIN_ROLES.includes(target.role) && target.active && (await activeAdmins()).length <= 1) {
        return json({ error: "last_admin" }, 409);
      }
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: "failed", detail: error.message }, 500);
      return json({ ok: true });
    }

    case "resetStudentPassword": {
      const { data: st } = await admin.from("students").select("id").eq("id", id).maybeSingle();
      if (!st) return json({ error: "not_found" }, 404);
      const password = tempPassword();
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: "failed", detail: error.message }, 500);
      // the app sees must_change on the student's next load and forces a new password
      await admin.from("students").update({ must_change: true }).eq("id", id);
      return json({ ok: true, password });
    }

    case "updateStudent": {
      const { data: st } = await admin.from("students").select("*").eq("id", id).maybeSingle();
      if (!st) return json({ error: "not_found" }, 404);
      const patch: Record<string, unknown> = {};
      if (typeof body.name === "string") {
        const name = body.name.trim().replace(/\s+/g, " ");
        if (name.length < 3 || name.length > 120) return json({ error: "bad_name" }, 400);
        patch.name = name;
      }
      if (typeof body.college === "string") patch.college = body.college.trim().slice(0, 120);
      if (typeof body.phone === "string") patch.phone = body.phone.trim().slice(0, 30);
      const newSid = typeof body.sid === "string" ? body.sid.trim() : st.sid;
      if (!SID.test(newSid)) return json({ error: "bad_sid" }, 400);
      if (newSid !== st.sid) {
        const { data: taken } = await admin.from("students").select("id").eq("sid", newSid).maybeSingle();
        if (taken) return json({ error: "sid_taken" }, 409);
        const { error: eAuth } = await admin.auth.admin.updateUserById(id, { email: `${newSid}@${STUDENT_DOMAIN}`, email_confirm: true });
        if (eAuth) return json({ error: "sid_taken", detail: eAuth.message }, 409);
        patch.sid = newSid;
      }
      const { error } = await admin.from("students").update(patch).eq("id", id);
      if (error) return json({ error: "failed", detail: error.message }, 500);
      // keep bookings and the conversation list in step with the new details
      const { data: bks } = await admin.from("bookings").select("id,date").eq("uid", id);
      for (const b of bks ?? []) {
        const upd: Record<string, unknown> = { student_id: newSid };
        if (patch.name) upd.student_name = patch.name;
        const newId = `${b.date}_${newSid}`;
        if (newId !== b.id) upd.id = newId;
        await admin.from("bookings").update(upd).eq("id", b.id);
      }
      await admin.from("threads").update({ sid: newSid, ...(patch.name ? { name: patch.name } : {}) }).eq("student", id);
      return json({ ok: true });
    }

    case "deleteStudent": {
      const { data: st } = await admin.from("students").select("id").eq("id", id).maybeSingle();
      if (!st) return json({ error: "not_found" }, 404);
      // removing the sign-in account removes the student's profile, bookings, messages and warnings
      const { error } = await admin.auth.admin.deleteUser(id);
      if (error) return json({ error: "failed", detail: error.message }, 500);
      return json({ ok: true });
    }

    default:
      return json({ error: "bad_request" }, 400);
  }
});
