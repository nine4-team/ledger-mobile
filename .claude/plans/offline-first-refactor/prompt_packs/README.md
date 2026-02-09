# Offline-First Refactor — Prompt Packs

Self-contained, copy-paste-ready prompts for AI dev chats. See `../plan.md` for the overall plan and execution order.

**Chat A must complete before starting B-G.** Chats B-G are independent and can run in parallel.

- `chat_a_service_layer.md` — Service function signatures + missing `trackPendingWrite`
- `chat_b_item_screens.md` — Item detail, edit, and create screens
- `chat_c_transaction_screens.md` — Transaction detail, edit, and create screens
- `chat_d_space_screens.md` — Space detail screens + `SpaceSelector`
- `chat_e_project_screens.md` — Project create, edit, shell, and `createProject` refactor
- `chat_f_settings_and_budget.md` — Settings tab + budget category management
- `chat_g_shared_and_request_docs.md` — `SharedItemsList`, inventory operations, `resolveItemMove`
