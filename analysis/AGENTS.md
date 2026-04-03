# AC108 Shutdown Fix — Agent Context

## Effort identity

This is the `ac108-shutdown-fix` branch on `TSheahan/seeed-voicecard`, forked from `HinTak/seeed-voicecard` branch `v6.12`. It fixes sleeping-in-atomic bugs in the ALSA trigger path of the AC108 codec driver and seeed-voicecard machine driver that cause a Raspberry Pi reboot when an ALSA PCM stream closes on process exit. The end goal is an upstream pull request to `HinTak/seeed-voicecard`.

## Start here

Read [`ac108_shutdown_crash_analysis.md`](ac108_shutdown_crash_analysis.md) before starting any work. It contains the full technical analysis: five questions answered with source citations, four sleeping-in-atomic bugs identified, six recommended fixes with dependency ordering, and five uncertainties requiring runtime resolution.

## Effort phases

| Phase | Name | Status | Goal |
|---|---|---|---|
| 1 | Instrumentation | **current** | Add `dev_err`/`pr_info` to trigger and shutdown callbacks. Resolve uncertainties U1–U5 via dmesg / serial console. Confirm the sleeping-in-atomic hypothesis with runtime evidence before committing to fixes. |
| 2 | Fix | pending | Apply Fixes 1–6 in recommended order. Each fix is a separate commit (atomic, reviewable). Test after Fix 1+2 (the critical pair) before proceeding to Fix 3–6. |
| 3 | Validate | pending | Sustained testing on the Pi: multiple wake-capture-STT-shutdown cycles without reboot. Remove Python workarounds in raspberry-ai (`paComplete` flag, cancel monkey-patch, cleanup monkey-patch, `os._exit(0)`) once driver shutdown is confirmed clean. |
| 4 | PR | pending | Produce a clean branch from `upstream/v6.12` with fix commits only (no `analysis/`, no instrumentation). Write PR description drawing from the analysis document. Submit to `HinTak/seeed-voicecard`. |

## Work items

| ID | Description | Phase | Status | Depends on |
|---|---|---|---|---|
| I1 | Add `dev_err` to `seeed_voice_card_trigger` TRIGGER_START / TRIGGER_STOP with timestamps | 1 | pending | — |
| I2 | Add `dev_err` to `ac108_aif_shutdown` entry/exit | 1 | pending | — |
| I3 | Add `dev_err` to `ac108_set_clock` entry/exit with `y_start_n_stop` value | 1 | pending | — |
| I4 | Add `dev_err` to `work_cb_codec_clk` entry/exit | 1 | pending | — |
| I5 | Rebuild module, load on Pi, reproduce crash, capture dmesg via serial console or pstore | 1 | pending | I1–I4 |
| U1 | Resolve: does PortAudio drain after paComplete? (count TRIGGER_STOP events in dmesg) | 1 | pending | I5 |
| U2 | Resolve: does sleeping-in-atomic cause reboot directly or via cascading corruption? | 1 | pending | I5 |
| U3 | Resolve: does AC101 contribute I2C writes on the teardown path? (read `ac101.c`) | 1 | pending | — |
| U5 | Resolve: I2C IRQ affinity on Pi 4 (`cat /proc/irq/*/smp_affinity_list`) | 1 | pending | — |
| F1 | Fix 1: unconditional workqueue deferral in TRIGGER_STOP | 2 | pending | I5 |
| F2 | Fix 2: `cancel_work_sync` in `seeed_voice_card_shutdown` | 2 | pending | F1 |
| F1F2-test | Test Fix 1+2: reproduce crash scenario, confirm no reboot | 2 | pending | F1, F2 |
| U4 | Resolve: does the crash survive Fix 1+2? | 2 | pending | F1F2-test |
| F3 | Fix 3: move `cancel_work_sync` from TRIGGER_START to `startup` callback | 2 | pending | F1F2-test |
| F4 | Fix 4: move `_set_clock(1,...)` from TRIGGER_START to `prepare` callback | 2 | pending | F1F2-test |
| F5 | Fix 5: error handling in `ac108_multi_write` | 2 | pending | — |
| F6 | Fix 6: fix conditional I2C write in `ac108_trigger` TRIGGER_START (if applicable) | 2 | pending | U3 |
| V1 | Sustained Pi testing: 5+ wake-capture-STT-shutdown cycles without crash | 3 | pending | F1, F2 |
| V2 | Remove Python workarounds in raspberry-ai (paComplete flag, monkey-patches, `os._exit`) | 3 | pending | V1 |
| V3 | Re-test after Python workaround removal | 3 | pending | V2 |
| PR1 | Create clean branch from `upstream/v6.12`, cherry-pick fix commits only | 4 | pending | V1 |
| PR2 | Write PR description from analysis document | 4 | pending | PR1 |
| PR3 | Submit PR to `HinTak/seeed-voicecard` | 4 | pending | PR2 |

**Next item to pick up:** I1 (instrument `seeed_voice_card_trigger`). This is the foundation — all subsequent work depends on dmesg evidence from instrumented runs.

## PR preparation

Checklist tracking readiness for upstream submission:

- [ ] Fix commits: one per fix, clean commit messages referencing the bug (sleeping-in-atomic, workqueue race)
- [ ] Testing evidence: dmesg logs showing the bug before and after fix, crash reproduction steps
- [ ] Scope discipline: minimum changes needed, no refactoring, no style changes unrelated to the bug
- [ ] Commit message convention: match existing seeed-voicecard commit style (see `git log --oneline` for examples)
- [ ] PR description: concise problem statement, root cause analysis (from analysis doc), fix summary, test results
- [ ] Target: `HinTak/seeed-voicecard` branch `v6.12`
- [ ] Clean branch: `analysis/` directory and instrumentation commits excluded

## Cross-references

| Document | Location | Content |
|---|---|---|
| AC108 shutdown crash analysis | [`analysis/ac108_shutdown_crash_analysis.md`](ac108_shutdown_crash_analysis.md) | Full technical analysis: Q1–Q5, bugs, fixes, uncertainties |
| Driver repo roadmap | [`analysis/2026-04-03_driver_repo_roadmap.md`](2026-04-03_driver_repo_roadmap.md) | File map and reading guide for this repo |
| Investigation handoff | [`analysis/2026-04-03_investigation_handoff.md`](2026-04-03_investigation_handoff.md) | How the investigation evolved (I2S revelation, workstream history) |
| Python-side interface brief | `raspberry-ai/mvp-modules/forked_assistant/archive/2026-04-03_python_alsa_interface_brief.md` | Python/PortAudio side of the ALSA interface |
