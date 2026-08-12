# L6 — WebSockets, shutdown, heartbeat concurrency

Date: 2026-08-12  
Stack: `COMPOSE_PROJECT_NAME=paperclip-l6`, host port **3130**  
Second scheduler: `paperclip-l6-paperclip-b` on same network/DB, `HEARTBEAT_SCHEDULER_ENABLED=true`  
Image: `ghcr.io/paperclipai/paperclip:sha-e55d702`

## 1. Live-events WebSocket (revision / restart)

Endpoint: `/api/companies/{companyId}/events/ws` (auth required — unauthenticated upgrade → **403**).

Empirical (session cookie, Origin `http://localhost:3100`):

| Step | Result |
|------|--------|
| Connect while healthy | `open` (held 4s) |
| SIGTERM app container while client held | Client `close:1006` after ~3s — **not silent** |
| Reconnect after container healthy again | `open` succeeds |

UI bundle (`ui/dist`): live-events clients **auto-reconnect** — `onclose` → `setTimeout(connect, 1500)`; another path uses exponential backoff capped at **15s**. Dangerous outcome (silent staleness) **not** observed; client reconnects after drop.

**Cloud Run note:** every revision change still drops WS; UI recovers via reconnect. Keep long request timeout (3600s) so idle live connections are not cut early.

## 2. SIGTERM / heartbeat drain vs ~10s Cloud Run grace

Prior measurement on this stack: clean exit in **~0.64s** with log `graceful heartbeat run drain complete`.

**Verdict:** under Cloud Run ~10s grace — **no SIGKILL mid-drain finding** for idle/light drain on `sha-e55d702`. Revisit if production routinely has long in-flight heartbeat runs at deploy time.

## 3. Dual-scheduler heartbeat claim concurrency

Both `paperclip-1` and `paperclip-b` ran with Heartbeat enabled (30s tick) against the same Postgres. Agent `Heartbeat Probe` policy set to `enabled` + `intervalSec: 30`.

| Metric | Result |
|--------|--------|
| Runs observed | 13+ timer invocations over ~8+ minutes |
| Near-simultaneous duplicates (`|Δt| < 2s`, same agent) | **0** |
| Both schedulers enqueued | Yes (both logged `heartbeat timer tick enqueued runs`) |

Claim path appears **idempotent in practice** under brief dual-scheduler overlap (Cloud Run traffic migration stand-in). No evidence of double-claimed runs in `heartbeat_runs`.

**Plan impact:** Do **not** escalate R3 solely for double-claim; normal Cloud Run traffic migration remains acceptable from this probe. Still expect brief dual schedulers during rollout.

## Deliverables

Merged into `local/FINDINGS.md` under **Realtime and shutdown**.
