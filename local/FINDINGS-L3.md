# L3 — First-admin bootstrap probe

Date: 2026-08-12  
Stack: `COMPOSE_PROJECT_NAME=paperclip-l3`, host port **3110**  
Image: `ghcr.io/paperclipai/paperclip:sha-e55d702`  
Override: `local/docker-compose.l3.yml`

## Doc contradiction — which is correct?

| Doc | Claim | Empirical result |
|-----|--------|------------------|
| `doc/DEPLOYMENT-MODES.md` §8 | Fresh `authenticated/public` stays `bootstrap_pending`; browser self-claim disabled; use CLI bootstrap invite | **Correct** |
| `docs/deploy/aws-ecs.md` | First UI signup grants admin, then lock down | **Stale** |

UI signup without invite created `l3-nosignup-admin@example.com` with **no** `instance_user_roles` row.  
Invite accept created `l3-invite-admin@example.com` with **`instance_admin`**.

**Plan impact:** Keep T14 / Cloud Run Job that runs `paperclipai auth bootstrap-ceo`. Do not rely on first signup.

## CLI path (Cloud Run design)

1. Without config: `pnpm paperclipai auth bootstrap-ceo --base-url …` fails with  
   `No config found at /paperclip/instances/default/config.json`.
2. Server can boot from env alone and does **not** write that file.
3. Seed a config with `"$meta.source": "configure"` (reader rejects `edited-by-hand`).
4. Verified template: `config/bootstrap-config.template.json` (also mirrored by `local/bootstrap-admin.sh`).
5. Accept invite via API (in-container Origin `http://localhost:3100`):  
   `POST /api/invites/{token}/accept` with `{"requestType":"human"}` → user becomes `instance_admin`, bootstrap ready.
6. With `PAPERCLIP_AUTH_DISABLE_SIGN_UP=true`, signup returns `EMAIL_PASSWORD_SIGN_UP_DISABLED`; CLI can still mint invites; invite GET/accept still works.

## Operational gotcha — host port vs auth base URL

Compose `env_file: .env` alone kept `PAPERCLIP_PUBLIC_URL=http://localhost:3100` even when host mapped `:3110`. Auth rewrites/validates against the **listen** port **3100** inside the container (`rewriteLocalUrlPort`).

- Host browser on `:3110` → **Invalid origin** unless Origin matches the in-container public URL.
- For non-default host ports, set `PAPERCLIP_PUBLIC_URL` / `PAPERCLIP_API_URL` via compose `environment:` override **and** prefer in-container Origin `:3100` for API probes.

## Deliverables

- `config/bootstrap-config.template.json` — placeholders for Cloud Run Job config seed
- Merged into `local/FINDINGS.md` under **First-admin bootstrap**
