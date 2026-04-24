# AC108 Shutdown Fix — Agent Context

## Effort identity

This is the `ac108-shutdown-fix` branch on `TSheahan/seeed-voicecard`, forked from `HinTak/seeed-voicecard` branch `v6.12`. It fixes sleeping-in-atomic bugs in the ALSA trigger path of the AC108 codec driver and seeed-voicecard machine driver that cause a Raspberry Pi reboot when an ALSA PCM stream closes on process exit. The end goal is an upstream pull request to `HinTak/seeed-voicecard`.

## Start here

Read [`ac108_shutdown_crash_analysis.md`](ac108_shutdown_crash_analysis.md) before starting any work. It contains the full technical analysis: five questions answered with source citations, four sleeping-in-atomic bugs identified, six recommended fixes with dependency ordering, and five uncertainties requiring runtime resolution.

## Effort phases

| Phase | Name | Status | Goal |
|---|---|---|---|
| 1 | Instrumentation | **done** | Hypothesis confirmed with runtime evidence. See `analysis/executions/2026-04-03_22-18-50_dmesg.txt`. |
| 2 | Fix | **done** | F1–F4 written and validated. Single-cycle test clean: zero BUG, no Oops, no panic. See [`analysis/executions/2026-04-03_22-58-41_report.md`](executions/2026-04-03_22-58-41_report.md). F5 (error handling) deferred. F6 (ac101 spinlock) confirmed moot after F4. |
| 3 | Validate | **done** | V1: 6 clean cycles (zero BUG). V2: Python workarounds removed. V3: 2 clean runs with workarounds gone. |
| 4 | PR | **done** | Submitted to `HinTak/seeed-voicecard` targeting `v6.12`. Two commits: F1–F4 fix + F5 hardening. References issue #22. |

## Work items

| ID | Description | Phase | Status | Depends on |
|---|---|---|---|---|
| I1 | Add `dev_err` to `seeed_voice_card_trigger` TRIGGER_START / TRIGGER_STOP with context (irqs_disabled, in_atomic, path) | 1 | done | — |
| I2 | Add `dev_err` to `ac108_aif_shutdown` entry/exit | 1 | done | — |
| I3 | Add `dev_err` to `ac108_set_clock` entry/exit with `y_start_n_stop`, irqs_disabled, in_atomic, sysclk_en | 1 | done | — |
| I4 | Add `pr_err` to `work_cb_codec_clk` entry/exit with try_stop, rescheduling | 1 | done | — |
| I+ | Add `dev_err` to `seeed_voice_card_shutdown` entry/exit | 1 | done | — |
| I5 | Rebuild module, load on Pi, reproduce crash, capture dmesg via serial console or pstore | 1 | done | I1–I4 |
| U1 | Resolve: does PortAudio drain after paComplete? (count TRIGGER_STOP events in dmesg) | 1 | resolved | I5 |
| U2 | Resolve: does sleeping-in-atomic cause reboot directly or via cascading corruption? | 1 | resolved | I5 |
| U3 | Resolve: does AC101 contribute I2C writes on the teardown path? (read `ac101.c`) | 1 | resolved | — |
| U5 | Resolve: I2C IRQ affinity on Pi 4 (`cat /proc/irq/*/smp_affinity_list`) | 1 | deferred | — |
| F1 | Fix 1: unconditional workqueue deferral in TRIGGER_STOP (`seeed-voicecard.c` TRIGGER_STOP case) | 2 | done | I5 |
| F2 | Fix 2: `cancel_work_sync` in `seeed_voice_card_shutdown` | 2 | done | F1 |
| F3 | Fix 3: move `cancel_work_sync` from TRIGGER_START to `startup` callback | 2 | done | — |
| F4 | Fix 4: move `_set_clock(1,...)` from TRIGGER_START to new `prepare` callback | 2 | done | — |
| F1-F4-test | Test F1–F4: deploy to Pi, reproduce scenario, confirm no BUG/crash | 2 | done | F1–F4 |
| F5 | Fix 5: error handling in `ac108_multi_write` (`ac108.c`) | 2 | done | — |
| F6 | Fix 6: fix `ac101_trigger(START)` I2C under spinlock (`ac101.c:1271–1282`) | 2 | skipped | — |
| V1 | Sustained Pi testing: 5+ wake-capture-STT-shutdown cycles without crash | 3 | done | F1-F4-test |
| V2 | Remove Python workarounds in raspberry-ai (paComplete flag, monkey-patches, `os._exit`) | 3 | done | V1 |
| V3 | Re-test after Python workaround removal | 3 | done | V2 |
| PR1 | Create clean branch from `upstream/v6.12`, cherry-pick fix commits only | 4 | done | V1 |
| PR2 | Write PR description from analysis document | 4 | done | PR1 |
| PR3 | Submit PR to `HinTak/seeed-voicecard` | 4 | done | PR2 |

**All phases complete.** PR submitted to `HinTak/seeed-voicecard` targeting `v6.12`. Awaiting maintainer review. See [`analysis/pr_description.md`](pr_description.md) for the PR text.

### Summary of F1–F4 changes (all in `seeed-voicecard.c`)

| Fix | What changed | Why |
|---|---|---|
| F1 | TRIGGER_STOP: removed `in_irq()` conditional, always `schedule_work` | `_set_clock(0)` does I2C (sleeps) — must not run under stream lock |
| F2 | `seeed_voice_card_shutdown`: added `cancel_work_sync` before teardown | Drains F1's deferred work before `ac108_aif_shutdown` races with it |
| F3 | `seeed_voice_card_startup`: added `cancel_work_sync`; removed from TRIGGER_START | `cancel_work_sync` can sleep — must not run under stream lock |
| F4 | New `seeed_voice_card_prepare` callback: runs `_set_clock(1)`; TRIGGER_START is now empty | `_set_clock(1)` does I2C (sleeps) — moved to prepare (process ctx, no lock) |

After F1–F4, `seeed_voice_card_trigger` performs **zero sleeping operations** in either START or STOP. All I2C happens in `prepare` (start) or on the system workqueue (stop).

### Resolved uncertainties

#### U1 — Does PortAudio drain after paComplete?
**Yes.** Only one TRIGGER_STOP event in the entire session, triggered via `snd_pcm_drop` from `snd_pcm_common_ioctl` (PortAudio's explicit drain after paComplete). No second TRIGGER_STOP from `snd_pcm_release` during FD close. This means PortAudio successfully drains the stream before `os._exit(0)`.

#### U2 — Direct reboot or cascading corruption?
**Cascading corruption.** The first BUG fires at TRIGGER_START (t=299.352) — the I2C transfer completes successfully (another core services the IRQ), `ac108_set_clock` returns `ret=0`, but scheduler state is corrupted (preempt_count=2 during `schedule()`). A second BUG fires immediately in a `ppoll` syscall (corrupted scheduler internals). The system runs for 37 seconds with corrupted state (recording, STT, wake word detection all succeed). TRIGGER_STOP (t=336.217) fires a third BUG, and immediately after `ac108_set_clock EXIT`, the kernel Oopses: `Unable to handle kernel paging request at virtual address 0000007f948876e8` — the kernel jumped to a userspace address during a context switch (corrupted saved registers from `schedule()` with preemption disabled). Ends in `Kernel panic - not syncing: Aiee, killing interrupt handler!`.

#### U3 — AC101 role in teardown path
`ac101_trigger()` has an **empty case** for TRIGGER_STOP/SUSPEND/PAUSE_PUSH (`ac101.c:1285–1288`) — it performs zero I2C writes on the stop path. `ac101_aif_shutdown()` (`ac101.c:951–967`) does perform 3–4 I2C writes via `ac101_aif1clk(POST_PMD)`, but this runs from the ALSA `.shutdown` callback (process context, not atomic), so it is safe. On the ReSpeaker 4-Mic Array HAT, `i2c101` is expected non-NULL (`ac108.c:1435–1436` sets it when AC101 probes successfully; `ac10x.h:27` sets `_MASTER_MULTI_CODEC == _MASTER_AC101`). **Net impact on the fix plan:** AC101 does not contribute sleeping-in-atomic bugs on the teardown path.

### F6 disposition — skipped

F6 originally targeted two sleeping-in-atomic sites in codec trigger START paths. Both are skipped from this PR:

**F6a — `ac101_trigger(START)` I2C under spinlock (`ac101.c:1271–1282`):** Moot after F4. `ac101_trigger(START)` is called from `ac108_set_clock(1)`, which F4 moved from `seeed_voice_card_trigger` to `seeed_voice_card_prepare` (process context). The spinlock still acquires `spin_lock_irqsave`, but I2C completes safely because `prepare` does not hold the stream lock and the BCM2835 I2C IRQ is serviced on another core. Zero BUG traces across 8 test runs.

**F6b — `ac108_trigger(START)` I2C under spinlock (`ac108.c:1074–1081`):** Latent, condition-gated. The codec DAI's own trigger callback acquires `spin_lock_irqsave`, reads `I2S_CTRL` (hits `REGCACHE_FLAT` — no I2C, safe), and conditionally writes via `ac108_multi_update_bits` only if `BCLK_IOEN=1 && LRCK_IOEN=0`. This guard condition was never true in any test run. If it were true, the I2C write would sleep under stream lock + spinlock — a genuine sleeping-in-atomic bug. However: the condition appears to be an edge-case safeguard that doesn't fire during normal ReSpeaker 4-Mic HAT operation, and fixing it properly requires moving the logic to an `ac108_prepare` codec callback (non-trivial refactoring in `ac108.c`). Not worth the scope expansion for a path that has never been observed to execute.

**PR note:** Mention F6b as a known latent issue in the PR description. If the maintainer wants it addressed, it can be a follow-up.

## PR preparation

**Structure:** One PR, two commits.

| Commit | Scope | Content |
|---|---|---|
| 1 | `seeed-voicecard.c` | F1–F4: fix sleeping-in-atomic in ALSA trigger path (workqueue deferral, prepare callback, cancel_work_sync) |
| 2 | `ac108.c` | F5: error handling in `ac108_multi_write` (hardening) |

F6 (ac101 spinlock I2C) confirmed moot after F4 — not included.

**Timing:** After V2+V3 (Python workaround removal and re-test).

Checklist:

- [ ] Clean branch from `upstream/v6.12`, no `analysis/`, no instrumentation
- [ ] Commit 1: F1–F4 as single atomic commit
- [ ] Commit 2: F5 as separate hardening commit
- [ ] Testing evidence: before/after dmesg in PR description
- [ ] Scope discipline: minimum changes, no style/refactoring
- [ ] Commit message convention: match existing repo style (`git log --oneline`)
- [ ] PR description: problem statement, root cause, fix summary, test results
- [ ] Target: `HinTak/seeed-voicecard` branch `v6.12`

## Cross-references

| Document | Location | Content |
|---|---|---|
| AC108 shutdown crash analysis | [`analysis/ac108_shutdown_crash_analysis.md`](ac108_shutdown_crash_analysis.md) | Full technical analysis: Q1–Q5, bugs, fixes, uncertainties |
| Driver repo roadmap | [`analysis/2026-04-03_driver_repo_roadmap.md`](2026-04-03_driver_repo_roadmap.md) | File map and reading guide for this repo |
| Investigation handoff | [`analysis/2026-04-03_investigation_handoff.md`](2026-04-03_investigation_handoff.md) | How the investigation evolved (I2S revelation, workstream history) |
| Python-side interface brief | `raspberry-ai/mvp-modules/forked_assistant/archive/2026-04-03_python_alsa_interface_brief.md` | Python/PortAudio side of the ALSA interface |
| First crash report | [`analysis/executions/2026-04-03_22-18-50_report.md`](executions/2026-04-03_22-18-50_report.md) | Detailed analysis: timeline, BUG traces, uncertainty resolutions, fix priority revision |
| First crash dmesg | [`analysis/executions/2026-04-03_22-18-50_dmesg.txt`](executions/2026-04-03_22-18-50_dmesg.txt) | Raw dmesg: 3× BUG scheduling while atomic → kernel Oops → panic |
| First crash app log | [`analysis/executions/2026-04-03_22-18-50_master_py.txt`](executions/2026-04-03_22-18-50_master_py.txt) | Python-side log showing full wake-capture-STT cycle before crash |
| F1–F4 validation report | [`analysis/executions/2026-04-03_22-58-41_report.md`](executions/2026-04-03_22-58-41_report.md) | Clean pass: zero BUG, no Oops, all four fixes confirmed working |
| F1–F4 validation dmesg | [`analysis/executions/2026-04-03_22-58-41_dmesg.txt`](executions/2026-04-03_22-58-41_dmesg.txt) | Clean dmesg: prepare in process ctx, workqueue deferral, clean shutdown |
| Executions index | [`analysis/executions/AGENTS.md`](executions/AGENTS.md) | Summary and routing for all execution captures |
