# UI kit stash (`src/ui`)

This folder is the **app-only design-system layer** that sits on top of `@nine4/ui-kit`.

## Goals

- Keep using the published UI kit as-is.
- Put **all app-specific tokens/styles/components** in one obvious place.
- Make it easy to graduate changes into `@nine4/ui-kit` later.

## Rules

- If you need a new token (ex: screen content top padding), add it to `src/ui/**`.
- Mark anything intended for graduation with **`TODO(ui-kit): ...`**.
- Run `npm run ui:check` to ensure `TODO(ui-kit):` only exists inside `src/ui/**`.

