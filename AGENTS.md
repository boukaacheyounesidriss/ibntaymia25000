<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.

## What Lovable manages

Rules outside this block are the project's own. Change the pieces below in
Lovable, not by hand. With the [Lovable MCP](https://mcp.lovable.dev)
connected, `send_message` asks Lovable to do it; otherwise ask the user to
use the editor.

- **Database.** Do not add or edit `supabase/migrations/` or `drizzle/`.
  Ask Lovable to change the schema.
- **Generated files.** Do not edit a file whose header says it is automatically
  generated.
- **AI gateway.** Keep model calls on Lovable's gateway, and keep
  `LOVABLE_API_KEY` out of browser code.
- **Connectors.** Lovable provides native connectors. `list_connectors` shows
  which are enabled; `add_connector` only returns the dashboard link. When a
  connector is enabled, calls go through the connector gateway and need
  `LOVABLE_API_KEY`. When Lovable does not provide one, users can bring their
  own key and store it in Secrets.
- **Secrets.** Lovable manages them. Do not put secret values in the repo.
<!-- LOVABLE:END -->

- Raw data editors must exclude enrollment decision fields and enforce the same restriction server-side; the dedicated legal workflow owns strike-off decisions.
- Settings groups existing administration pages and offers a browser data export through the authorized backup function; hosted credentials and auth passwords are never included.
- Social OAuth returns to the public login page and navigates to the dashboard only after session confirmation; use the managed broker, Google branding tokens, and original Apple Design Resources artwork for provider buttons.
- Authorize role management through the database's verified immutable owner identity; never through email, editable metadata or an administrator/developer role, to prevent delegation and account takeover.
- Keep built-in enum roles and additive custom role definitions separate; custom roles grant only existing permission capabilities, never implicit built-in role membership or wider data visibility.
- Change built-in account roles atomically through the owner-authorized database function and protect owner credentials in every account administration path.
- Teachers' class membership (class_teachers) is auto-synced from schedule_slots by trigger; teacher-scoped RLS on students depends on it.
- Lab/TD subgroups: students.subgroup (g1/g2) + attendance_sessions.group_scope (all/g1/g2/merged); a DB trigger forbids overlapping scopes per class/date/period, and subgroup/slot-group edits go only through RPCs allowed for management or teachers of that class — keeps G1 and G2 sessions coexisting without double counting.

- Lesson files use private storage with post-reader RLS and author/post-scoped paths; signed URLs must never be persisted in post data so classroom access stays scoped.
- Compress lesson photos only on user selection and keep the original when compression is disabled, fails, or grows the file; do not impose per-teacher quotas, and surface hosting storage failures honestly.
- Digital-advisor navigation explicitly mirrors supervisor pages without adding raw technical access or owner-only role management; keep database authorization independent from menu visibility.
