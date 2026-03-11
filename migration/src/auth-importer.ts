/**
 * Imports Supabase Auth users into Firebase Auth with matching UIDs.
 *
 * This ensures:
 * 1. All Firestore document references (createdBy, updatedBy, user doc paths) remain valid
 * 2. Google Sign-In users can log in and see their data immediately
 * 3. Email/password users keep their same credentials (bcrypt hash import)
 *
 * Reads from Supabase Auth Admin API (requires service role key).
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import admin from 'firebase-admin';

interface SupabaseAuthUser {
  id: string;
  email: string | null;
  email_confirmed_at: string | null;
  phone: string | null;
  encrypted_password: string | null;
  created_at: string;
  updated_at: string;
  raw_app_meta_data: {
    provider?: string;
    providers?: string[];
    [key: string]: unknown;
  } | null;
  raw_user_meta_data: {
    full_name?: string;
    name?: string;
    avatar_url?: string;
    picture?: string;
    email?: string;
    iss?: string;
    sub?: string;
    [key: string]: unknown;
  } | null;
  identities: Array<{
    id: string;
    user_id: string;
    identity_data: Record<string, unknown>;
    provider: string;
    created_at: string;
    updated_at: string;
  }> | null;
}

export interface AuthImportResult {
  imported: number;
  skipped: number;
  failed: number;
  errors: Array<{ uid: string; email: string | null; error: string }>;
}

/**
 * Fetch all auth users for the given account from Supabase.
 * We use the Auth Admin API to list users, then filter to only those
 * whose UIDs match the account's user list.
 */
export async function fetchSupabaseAuthUsers(
  supabase: SupabaseClient,
  userIds: string[]
): Promise<SupabaseAuthUser[]> {
  const userIdSet = new Set(userIds);
  const authUsers: SupabaseAuthUser[] = [];

  // Supabase Auth Admin API paginates at 1000 users max per page
  let page = 1;
  const perPage = 1000;

  for (;;) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage,
    });

    if (error) throw new Error(`Failed to list Supabase auth users: ${error.message}`);
    if (!data?.users || data.users.length === 0) break;

    for (const user of data.users) {
      if (userIdSet.has(user.id)) {
        authUsers.push(user as unknown as SupabaseAuthUser);
      }
    }

    // If we got fewer than perPage, we've read all pages
    if (data.users.length < perPage) break;
    page++;
  }

  return authUsers;
}

/**
 * Import Supabase auth users into Firebase Auth with matching UIDs.
 */
export async function importAuthUsers(
  authUsers: SupabaseAuthUser[],
  options: { dryRun?: boolean } = {}
): Promise<AuthImportResult> {
  if (options.dryRun) {
    console.log(`  [dry-run] Would import ${authUsers.length} auth user(s).`);
    return { imported: authUsers.length, skipped: 0, failed: 0, errors: [] };
  }

  let imported = 0;
  let skipped = 0;
  const importErrors: AuthImportResult['errors'] = [];

  const auth = admin.auth();

  for (const user of authUsers) {
    try {
      // Check if user already exists in Firebase Auth
      try {
        await auth.getUser(user.id);
        // User exists — skip
        console.log(`  Skipping ${user.email ?? user.id} (already exists in Firebase Auth)`);
        skipped++;
        continue;
      } catch (e: unknown) {
        const err = e as { code?: string };
        if (err.code !== 'auth/user-not-found') throw e;
        // User doesn't exist — proceed with import
      }

      const displayName =
        user.raw_user_meta_data?.full_name ??
        user.raw_user_meta_data?.name ??
        null;
      const photoURL =
        user.raw_user_meta_data?.avatar_url ??
        user.raw_user_meta_data?.picture ??
        null;

      // Build the provider data for this user
      const providerData: admin.auth.UserProviderRequest[] = [];

      // Check identities for Google provider
      const googleIdentity = user.identities?.find((i) => i.provider === 'google');
      if (googleIdentity) {
        providerData.push({
          uid: googleIdentity.id,
          providerId: 'google.com',
          email: user.email ?? undefined,
          displayName: displayName ?? undefined,
          photoURL: photoURL ?? undefined,
        });
      }

      // Check for email provider
      const emailIdentity = user.identities?.find((i) => i.provider === 'email');
      if (emailIdentity && user.email) {
        providerData.push({
          uid: user.email,
          providerId: 'password',
          email: user.email,
          displayName: displayName ?? undefined,
        });
      }

      // Create user with matching UID
      const createRequest: admin.auth.CreateRequest = {
        uid: user.id,
        email: user.email ?? undefined,
        emailVerified: true,
        displayName: displayName ?? undefined,
        photoURL: photoURL ?? undefined,
        disabled: false,
      };

      // For email/password users, we need to set a password.
      // We can't import bcrypt hashes via createUser — we'll use importUsers for that.
      // For now, create without password; email/password users will need to reset.
      // Google users will work immediately via Google Sign-In.

      await auth.createUser(createRequest);

      // Link provider identities if we have them
      // Note: Firebase Admin SDK doesn't directly support linking providers on import.
      // Google Sign-In will auto-link when the user signs in because the email matches.

      console.log(`  Imported ${user.email ?? user.id} (${providerData.map(p => p.providerId).join(', ') || 'no provider'})`);
      imported++;
    } catch (e: unknown) {
      const err = e as { message?: string };
      importErrors.push({
        uid: user.id,
        email: user.email,
        error: err.message ?? String(e),
      });
      console.error(`  Failed to import ${user.email ?? user.id}: ${err.message}`);
    }
  }

  return { imported, skipped, failed: importErrors.length, errors: importErrors };
}

/**
 * Import users with password hashes using the bulk importUsers API.
 * This is the proper way to transfer bcrypt hashes from Supabase to Firebase.
 */
export async function importAuthUsersWithPasswords(
  authUsers: SupabaseAuthUser[],
  options: { dryRun?: boolean } = {}
): Promise<AuthImportResult> {
  if (options.dryRun) {
    console.log(`  [dry-run] Would import ${authUsers.length} auth user(s).`);
    return { imported: authUsers.length, skipped: 0, failed: 0, errors: [] };
  }

  const auth = admin.auth();

  // Filter to users that don't already exist
  const usersToImport: SupabaseAuthUser[] = [];
  let skipped = 0;

  for (const user of authUsers) {
    try {
      await auth.getUser(user.id);
      console.log(`  Skipping ${user.email ?? user.id} (already exists)`);
      skipped++;
    } catch (e: unknown) {
      const err = e as { code?: string };
      if (err.code === 'auth/user-not-found') {
        usersToImport.push(user);
      } else {
        throw e;
      }
    }
  }

  if (usersToImport.length === 0) {
    console.log('  All users already exist in Firebase Auth.');
    return { imported: 0, skipped, failed: 0, errors: [] };
  }

  // Build import records
  const userImportRecords: admin.auth.UserImportRecord[] = usersToImport.map((user) => {
    const displayName =
      user.raw_user_meta_data?.full_name ??
      user.raw_user_meta_data?.name ??
      undefined;
    const photoURL =
      user.raw_user_meta_data?.avatar_url ??
      user.raw_user_meta_data?.picture ??
      undefined;

    const providerData: admin.auth.UserProviderRequest[] = [];

    // Google provider
    const googleIdentity = user.identities?.find((i) => i.provider === 'google');
    if (googleIdentity) {
      providerData.push({
        uid: googleIdentity.id,
        providerId: 'google.com',
        email: user.email ?? undefined,
        displayName: displayName ?? undefined,
        photoURL: photoURL ?? undefined,
      });
    }

    const record: admin.auth.UserImportRecord = {
      uid: user.id,
      email: user.email ?? undefined,
      emailVerified: true,
      displayName: displayName ?? undefined,
      photoURL: photoURL ?? undefined,
      disabled: false,
      providerData,
    };

    // Include password hash if it exists (bcrypt from Supabase)
    if (user.encrypted_password && user.encrypted_password.startsWith('$2')) {
      record.passwordHash = Buffer.from(user.encrypted_password, 'utf8');
    }

    return record;
  });

  // Import with bcrypt hash algorithm
  const hasBcryptUsers = userImportRecords.some((r) => r.passwordHash);

  try {
    const result = await auth.importUsers(
      userImportRecords,
      hasBcryptUsers
        ? { hash: { algorithm: 'BCRYPT' } }
        : undefined
    );

    const importedCount = userImportRecords.length - (result.errors?.length ?? 0);
    const importErrors: AuthImportResult['errors'] = [];

    if (result.errors && result.errors.length > 0) {
      for (const err of result.errors) {
        const user = usersToImport[err.index];
        importErrors.push({
          uid: user.id,
          email: user.email,
          error: err.error.message,
        });
        console.error(`  Failed: ${user.email ?? user.id}: ${err.error.message}`);
      }
    }

    for (const user of usersToImport) {
      const failed = result.errors?.some((e) => usersToImport[e.index]?.id === user.id);
      if (!failed) {
        const providers = user.identities?.map((i) => i.provider).join(', ') ?? 'none';
        const hasPassword = user.encrypted_password?.startsWith('$2') ? '+password' : '';
        console.log(`  Imported ${user.email ?? user.id} (${providers}${hasPassword ? ` ${hasPassword}` : ''})`);
      }
    }

    return { imported: importedCount, skipped, failed: importErrors.length, errors: importErrors };
  } catch (e: unknown) {
    const err = e as { message?: string };
    console.error(`  Bulk import failed: ${err.message}`);
    return {
      imported: 0,
      skipped,
      failed: usersToImport.length,
      errors: usersToImport.map((u) => ({
        uid: u.id,
        email: u.email,
        error: err.message ?? String(e),
      })),
    };
  }
}
