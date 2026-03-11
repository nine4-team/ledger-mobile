import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type {
  SupabaseExport,
  SupabaseAccount,
  SupabaseUser,
  SupabaseProject,
  SupabaseSpace,
  SupabaseSpaceTemplate,
  SupabaseItem,
  SupabaseTransaction,
  SupabaseInvitation,
  SupabaseAccountPresets,
  SupabaseLineageEdge,
} from './types.js';

const PAGE_SIZE = 1000;

// Use `any` for the query builder to avoid fighting Supabase's complex generic types.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type QueryBuilder = any;

async function readAllPages<T>(
  supabase: SupabaseClient,
  table: string,
  filter: (q: QueryBuilder) => QueryBuilder,
  orderColumn = 'created_at'
): Promise<T[]> {
  const rows: T[] = [];
  let from = 0;

  for (;;) {
    const to = from + PAGE_SIZE - 1;
    const base = supabase.from(table).select('*').order(orderColumn, { ascending: true, nullsFirst: false });
    // eslint-disable-next-line no-await-in-loop
    const { data, error } = await filter(base).range(from, to);

    if (error) throw new Error(`Failed reading ${table}: ${error.message}`);
    const page = (data ?? []) as T[];
    rows.push(...page);
    if (page.length < PAGE_SIZE) break;
    from += PAGE_SIZE;
  }

  return rows;
}

export async function readAccount(
  supabase: SupabaseClient,
  accountId: string
): Promise<SupabaseExport> {
  // Verify account exists first
  const { data: accountData, error: accountError } = await supabase
    .from('accounts')
    .select('*')
    .eq('id', accountId)
    .maybeSingle();

  if (accountError) throw new Error(`Failed reading account: ${accountError.message}`);
  if (!accountData) throw new Error(`Account not found: ${accountId}`);

  const account = accountData as SupabaseAccount;
  const byAccount = (q: QueryBuilder) => q.eq('account_id', accountId);

  const [
    users,
    projects,
    spaces,
    spaceTemplates,
    items,
    transactions,
    invitations,
    lineageEdges,
  ] = await Promise.all([
    readAllPages<SupabaseUser>(supabase, 'users', byAccount, 'id'),
    readAllPages<SupabaseProject>(supabase, 'projects', byAccount),
    readAllPages<SupabaseSpace>(supabase, 'spaces', byAccount),
    readAllPages<SupabaseSpaceTemplate>(supabase, 'space_templates', byAccount, 'sort_order'),
    readAllPages<SupabaseItem>(supabase, 'items', byAccount),
    readAllPages<SupabaseTransaction>(supabase, 'transactions', byAccount),
    readAllPages<SupabaseInvitation>(supabase, 'invitations', byAccount),
    readAllPages<SupabaseLineageEdge>(supabase, 'item_lineage_edges', byAccount),
  ]);

  // account_presets is a single row keyed by account_id
  const { data: presetsData } = await supabase
    .from('account_presets')
    .select('*')
    .eq('account_id', accountId)
    .maybeSingle();

  const accountPresets = (presetsData ?? null) as SupabaseAccountPresets | null;

  console.log(`  accounts: 1`);
  console.log(`  users: ${users.length}`);
  console.log(`  projects: ${projects.length}`);
  console.log(`  spaces: ${spaces.length}`);
  console.log(`  space_templates: ${spaceTemplates.length}`);
  console.log(`  items: ${items.length}`);
  console.log(`  transactions: ${transactions.length}`);
  console.log(`  invitations: ${invitations.length}`);
  console.log(`  lineage_edges: ${lineageEdges.length}`);

  return {
    account,
    users,
    projects,
    spaces,
    spaceTemplates,
    items,
    transactions,
    invitations,
    accountPresets,
    lineageEdges,
  };
}

export function createSupabaseClient(supabaseUrl: string, serviceRoleKey: string): SupabaseClient {
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
