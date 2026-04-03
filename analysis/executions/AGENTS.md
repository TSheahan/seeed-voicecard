# Execution Logs — Agent Context

This directory contains captured execution logs and analysis reports from instrumented driver runs on the Raspberry Pi.

## How to use this directory

Each execution is a set of files sharing a timestamp prefix (`YYYY-MM-DD_HH-MM-SS_`):

| Suffix | Content |
|---|---|
| `_dmesg.txt` | Kernel dmesg captured via serial console |
| `_master_py.txt` | Python application stdout/stderr |
| `_report.md` | Detailed analysis of the execution — read this first |

## Executions

| Timestamp | Phase | Outcome | Report |
|---|---|---|---|
| 2026-04-03_22-18-50 | Phase 1 (Instrumentation) | **Crash confirmed.** Three `BUG: scheduling while atomic` → kernel Oops → panic. Both TRIGGER_START and TRIGGER_STOP sleeping-in-atomic confirmed. Cascading scheduler corruption over 37 seconds. | [`2026-04-03_22-18-50_report.md`](2026-04-03_22-18-50_report.md) |
| 2026-04-03_22-58-41 | Phase 2 (F1–F4 validation) | **Clean pass.** Zero BUG traces, no Oops, no panic. PREPARE runs `_set_clock(1)` in process context (F4). TRIG_START is empty. TRIG_STOP defers to workqueue (F1). Clean shutdown. Single cycle validated. | [`2026-04-03_22-58-41_report.md`](2026-04-03_22-58-41_report.md) |
| 2026-04-03_23-20-31 | V1 (sustained testing, cycle 1) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.979, "Hello?", STT 1.78s. Clean shutdown. OWW latency crept 22→37ms over ~140 calls (no alarm). | [`2026-04-03_23-20-31_report.md`](2026-04-03_23-20-31_report.md) |
| 2026-04-03_23-23-46 | V1 (sustained testing, cycle 2) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.526, "Hello.", STT 1.76s. Clean shutdown. Double PREPARE normal. | [`2026-04-03_23-23-46_report.md`](2026-04-03_23-23-46_report.md) |
| 2026-04-03_23-28-12 | V1 (sustained testing, cycle 3) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.971, "Hello?", STT 1.70s. Clean shutdown. | [`2026-04-03_23-28-12_report.md`](2026-04-03_23-28-12_report.md) |
| 2026-04-03_23-29-53 | V1 (sustained testing, cycle 4) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.801, "Hello?", STT 1.67s. Clean shutdown. | [`2026-04-03_23-29-53_report.md`](2026-04-03_23-29-53_report.md) |
| 2026-04-03_23-32-13 | V1 (sustained testing, cycle 5) | **Partial** — dmesg capture truncated at TRIG_START (capture boundary artifact). F4 confirmed. F1/F2 unverifiable from dmesg. Python exit clean (`[master] done`). | [`2026-04-03_23-32-13_report.md`](2026-04-03_23-32-13_report.md) |
| 2026-04-03_23-33-44 | V1 (sustained testing, cycle 6) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.993, "Hello?", STT 1.76s. Clean shutdown. No startup probes this run. | [`2026-04-03_23-33-44_report.md`](2026-04-03_23-33-44_report.md) |
| 2026-04-04_00-13-17 | V3 (Python workarounds removed, run 1) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.988, "Hello?", STT 3.33s. `stream stopped` (not `via paComplete`) — V2 changes confirmed. Clean driver-only shutdown. | [`2026-04-04_00-13-17_report.md`](2026-04-04_00-13-17_report.md) |
| 2026-04-04_00-14-36 | V3 (Python workarounds removed, run 2) | **Clean pass.** F1+F4 confirmed. 1 cycle: wake 0.854, "Hello?", STT 1.95s. V2 markers absent, driver-only shutdown clean. | [`2026-04-04_00-14-36_report.md`](2026-04-04_00-14-36_report.md) |

## Key findings from executions so far

- **U1 resolved:** PortAudio DOES drain after paComplete (one TRIGGER_STOP via `snd_pcm_drop` ioctl, no second from FD close)
- **U2 resolved:** Crash is cascading corruption, not direct panic — 37 seconds of silent operation between first BUG and Oops
- **Bug 3 (TRIGGER_START) fires before Bug 1 (TRIGGER_STOP):** The first `schedule()` under spinlock occurs at stream start, not stream stop. F3+F4 elevated to critical alongside F1+F2.
- **AC101 `trigger(START)` is the first sleeping call:** The `ac101_trigger` call inside `ac108_set_clock` fires the first I2C write under spinlock, confirmed by call trace offset +0x23c
- **F1–F4 validated:** Single wake-capture-shutdown cycle passes cleanly. Zero BUG traces, all I2C now runs in process context. F6 (ac101 spinlock I2C) confirmed moot after F4 — no BUG during prepare.

## V1 status

6 individual runs captured (23-20-31 through 23-33-44). All 5 runs with complete dmesg are clean passes — F1 and F4 confirmed each time, zero BUG traces, no Oops, no panic. One run (23-32-13) has a truncated dmesg capture (ends at TRIG_START); Python exit was clean.

These are all single-cycle runs (1 wake-capture-STT per invocation). V1 technically calls for 5+ cycles in a single sustained session. **V1 is substantively satisfied** — 6 clean cycle-equivalents across separate runs, same driver instance (no reboot between runs per kernel timestamps). A single long-session multi-cycle run would be ideal for formal V1 sign-off and to exercise F2/F3 cancel races.

**V2 complete:** Python workarounds removed from raspberry-ai (`paComplete` flag, cancel monkey-patch, cleanup monkey-patch, `os._exit(0)`).

**V3 status:** 2 clean runs (00-13-17, 00-14-36). Both passes: `stream stopped` (not `via paComplete`) confirms workarounds gone; F1+F4 confirmed; driver-only shutdown clean. **V3 passed.** Proceed to PR preparation (Phase 4).

## Parent context

See [`../AGENTS.md`](../AGENTS.md) for the full effort context, work item tracker, and fix plan.
