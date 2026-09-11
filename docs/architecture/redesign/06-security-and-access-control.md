# Security and Access Control

Status: proposed architecture
Architecture version: 0.1
Last reviewed: 2026-08-31

## Purpose

This document defines defense-in-depth for authentication, tenant isolation,
financial confidentiality, local offline data, Storage, trusted commands, MCP,
and migration tooling.

## Security Objectives

- A principal can access only accounts with active membership.
- Account membership does not automatically grant all financial visibility.
- Unauthorized rows are not downloaded to a device.
- Every authoritative write is authorized again at Postgres.
- Sensitive local data is encrypted and bounded by an offline-access policy.
- Privileged tools cannot silently bypass domain invariants or audit.
- Environment mistakes fail before any production read or write.
- Paid history, permission changes, and administrative corrections remain
  attributable.

## Identity Model

Authentication and Ledger identity are separate:

```text
auth provider issuer + subject
            |
            v
     auth_identities
            |
            v
       principals
            |
            v
     account_members
```

### Auth identity

An Auth identity is an externally signed `(issuer, subject)` pair. If A-007
selects temporary Firebase Auth for target launch, it begins as a Firebase
subject; otherwise it begins as a Supabase Auth subject.

### Principal

A Principal is Ledger's stable actor identity. Domain ownership, membership,
operations, audit, and attribution reference `principal_id`, not a provider UID.

### Membership

Membership grants a Principal access to one Account and stores role, state, and
financial permissions. It is server data, not a user-editable token claim.

## Authorization Inputs

Trusted inputs:

- validated token issuer, audience, subject, and expiry;
- server-side identity mapping;
- active account membership;
- role and financial-access records;
- resource account/project/client relationships;
- accounting authority and command-contract versions; and
- server-owned Invoice/paid/archived state.

Untrusted inputs:

- account/project IDs supplied by the client;
- client-claimed actor IDs or roles;
- user-editable auth metadata;
- UI visibility state;
- local cached membership after reconnect;
- attachment filenames/paths supplied without validation; and
- MCP command payload assertions about authorization.

## Authorization Layers

| Layer | Purpose | Failure behavior |
|---|---|---|
| UI/application | Prevent impossible choices and explain access | Hide/disable with explanation; not security authority |
| PowerSync Sync Streams | Prevent unauthorized rows from downloading | Omit/remove rows |
| Supabase grants | Limit which operations a role can attempt | Permission denied |
| Postgres RLS | Enforce row access for API/direct writes | Deny/filter |
| Command handler | Enforce domain capability, state, and cross-row rules | Durable rejected operation |
| Storage policy | Enforce object-path access | Deny upload/read |
| MCP/API authorization | Bind caller to Principal and allowed capability | Deny and audit |
| Migration/IAM | Restrict environment and maintenance operations | Fail closed before execution |

No single layer substitutes for another.

## Tenant Isolation

Every account-owned canonical row carries immutable `account_id`. Child
relationships must agree with the parent's account. Database constraints and
command handlers prevent cross-account foreign-key references.

RLS policies use the token's validated issuer/subject to resolve a Principal and
active membership, for example conceptually:

```sql
exists (
  select 1
  from ledger.account_members m
  where m.account_id = resource.account_id
    and m.principal_id = private.current_principal_id()
    and m.revoked_at is null
)
```

The exact helper implementation must avoid policy recursion, use a fixed search
path, expose no sensitive lookup results, and be benchmarked with membership and
`account_id` indexes.

## Financial Access

Role and financial visibility remain distinct. The target supports full,
limited-by-approved-category, and no company-financial access as defined by the
product spec.

Security requirements:

- filtering occurs before PowerSync download, not only in Swift;
- RLS uses the same authoritative permission facts;
- mixed Invoices follow the approved all-or-nothing or redaction policy;
- missing/ambiguous revenue metadata fails closed;
- restricted counts, totals, names, search hits, and operation results do not
  leak protected facts;
- reporting and MCP use the same visibility policy; and
- permission changes are auditable and take effect on reconnect/download.

If a screen requires both visible and hidden content to compute a total, the
server must provide a visibility-safe projection rather than downloading hidden
source rows and filtering locally.

Search indexes, reports, exports, MCP resources, bulk getters, and analytics are
authorization boundaries, not harmless formatting layers. Named projection
profiles enumerate permitted fields; clients cannot request arbitrary raw
columns or `full` canonical rows. Export artifacts carry their visibility scope
and never include private Storage paths, expiring bearer URLs, hidden-row counts,
or inferred totals. Temporary PDF/CSV files use protected storage and an
explicit cleanup/retention policy.

## Invite and Membership Administration

Invite possession is not Account membership and an email address is not a
Principal. Invite preview is rate-limited and non-enumerating and reveals only
the minimum Account display information needed for informed acceptance. The
database stores a one-way digest of a high-entropy, single-use, expiring token;
raw invite secrets are delivered out of band and never synchronized to clients,
logged, included in MCP resources, or returned after creation.

Invite create/revoke/accept and member-access changes are typed trusted
commands. Each handler derives the actor from the validated Auth identity,
checks active Account membership and the exact administrative capability,
validates proposed role/financial-category grants, prevents unsafe last-owner or
self-lockout transitions, and records append-oriented audit evidence. Acceptance
binds the authenticated Principal exactly once and cannot use an email match as
authorization. Enumeration, replay, expired, revoked, cross-account and
already-used tokens fail closed with stable redacted results.

The normal Account catalog contains only the caller's authorized Account and
membership/capability summary. Member and pending-invite directories require a
separate administration capability and Sync Stream; Auth subjects, raw secrets
and token digests never download.

## RLS Policy Standards

1. RLS is enabled on every exposed or tenant-bearing table.
2. Explicit grants are reviewed separately from policies.
3. Policies name the operation and role explicitly.
4. `TO authenticated` is paired with actual authorization predicates.
5. Update policies have both `USING` and `WITH CHECK`, plus a select policy.
6. Account ownership columns cannot be reassigned by ordinary updates.
7. User-editable metadata is never used for authorization.
8. Views exposed to app roles are security-invoker views.
9. `SECURITY DEFINER` is exceptional, private, search-path-pinned, explicitly
   granted, and advisor/test reviewed.
10. RLS tests cover positive, negative, cross-tenant, revoked, anonymous,
    expired-token, limited-financial, and ambiguous-metadata cases.

Service-role and database-owner credentials bypass RLS and are therefore not a
shortcut for ordinary application code.

## Sync Stream Authorization

PowerSync download authorization mirrors RLS but is independently tested.

- `auth.user_id()`/signed claims resolve an Auth identity.
- Identity maps to a Principal and active memberships.
- Subscription parameters may request a project but cannot grant it.
- Financial restrictions are applied in stream queries or safe source
  projections before rows reach the PowerSync service/client.
- Membership revocation removes future entitlement and rows when the device
  reconnects.
- Stream configuration is version controlled and deployed with security tests.

Any RLS change that does not have a corresponding Sync Stream review is
incomplete.

## Command Authorization

Every trusted command handler performs, in order:

1. token validation at the platform boundary;
2. Auth identity to Principal resolution;
3. active account membership check;
4. command-specific role/financial capability check;
5. scope relationship check for every referenced entity;
6. authority/contract version check;
7. state and concurrency precondition checks;
8. idempotency claim/payload-hash validation; and
9. atomic mutation plus result/audit creation.

The actor stored in audit is derived from authenticated context. A payload's
`actorPrincipalId` is correlation evidence and must match the resolved actor.

## Authentication Transition Security

### Optional Firebase Auth integration

These controls apply only if proposed decision A-007 selects Firebase Auth for
the target launch. They do not create a Firebase application-data adapter.

- Register only the intended Firebase project with Supabase Third-Party Auth.
- Add the authenticated role claim through trusted Firebase administration.
- Refresh existing users' tokens after claims change.
- Configure PowerSync to validate the Firebase audience and signing keys.
- Resolve issuer and subject to a Ledger Principal.
- Keep token lifetime and refresh behavior observable.

### Supabase Auth migration

- Preserve Principal identity while adding the new issuer/subject mapping.
- Rehearse password and Google identity migration separately.
- Do not base authorization on `raw_user_meta_data`/user metadata.
- Revoke or expire old provider sessions before removing the Firebase identity
  mapping.
- Verify PowerSync cached-token and key-rotation behavior during rollout.

## Offline Local-Data Security

Offline availability creates an explicit bounded risk: a disconnected device
cannot receive revocation.

Required controls:

- encrypt the local database with a Keychain-held per-principal/environment key;
- use platform data-protection classes for pending media;
- require device unlock and optionally app biometric re-entry according to
  approved policy;
- enforce the approved offline-access lease before opening sensitive data;
- apply the pending-operation/media disposition policy before voluntary
  signout/account removal, then remove the database and key only after work is
  synchronized/resolved or the user explicitly confirms destructive discard;
- never include local database files in insecure logs or support bundles;
- redact notifications and previews where financial visibility requires it;
- clear signed URLs and protected caches after logout cleanup is permitted; and
- document backup/restore behavior so Keychain and database copies cannot become
  permanently mismatched.

The product/security team must choose the lease duration. Until then, tests
must treat it as a configurable policy rather than hard-code an assumption.

## Storage Security

- Buckets are private unless a reviewed product requirement says otherwise.
- Object paths begin with an immutable account ID and validated entity/attachment
  ID components.
- Clients cannot choose paths outside their authorized account prefix.
- MIME type, extension, size, and checksum are validated independently of the
  filename.
- Access uses authenticated requests or short-lived signed URLs.
- Storage policies mirror active account membership and financial restrictions
  where attachments inherit restricted parent visibility.
- Upsert requires select, insert, and update permissions; delete is preferably a
  trusted retention command.
- Unreferenced-object cleanup uses a quarantine/retention window, not immediate
  deletion.
- Production and staging buckets have distinct credentials and hard guards.

## MCP and Service Security

The MCP service may operate with a server credential, but it must authenticate
the calling user/agent and resolve the same Principal/membership/capability as
the app. Every mutating MCP tool maps to a versioned domain command.

Requirements:

- no unscoped “run arbitrary SQL” production tool;
- no hidden bypass of financial visibility;
- no hard-coded production project/bucket fallback;
- service identity and human actor both recorded;
- per-tool least privilege and rate limits;
- structured audit with redacted payload handling; and
- explicit separation between ordinary tools and reviewed repair/migration
  commands.

## Secrets and Environment Isolation

- Client builds contain only publishable client configuration.
- Service-role, database passwords, JWT signing material, migration credentials,
  and Storage admin keys are secret-manager/IAM controlled.
- Local, staging, and production use different projects, PowerSync instances,
  buckets, bundle identifiers, URL schemes, and credentials.
- Startup verifies all resolved resources belong to the same environment.
- Staging credentials have no production IAM.
- Migration tools require explicit environment, source, destination, account,
  mode, manifest, and production acknowledgment.
- Logs print resource identifiers safe for diagnosis but never secret values.

## Audit Requirements

Append-oriented audit covers:

- command actor, service, version, idempotency ID, and outcome;
- membership/role/financial-permission changes;
- Invoice collection and corrections;
- Transfer creation and reversal;
- paid Item credit/refund actions;
- privileged MCP/admin operations;
- migration run and per-record correlation; and
- authorization denials or suspicious cross-scope attempts at an appropriate
  sampled/rate-limited level.

Audit records preserve business identifiers and hashes needed for proof without
copying unnecessary sensitive payloads.

## Security Review Gate

Before production activation:

- threat model and data classification are reviewed;
- every table/view/function has grants and RLS evidence;
- Sync Stream and RLS results match for the full role matrix;
- financial-access negative tests prove no row/count/total leakage;
- service-role and migration credentials are inventoried;
- local encryption/logout/offline-lease behavior passes device tests;
- Storage read/write/delete policies pass path and inheritance tests;
- Supabase advisors contain no unresolved security finding; and
- an operator can revoke a member, reconnect a device, and demonstrate data and
  write removal behavior.
