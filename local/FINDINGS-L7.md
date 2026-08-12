## Sizing (L7)

Date: 2026-08-12  
Stack: `paperclip-local` (L1), container `paperclip-local-paperclip-1` after prior
onboarding + agent activity (Chief of staff / Founding Engineer runs).

### Memory (`docker stats`, ~20s sampling)

| Sample | MemUsage | Mem% | CPU% |
|--------|----------|------|------|
| 0 | 1.107 GiB / 7.653 GiB | 14.47% | 10.43% |
| 1 | 1.113 GiB | 14.55% | 15.65% |
| 2 | 1.107 GiB | 14.47% | 7.95% |
| 3 | 1.114 GiB | 14.56% | 52.64% |
| 4 | 1.118 GiB | 14.61% | 41.77% |
| 5 | 1.106 GiB | 14.45% | 9.74% |

Steady-state under light UI/API hits + live agent work: **~1.11 GiB** reported by
`docker stats`.

cgroup v2 (same container lifetime, includes earlier agent runs):

| Metric | Value |
|--------|-------|
| `memory.current` | **1757.9 MiB** |
| `memory.peak` | **2033.9 MiB** (~2.0 GiB) |

Earlier L1 cold-boot note (~380 MiB idle / ~800 MiB first-boot peak) still useful for
empty boot; **loaded** steady-state with agents is closer to 1.1–1.8 GiB.

### Ephemeral `/paperclip` (counts against Cloud Run memory if tmpfs)

```text
df -h /paperclip  → overlay host FS (local harness); not a size-capped tmpfs here
du -sh /paperclip → 139M total
  85M  instances/
  52M  .npm/
  2.3M .claude/
```

### Verdict

**RSS + `/paperclip` stays well under 3 GiB** (~2.0 GiB cgroup peak + 0.14 GiB disk).
No need to bump the Cloud Run memory plan to 8 GiB based on this harness. Keep
headroom above ~2 GiB for agent-heavy workloads; 4 GiB remains a reasonable default
unless production traffic proves higher.
