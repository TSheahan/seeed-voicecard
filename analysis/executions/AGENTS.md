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

## Key findings from executions so far

- **U1 resolved:** PortAudio DOES drain after paComplete (one TRIGGER_STOP via `snd_pcm_drop` ioctl, no second from FD close)
- **U2 resolved:** Crash is cascading corruption, not direct panic — 37 seconds of silent operation between first BUG and Oops
- **Bug 3 (TRIGGER_START) fires before Bug 1 (TRIGGER_STOP):** The first `schedule()` under spinlock occurs at stream start, not stream stop. F3+F4 elevated to critical alongside F1+F2.
- **AC101 `trigger(START)` is the first sleeping call:** The `ac101_trigger` call inside `ac108_set_clock` fires the first I2C write under spinlock, confirmed by call trace offset +0x23c

## What to capture next

**F1-F4-test execution:** Deploy the fixed module. Expected dmesg pattern:

```
PREPARE stream=Capture irqs_disabled=0 in_atomic=0       ← F4: clock enable in process ctx
ac108_set_clock ENTER y_start_n_stop=1 irqs_disabled=0    ← no BUG
ac108_set_clock EXIT y_start_n_stop=1 ret=0
TRIG_START stream=Capture cmd=1 irqs_disabled=1 in_atomic=1  ← empty, no I2C
  ...recording...
TRIG_STOP stream=Capture ... path=workqueue               ← F1: deferred, no I2C
work_cb_codec_clk ENTER try_stop=0                         ← runs on workqueue
ac108_set_clock ENTER y_start_n_stop=0 irqs_disabled=0     ← no BUG
ac108_set_clock EXIT y_start_n_stop=0 ret=0
work_cb_codec_clk EXIT r=0
seeed_voice_card_shutdown ENTER                             ← F2: cancel_work_sync first
ac108_aif_shutdown ENTER / EXIT
seeed_voice_card_shutdown EXIT
```

**Success criteria:** Zero `BUG: scheduling while atomic`, no kernel Oops, no panic. Multiple wake-capture-STT cycles without reboot.

## Parent context

See [`../AGENTS.md`](../AGENTS.md) for the full effort context, work item tracker, and fix plan.
