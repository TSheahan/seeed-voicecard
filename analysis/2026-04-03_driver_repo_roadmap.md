# Driver Repo Roadmap — seeed-voicecard

*2026-04-03 — Roadmap document for Workstream 2: deep driver/ALSA/Python interface analysis*

---

## 1. Purpose and scope

This is the companion to `raspberry-ai/mvp-modules/forked_assistant/archive/2026-04-03_python_alsa_interface_brief.md`. The agent reads both before beginning Workstream 2. This document is a guide to the driver repo, not a curated analysis — the agent decides what to read and how deeply. The driver repo is structurally simple: no archive layers, no superseded iterations, no memory files with stale content. The relevant source fits in the root directory and one subfolder. The analysis question is: what in the `seeed-voicecard` / `ac108` kernel driver teardown path causes a Pi reboot when the ALSA PCM file descriptor closes on process exit?

---

## 2. Repo structure — file map

### Primary source files (analysis targets)

| File | Lines | Role |
|---|---|---|
| `ac108.c` | 1347 | AC108 ADC codec driver — **primary crash suspect**. Owns `ac108_trigger`, `ac108_aif_shutdown`, `ac108_set_clock`, `ac108_hw_params`. All I2C register interaction with the AC108 chip on the HAT. |
| `seeed-voicecard.c` | 783 | ASoC machine driver — card-level ops, `seeed_voice_card_trigger`, workqueue scheduling (`work_codec_clk`), `seeed_voice_card_shutdown`. The trigger dispatch layer between ASoC and the codec. |
| `ac10x.h` | 104 | Shared struct definitions and function declarations. Contains `ac10x_read`, `ac10x_update_bits`, `ac108_multi_update_bits`, `ac108_multi_write` — the regmap wrapper layer. The regmap configuration here (cache type, volatile registers) determines whether these functions can sleep, which is the spinlock question. |
| `ac108.h` | 619 | AC108 register map: addresses and bit field definitions. Reference for understanding what `ac108_aif_shutdown` and `ac108_set_clock` are writing to and why. |

### Not relevant to 4-mic HAT analysis

These files are for different codec hardware. Skip unless the machine driver (`seeed-voicecard.c`) cross-references them in a way that affects the 4-mic path.

| File | Lines | Note |
|---|---|---|
| `ac101.c` | 1459 | AC101 codec — not present on ReSpeaker 4-mic HAT. |
| `wm8960.c` | 1179 | WM8960 codec — different board variant entirely. |

### Userspace ALSA plugin — teardown path uncertainty

| File | Lines | Role |
|---|---|---|
| `ac108_plugin/pcm_ac108.c` | 466 | Userspace ALSA plugin for AC108 channel mapping/routing. Whether PortAudio's `Pa_OpenStream` routes through this plugin or directly to the kernel `hw:seeed4micvoicec` device determines whether this code is in the teardown path at all. The `asound_4mic.conf` `pcm.ac108` definition (a `type plug` over `hw:seeed4micvoicec`) suggests the plug layer is interposed — but the plugin library is separate from the plug type. Needs analysis. |
| `ac108_plugin/ac108_help.c` | 74 | Helper functions for the plugin. Only relevant if `pcm_ac108.c` is in the path. |

### Configuration files

- **`asound_4mic.conf`** — the `/etc/asound.conf` installed by the seeed-voicecard installer for the 4-mic HAT. Defines `pcm.ac108` as `type plug` over `hw:seeed4micvoicec`; capture default routes through this plug. Read to understand what ALSA PCM name PortAudio resolves when opening device index 1.
- **`ac108_asound.state`** — ALSA mixer state snapshot (register values at initialisation). Contains confirmed ADC digital volume 47.25 dB. Read if register initial state matters for understanding what state the codec is in when teardown fires.
- **`dkms.conf`** — DKMS build configuration. Module name: `seeed-voicecard`. Read if confirming that the running `.ko` on the Pi matches this source branch (`v6.12`) is necessary for the analysis.
- **`Makefile`** — kernel module build targets. Read only if build configuration (e.g., conditional compilation flags) affects which code paths are compiled in.

---

## 3. Pre-identified suspicious patterns

These four patterns were flagged in prior analysis as unconfirmed suspects. Line numbers are approximate for the `v6.12` / `ac108-shutdown-fix` branch — confirm exact locations when reading.

### Pattern 1 — Possible I2C inside spinlock (`ac108.c`, `ac108_trigger`)

In `ac108_trigger` handling `SNDRV_PCM_TRIGGER_START`, calls to `ac10x_read()` and `ac108_multi_update_bits()` appear inside a `spin_lock_irqsave` / `spin_unlock_irqrestore` block. If these functions perform real I2C bus transactions (which can sleep), calling them in atomic context is a kernel BUG that will panic. The resolution depends on the regmap configuration in `ac10x.h` or the regmap init in `ac108.c`: if the cache type is `REGCACHE_RBTREE` (or similar), reads may be served from cache without touching the bus.

**What to confirm:** regmap `cache_type` for the AC108 device registration; whether `ac10x_read` ultimately calls `regmap_read` (potentially cached) or a raw I2C transfer.

### Pattern 2 — Workqueue race on TRIGGER_STOP (`seeed-voicecard.c`, `seeed_voice_card_trigger`)

In `seeed_voice_card_trigger` handling `SNDRV_PCM_TRIGGER_STOP`, when called from interrupt context (`in_irq()` branch), the clock-stop work (`ac108_set_clock(0, ...)`) is deferred to a workqueue via `schedule_work(&work_codec_clk)`. This deferred item contains multiple I2C writes. If `snd_pcm_release()` subsequently calls `ac108_aif_shutdown` while `work_cb_codec_clk` is still pending or executing, both functions are writing to the AC108 codec concurrently over I2C.

**What to confirm:** the `in_irq()` branch logic; whether any `flush_work()` or `cancel_work_sync()` call exists to drain the workqueue before `shutdown` proceeds; what `ac108_aif_shutdown` assumes about codec clock state on entry.

### Pattern 3 — No error handling in shutdown (`ac108.c`, `ac108_aif_shutdown`)

`ac108_aif_shutdown` performs I2C writes to disable the module clock (`MOD_CLK_EN=0`) and assert reset (`MOD_RST_CTRL=0`). The return values of these writes are not checked. If the I2C bus is in a bad state (e.g., due to a prior atomic-context violation from Pattern 1, or a concurrent write from Pattern 2), the write silently fails and the codec is left in an undefined state. Whether this produces a kernel panic, a hang, or silent corruption depends on the I2C driver and bus error handling.

**What to confirm:** `ac108_aif_shutdown` return value handling; what the I2C subsystem does on a hung bus in the context of a driver shutdown callback.

### Pattern 4 — Author-acknowledged spinlock workaround (`seeed-voicecard.c`)

The comment `/* I know it will degrades performance, but I have no choice */` appears near the spinlock added to `seeed_voice_card_trigger`. The author explicitly acknowledges the spinlock as a concurrency band-aid rather than a correct fix. This is direct evidence that the concurrency model in the trigger path was known to be problematic at the time of writing.

**What to confirm:** exact context of the comment; what race condition the spinlock was intended to prevent; whether the "no choice" situation is the same race described in Pattern 2.

---

## 4. Build and installation context

The module is built and installed via DKMS (`dkms.conf`). On the Pi running `6.12.75+rpt-rpi-v8`, the installed `.ko` should correspond to the `v6.12` branch of the HinTak fork (now also `TSheahan/seeed-voicecard`, branch `ac108-shutdown-fix`). The working branch contains no functional changes from `upstream/v6.12` yet — only the `.gitignore` commit. So `ac108-shutdown-fix` HEAD is identical to `upstream/v6.12` for all source files.

If the Pi's DKMS module was built from the original installation rather than from this checkout, source and runtime may differ at the margin. This is unlikely to affect the analysis of the crash patterns, but worth noting if a specific line reference doesn't match observed behaviour.

---

## 5. Key questions for driver analysis

These are the same five questions stated in the Python-side brief, now framed for driver source reading:

1. **Call sequence to shutdown:** Trace from `snd_pcm_release()` through the ASoC / machine driver layer to `ac108_aif_shutdown`. Does `SNDRV_PCM_TRIGGER_STOP` always fire before `shutdown`, or can `shutdown` be called without a prior TRIGGER_STOP — specifically in the case where the stream was already stopped via PortAudio's paComplete path before FD close?

2. **paComplete and TRIGGER_STOP:** When PortAudio stops a stream internally via the paComplete return value, does it call `snd_pcm_drop()` or `snd_pcm_drain()` (or an equivalent) before the application closes the FD? If so, does `ac108_trigger(STOP)` and any workqueue work it schedules complete before `snd_pcm_release()` reaches `shutdown`?

3. **Regmap cache and sleeping-in-atomic:** What is the `cache_type` in the AC108 regmap registration in `ac108.c`? Does `ac10x_read()` (called inside `spin_lock_irqsave` in `ac108_trigger` TRIGGER_START) ultimately perform a real I2C transfer, or is it served from the regmap cache without sleeping?

4. **Workqueue synchronisation:** Is there any `flush_work()`, `cancel_work_sync()`, or equivalent call that ensures `work_cb_codec_clk` has completed before `ac108_aif_shutdown` executes? What state does `ac108_aif_shutdown` assume the AC108 clock is in on entry?

5. **I2C error handling in shutdown:** What happens when an I2C write inside `ac108_aif_shutdown` fails? Does the failure propagate up through the ASoC shutdown call chain, and if so, does any layer translate it into a kernel panic or BUG?
