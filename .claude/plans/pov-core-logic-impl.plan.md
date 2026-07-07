# Plan: POV Wand Core Logic Implementation

- **Source**: User-provided explicit requirements (A–I) + Phase 1 verified findings (5-Phase 底层验证) + car2025_final reference decoder (LEDSHOW / LED_Loop1 / UserLEDShowProcess).
- **Complexity**: Medium-High. C bottom layer is frozen-solid (Phase 1–5 PASS); this plan ports the frame-table LEDSHOW decoder into `c/drivers/led_pov.c`, wires the C ISR↔foreground handshake (`g_LED_key_down` reset on EXTI3 rising edge), and stages a 3-layer Zig top (`Application / Control / Bridge`) without disturbing the validated C/HAL/ASM tree.

---

## Summary

Port the car2025_final `led_show.c` LEDSHOW decoder into our `c/drivers/led_pov.c`, keeping TIM7 @ 250 µs and the C ISR as the single owner of `g_LED_Show_RAM[24]` / `g_LED_CAT_RAM[6]` / `g_LED_MAP[2][6]`. The 240-step frame (40 cols × 6 cats) advances from inside the TIM7 ISR; the EXTI3 vibration handler only flips the state machine and zeroes `col`/`cat` — never runs LEDSHOW itself, so the "one-way refresh" (no double-direction ghosting) invariant is preserved. A staged 3-layer Zig top (`Application` / `Control` / `Bridge`) is added on top with raw `extern fn` (no `@cImport`), with the foreground FSM and a `zig build test` host-native test target. **Open question**: the user states 40 cols while `board.h` says 48 — flagged in Risks; **recommendation is 40 cols** (40 × 6 = 240 ticks, matching the car2025 source-of-truth `g_ShowData[3][48]`/40-col frame width distinction).

---

## Requirements

The 9 user-provided explicit requirements (A–I):

1. **(A) 3-layer Zig architecture**: `Application` (state machine / FSM / comms) → `Control` (pure functions: PID, font decode, pattern select, debounce) → `Bridge` (raw `extern fn`, type-mapping, global declarations, zero abstraction over C).
2. **(B) Front/back scheduling**: ISR only sets flags (`g_LED_key_down`); main loop does the work. Zig foreground never executes inside TIM7 or EXTI3 ISR.
3. **(C) One-way refresh on EXTI3 rising edge**: zero `col`/`cat` on rising edge to avoid drawing the same column twice on the back-swing. No double-direction ghosting. Foreground uses `led_pov_stop()` / `led_pov_start()` for 200 ms cooldown to suspend ISR-driven redraws during the back-swing phase.
4. **(D) `g_LED_Show_RAM` bit-domain (FROZEN FORMULA — truth source for both C decoder and Zig golden-output test)**:
   ```c
   b = (byte >> 6) & 0x03;   // [7:6] = Blue,  2 bits
   g = (byte >> 3) & 0x07;   // [5:3] = Green, 3 bits
   r =  byte       & 0x07;   // [2:0] = Red,   3 bits
   ```
   MSB-first `{B[1:0], G[2:0], R[2:0]}` — derived from `POV_COLOR_BLUE=0x80`, `POV_COLOR_GREEN=0x08`, `POV_COLOR_RED=0x01`, `POV_COLOR_YELLOW=0x09` already in `board.h:88-92`.
5. **(E) `g_LED_CAT_RAM[6] = {0xFB,0xF7,0xEF,0xDF,0xBF,0x7F}`** — active-low CAT select bytes.
6. **(F) `g_LED_MAP[2][6] = {{0,10,7,4,1,2},{3,6,9,11,8,5}}`** — 2×6 column permutation for SPI byte packing.
7. **(G) No empty-loop blocking**: must use SysTick (1 ms tick) or TIM7 — no `while(i<N)i++;` busy-waits anywhere in the new code.
8. **(H) 40 cols × 6 cats = 240 ticks/frame**: **DISCREPANCY** — current `c/drivers/board.h` declares 48 cols; user explicitly says 40. Recommendation: resolve to **40** (matches car2025 line 198 `if ( col < 40 )` and gives exactly 240 ticks × 250 µs = 60 ms/frame).
9. **(I) Reuse car2025_final, do not reinvent**: port `LEDSHOW`, `LED_Loop1`, `UserLEDShowProcess`, `g_LED_Show_RAM`, `g_LED_CAT_RAM`, `g_LED_MAP`, `g_ShowData` shape (3×48) — do not re-design.
10. **(J) Async fence protocol (NEW)**:
    - **Foreground → Background** (`g_LED_key_down = 1`): Zig FSM writes this volatile uint8_t when `vibration_consume_clear() == 1`. TIM7 ISR's `led_pov_tick()` checks at the very top: if set, reset `col=0; cat=0; g_LED_key_down=0`. This is the **single-frame-per-stroke** enforcement primitive.
    - **Background → Foreground**: TIM7 ISR runs continuously at 4 kHz; foreground does NOT poke per-tick state — only sets `pattern_idx` on shake-count threshold.
    - **Foreground control** (`led_pov_stop()` / `led_pov_start()`): Zig FSM enters 200 ms lockout window after a stroke, calls `led_pov_stop()` to suspend ISR (TIM7 peripheral keeps counting but no ISR fires → no SPI push). After cooldown, calls `led_pov_start()` to re-enable for next stroke.
11. **(K) Hardcoded address discipline (NEW)**: 11 SRAM addresses in `c/tests/README.md` §4.4 are linker-derived and WILL drift by +0~40 bytes once `g_LED_key_down` (1 byte) and `g_LED_Show_RAM[24]` (24 bytes) are added. Mitigation: (a) symbol-based gdb reads (`print g_isr_count_tim7`) preferred over address-based probe-rs reads; (b) after Task 5, re-measure with `nm zig-out/bin/wobbly-stick-light.elf | grep -E "(g_systick_ms|g_isr_count|g_spi_test|s_state|s_cat|s_pending|g_LED)"` and patch README §4.4; (c) peripheral MMIO addresses (0x4001xxxx, 0x4002xxxx, 0x08000000, 0x20000000) are ARM-spec fixed, no audit needed.

---

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| LEDSHOW byte-decode (RAM → SPI) | `car2025_final/Core/Src/led_show.c:60-108` | `LEDSHOW(uint8_t mode, uint8_t cat_addr)` — split each `g_LED_Show_RAM[ram_addr+i]` into 3 × 3-bit fields, then pack into `buf[0..2]` using `g_LED_MAP[i][j]` permutation. |
| 24-byte RAM layout | `car2025_final/Core/Src/led_show.c:6,41-48` | `#define LED_SIZE 24`; `ram_addr = cat_addr * 4`; per-CAT 4 bytes × 6 CATs = 24. |
| Cat-select bytes | `car2025_final/Core/Src/led_show.c:50-53` | `g_LED_CAT_RAM[6] = {0xFB,0xF7,0xEF,0xDF,0xBF,0x7F}` (active-low). |
| 2×6 column permutation | `car2025_final/Core/Src/led_show.c:55-58` | `g_LED_MAP[2][6] = {{0,10,7,4,1,2},{3,6,9,11,8,5}}`. |
| Frame-table population | `car2025_final/Core/Src/led_show.c:133-157` | `LED_Loop1(uint8_t index)` — per-column, expand 3 font rows (blue/green/red planes) into 24 bytes; CATs 0–1 = red, 2–3 = blue, 4–5 = green+blue. |
| State machine | `car2025_final/Core/Src/led_show.c:183-214` | `UserLEDShowProcess` — consumes `LEDSHOW_START` once per tick; `g_LED_key_down == 1` resets `col = cat = 0`. |
| ISR/foreground split | `car2025_final/Core/Src/led_show.c:188-193` | Flag set in ISR, polled & cleared in `UserTasks()` main loop. |
| EXTI3 handler shape | `car2025_final/Core/Src/stm32f1xx_it.c:243-252` + `HAL_GPIO_EXTI_Callback` | `EXTI3_IRQHandler` → `HAL_GPIO_EXTI_IRQHandler(GPIO_PIN_3)` → user-callback sets `g_LED_key_down = 1`. |
| TIM7 cadence | `car2025_final/Core/Src/led_show.c:185-186` (uses TIM7 @ ~5 kHz) | Our `c/drivers/led_pov.c:75-82` already configures TIM7 @ 250 µs (4 kHz); reuse, do not re-init. |
| Vibration debounce | `c/drivers/vibration.c` (Phase 2) | EXTI3 + 5 ms debounce window; `vibration_consume()` returns 1 on fresh trigger, 0 otherwise. |
| SPI1 3-byte emission | `c/drivers/led_pov.c:29-44` | `spi1_send_3bytes(buf[3])` already implemented; pull `IR_LOCK` low → transmit → high (matches car2025 line 102-104). |
| State enum | `c/drivers/led_pov.h:34-38` | `LED_POV_STOP/IDLE/START` already mirrors `LEDSHOW_STOP/IDLE/START`; do not rename. |
| Zig bridge convention | `src/c_bridge.zig` (new) | raw `extern fn ... callconv(.c)`; mirror `LedPovState` as `enum(c_int)` with `STOP=0, IDLE=1, START=2`. |
| Zig 3-layer split | `src/app.zig` + `src/control/*.zig` + `src/c_bridge.zig` | App = FSM + 5 ms poll loop; Control = pure functions + comptime font; Bridge = extern fn only. |

---

## Files to Change

| File | Action | Why |
|---|---|---|
| `c/drivers/led_pov.c` | **Edit (port LEDSHOW decoder)** | Replace placeholder `led_pov_tick()` (lines 121-135) with ported `LEDSHOW()` + `LED_Loop1()` + `UserLEDShowProcess()`. Add `g_LED_Show_RAM[24]`, `g_LED_CAT_RAM[6]`, `g_LED_MAP[2][6]`, `s_col`, `s_cat`, `s_state` static state. |
| `c/drivers/led_pov.h` | **Edit (extend API)** | Expose `g_LED_Show_RAM`/`g_LED_CAT_RAM`/`g_LED_MAP` as `static const` (kept file-local — do not export); ensure `POV_COL_NUM` aligns with **40**, not 48. |
| `c/drivers/board.h` | **Edit (resolve 40 vs 48)** | Change `POV_COL_NUM` from 48 to **40** to match user requirement (H) and car2025 line 198. **Flag this in PR description.** |
| `c/drivers/font_pov.c` | **Edit (replace placeholders)** | Replace `FONT_LKM`/`FONT_RAINBOW`/`FONT_ALL_RED` placeholders with real 3×40 bitmaps (or 3×48 with cols 40..47 zero-padded for forward-compat). Generate L/K/M glyphs as 16×8 bitmaps → pack into 3 color planes. |
| `c/drivers/font_pov.h` | **Keep (shape OK)** | `POV_ROW_NUM × POV_COL_NUM` array shape already in place; only the `POV_COL_NUM = 40` change from `board.h` propagates. |
| `c/drivers/vibration.c` | **Edit (add `vibration_consume_clear()`)** | Currently `vibration_consume()` also calls `led_pov_on_vibration()` as a side effect. Split: `vibration_consume()` returns 1/0 only; new `vibration_consume_clear()` allows the Zig side to also fire `led_pov_on_vibration()` at the moment policy decides (decouples policy from ISR). |
| `c/drivers/vibration.h` | **Edit (declare new symbol)** | Add `uint8_t vibration_consume_clear(void)` declaration. |
| `c/it.c` | **Verify (no change)** | Confirm `EXTI3_IRQHandler` and `TIM7_IRQHandler` are already wired and that EXTI3 sets `g_LED_key_down` (not `led_pov_on_vibration()`). Per Phase 1 PASS this should already be correct. |
| `src/c_bridge.zig` | **New** | Raw `extern fn` declarations for `board_init`, `led_pov_init/start/stop/set_pattern/on_vibration/tick/get_state/get_pattern`, `vibration_init/consume/consume_clear/last_tick_ms`; `LedPovState` enum mirror; `g_systick_ms` extern. |
| `src/app.zig` | **New** | FSM (`idle → armed → display → cooldown`), 5 ms poll loop using `g_systick_ms`, calls into `control.pov.tick()`. |
| `src/control/mod.zig` | **New** | Re-exports `pov`, `debounce`, `font`; `zig build test` target. |
| `src/control/pov.zig` | **New** | Pure FSM step function `onShake(now_ms, *PovState)`; pattern rotation; shake-count debouncing. |
| `src/control/debounce.zig` | **New** | Time-window helpers (5 ms / 200 ms / 1 s / 5 s). |
| `src/control/font.zig` | **New** | Comptime-encoded 16×8 L/K/M bitmaps (or call into C's `FONT_LKM` via `extern const`); `encodeAsciiTriple` helper for golden-output unit tests. |
| `src/main.zig` | **Edit (delete PB0 loop)** | Replace 53-line PB0 heartbeat halt with `export fn main() callconv(.c) noreturn` that calls `app.run()`. |
| `src/root.zig` | **Delete** | Dead 965-byte `build(b: *std.Build)` leftover from bootstrap skeleton. No callers. |
| `build.zig` | **Edit (add test target)** | Add `addTest` for `src/control/mod.zig` (host-native triple); keep existing 5 C files. No new `addCSourceFile` lines. |
| `.claude/plans/pov-core-logic-impl.plan.md` | **New (this file)** | Plan of record. |

---

## Tasks

### Task 1 — Resolve 40 vs 48 col discrepancy (Requirement H)
- **Action**: Edit `c/drivers/board.h`: change `POV_COL_NUM` from 48 to **40**. Update the static `g_ShowData` / `FONT_*` array dimensions in `c/drivers/font_pov.c` and `c/drivers/font_pov.h` accordingly. Re-run `zig build` to confirm no dimension mismatch.
- **Mirror**: car2025 line 198 `if ( col < 40 )` — 40 is the source-of-truth frame width.
- **Validate**: `zig build` produces `.elf` with no warnings about array sizes; `llvm-objdump -d zig-out/bin/wobbly-stick-light.elf | head -50` shows no surprise constants in the LED decoder. Document the change in the PR description.

### Task 2 — Port `g_LED_CAT_RAM` / `g_LED_MAP` constants
- **Action**: Add `static const uint8_t g_LED_CAT_RAM[6] = {0xFB,0xF7,0xEF,0xDF,0xBF,0x7F};` and `static const uint8_t g_LED_MAP[2][6] = {{0,10,7,4,1,2},{3,6,9,11,8,5}};` to `c/drivers/led_pov.c` (file-local, not exposed to Zig).
- **Mirror**: `car2025_final/Core/Src/led_show.c:50-58` exact text.
- **Validate**: Compile passes; `nm zig-out/bin/wobbly-stick-light.elf | grep LED_CAT` shows the symbols exist (with `static` linkage, address-stable).

### Task 3 — Port `LEDSHOW(mode, cat_addr)` byte decoder
- **Action**: Add `static void LEDSHOW(uint8_t mode, uint8_t cat_addr)` to `c/drivers/led_pov.c`. Replicate the `ram_data[12]` unpack loop (lines 72-80), the 2-row permutation loop (lines 83-94), and the 3-byte SPI emission (lines 102-104) using our existing `spi1_send_3bytes()` helper. The `IR_LOCK` GPIO toggle maps to our PA6 software CS (per `c/drivers/led_pov.c:47-73` SPI1 init).
- **Mirror**: `car2025_final/Core/Src/led_show.c:60-108` line-for-line.
- **Validate**: `zig build` produces no warnings; `llvm-objdump -d` shows the function is reachable from `led_pov_tick`; SPI1 pin toggle observable on scope if probe-rs hardware available.

### Task 4 — Port `LED_Loop1(index)` frame-table loader
- **Action**: Add `static void LED_Loop1(uint8_t index)` to `c/drivers/led_pov.c`. Read 3 bytes from `s_font[0][index]`, `s_font[1][index]`, `s_font[2][index]` and expand into `g_LED_Show_RAM[0..23]`. **Important deviation from car2025**: our `POV_ROW_COLOR` mapping is L=blue / K=green / M=red (per `c/drivers/led_pov.h:82`), but car2025 hard-codes 0x80/0x01/0x09 with no indirection. **Adapt the byte values to match our row-color convention** — do not blindly copy car2025's color constants.
- **Mirror**: `car2025_final/Core/Src/led_show.c:133-157` structure, not the constants.
- **Validate**: Static analyzer (or unit test) confirms each bit of `s_font[plane][col]` is mapped to the correct 8-bit packed byte in `g_LED_Show_RAM` per `POV_ROW_COLOR`.

### Task 4a — LEDSHOW byte decode (frozen formula)
- **Action**: In `c/drivers/led_pov.c::LEDSHOW(mode, cat_addr)`, decode each `g_LED_Show_RAM[cat_addr*4 + byte_idx]` byte using the **frozen bit-domain formula** (Requirement D):
  ```c
  uint8_t byte = g_LED_Show_RAM[cat_addr * 4 + i];
  uint8_t b = (byte >> 6) & 0x03;   // [7:6] = Blue
  uint8_t g = (byte >> 3) & 0x07;   // [5:3] = Green
  uint8_t r =  byte       & 0x07;   // [2:0] = Red
  ```
  Then pack into `buf[0..2]` (which will be emitted as 3 SPI bytes via `spi1_send_3bytes()`). Use `g_LED_MAP[row][col]` for byte permutation.
- **Mirror**: `car2025_final/Core/Src/led_show.c:60-108` (the structural loop), but **use our frozen formula**, not car2025's possibly-different bit order.
- **Validate**: Run `zig build test` → `test "LEDSHOW byte decode col=0 cat=0"` passes (golden-output matches `0x80` for blue-only column, `0x08` for green-only, `0x01` for red-only, `0x09` for yellow).

### Task 5 — Port `UserLEDShowProcess` state machine
- **Action**: Add `void led_pov_tick(void)` (or rename to `UserLEDShowProcess` for symmetry) to `c/drivers/led_pov.c`. Replicate the `s_col` / `s_cat` static counters (lines 185-186), the `g_LED_key_down` reset branch (lines 188-193), and the per-tick `cat` advance + `LED_Loop1` on wrap (lines 195-208). The placeholder `led_pov_tick()` (lines 121-135) is replaced.
- **Mirror**: `car2025_final/Core/Src/led_show.c:183-214`.
- **Validate**: With TIM7 firing at 4 kHz, `s_col` wraps 0→39 in 60 ms, `s_cat` wraps 0→5 in 1.5 ms; 240 ticks/frame; `g_LED_key_down` reset zeroes both counters. Test by injecting `g_LED_key_down = 1` mid-frame and observing the next column is 0.

### Task 6 — One-way refresh (Requirement C)
- **Action**: In `c/drivers/led_pov.c` (or `c/it.c`'s `HAL_GPIO_EXTI_Callback` for GPIO_PIN_3): on EXTI3 **rising edge** only, set `g_LED_key_down = 1`. On falling edge, do **nothing**. Per `c/drivers/vibration.c` (Phase 2) the debounced `vibration_consume()` already filters out the back-swing; do not weaken that filter.
- **Mirror**: car2025 `HAL_GPIO_EXTI_Callback` (in `main.c`, not in the files we read) — set `g_LED_key_down = 1` on rising.
- **Validate**: Wave the wand and confirm: only one frame re-draws per stroke; no double image; no flicker on the reversal direction.

### Task 7 — Split `vibration_consume()` / `vibration_consume_clear()`
- **Action**: Edit `c/drivers/vibration.c`: remove the internal `led_pov_on_vibration()` call from `vibration_consume()`. Add a new function `uint8_t vibration_consume_clear(void)` that returns the same 1/0 value but also clears the pending flag without firing `led_pov_on_vibration()`. The Zig FSM (Task 12) decides when to fire the LED reset based on its own policy.
- **Mirror**: car2025's separation of flag-set (in ISR) vs flag-consume (in foreground) — same pattern, extended with a "consume without side effect" variant.
- **Validate**: `vibration_consume()` no longer touches LED state; `g_LED_Show_state` remains `IDLE` after a shake unless `vibration_consume_clear()` is followed by `led_pov_on_vibration()`.

### Task 8 — Generate real font bitmaps
- **Action**: Edit `c/drivers/font_pov.c`: replace the placeholder `FONT_LKM` (uniform color blocks) with a real 3×40 (or 3×48 with cols 40..47 zero-padded) bitmap encoding the letters L, K, M as 16-column glyphs. Each column is 1 byte = 8 vertical pixels. Use the convention `POV_COLOR_BLUE=0x80, GREEN=0x08, RED=0x01` from `c/drivers/led_pov.h:88-92`.
- **Mirror**: car2025's `g_ShowData[3][48]` — same 3-plane structure, our row-to-color mapping differs.
- **Validate**: `zig build` passes; `llvm-objdump` does not show any `0xFF` or stray `0x80`/`0x08`/`0x01` in the data section beyond the 3×40 expected bytes; visual check by waving the wand and seeing L/K/M glyphs (requires hardware).

### Task 9 — `src/c_bridge.zig` raw extern declarations
- **Action**: Create `src/c_bridge.zig` with raw `extern fn ... callconv(.c)` for every C symbol listed in the bridge table (see §"Files to Change" above). Add `LedPovState` enum mirror: `pub const LedPovState = enum(c_int) { stop = 0, idle = 1, start = 2, _ };`. Expose `pub extern var g_systick_ms: volatile u32;`.
- **Mirror**: car2025's raw symbol exposure; Zig 0.16 `extern fn` convention.
- **Validate**: `zig build` resolves all extern symbols; no `@cImport` used; no missing-symbol linker errors.

### Task 10 — `src/control/*.zig` pure-function modules
- **Action**: Create `src/control/mod.zig` (re-exports), `src/control/pov.zig` (FSM step), `src/control/debounce.zig` (time windows), `src/control/font.zig` (comptime `encodeAsciiTriple` + golden-output tests for the LEDSHOW decoder). All pure functions; no allocator; no I/O. The Zig decoder MUST use the **same frozen bit-domain formula** as the C side:
  ```zig
  const b = (byte >> 6) & 0x03;
  const g = (byte >> 3) & 0x07;
  const r =  byte       & 0x07;
  ```
  This guarantees Zig-side golden-output matches C-side hardware output.
- **Mirror**: car2025's pure `LED_Loop1(index)` (no side effects beyond RAM write) — same separation of pure compute from I/O.
- **Validate**: `zig build test` runs the host-native test target; `test "encodeAsciiTriple L glyph byte-exact"` passes against a hand-computed expected `g_LED_Show_RAM` snapshot for col 0 of L (e.g. expect `{0x80,0x80,0x80,0x80}` for first 4 columns of all-blue L letter).

### Task 7.5 — Async fence protocol implementation (Requirement J)
- **Action**: 
  1. In `c/drivers/led_pov.c`, add `volatile uint8_t g_LED_key_down = 0;` (file-local static; do NOT export to header).
  2. In `led_pov_tick()`, at the very top (before `if (s_state != LED_POV_START) return;`):
     ```c
     if (g_LED_key_down) {
         s_col = 0; s_cat = 0;
         g_LED_key_down = 0;
     }
     ```
  3. In `src/c_bridge.zig`, declare `extern var g_LED_key_down: volatile u8;` (raw, no wrapper).
  4. In `src/app.zig`, when `vibration_consume_clear() == 1`, set `g_LED_key_down = 1` then `led_pov_start()`.
  5. After each stroke, enter 200 ms cooldown: `led_pov_stop()`; `while ((now_ms() - stroke_start) < 200)` ... `sleepUntilMs(now+5)`. After cooldown, `led_pov_start()` and wait for next EXTI3.
- **Mirror**: car2025's pattern of `g_LED_key_down` as a cross-foreground/background flag (set in `HAL_GPIO_EXTI_Callback`, read in `UserLEDShowProcess`).
- **Validate**: `nm zig-out/bin/wobbly-stick-light.elf | grep LED_key_down` shows the symbol with stable address; manual shake test on hardware shows exactly 1 frame per forward stroke, no redraw during back-swing.

### Task 0.5 — Hardcoded address audit (Requirement K)
- **Action**: Before any code changes, run:
  ```sh
  arm-none-eabi-nm --size-sort zig-out/bin/wobbly-stick-light.elf | grep -E "(g_systick_ms|g_isr_count|g_spi_test|s_state|s_cat|s_pending|g_LED|phase)"
  ```
  Snapshot current addresses. After Task 5 (adding `g_LED_key_down` + `g_LED_Show_RAM`), re-run and compare. Patch `c/tests/README.md` §4.4 SRAM address table. **All Phase 1-5 verification commands that use hardcoded probe-rs read addresses must be re-validated.**
- **Mirror**: Hardcoded-address discipline — peripheral MMIO addresses (0x4001xxxx, 0x4002xxxx, 0x08000000, 0x20000000) are ARM-spec fixed and safe; SRAM globals are linker-derived and must be re-measured.
- **Validate**: `nm` output matches the updated README §4.4 table; symbol-based gdb commands (`print g_isr_count_tim7`) work without modification; address-based probe-rs reads in `c/tests/README.md` §3 use the fresh addresses.

### Task 11 — `src/app.zig` foreground FSM
- **Action**: Create `src/app.zig` exporting `pub fn run() noreturn`. Body: `board_init` → `led_pov_init` → `vibration_init` → `control.pov.initialise()` → `while(true) { const now_ms = c_bridge.g_systick_ms; control.pov.tick(now_ms); sleepUntilMs(now_ms + 5); }`. Use 5 ms polling cadence (matches `VIBE_DEBOUNCE_MS=5` from `c/drivers/vibration.c`).
- **Mirror**: car2025's `UserTasks` loop (`common.c:146-155`) — sequential polling, no HAL_Delay, no `delay_ms`.
- **Validate**: `zig build` produces a `.elf` with the FSM present; `probe-rs run` shows the loop running (PC counter does not collapse to a single address); `g_systick_ms` advances monotonically per SysTick ISR.

### Task 12 — `src/main.zig` cleanup
- **Action**: Edit `src/main.zig`: delete the 53-line PB0 heartbeat halt; replace with `export fn main() callconv(.c) noreturn { app.run(); }`. Delete `src/root.zig` (no callers).
- **Mirror**: car2025's `main.c` — single `System_Init` + `while(1) UserTasks()` shape.
- **Validate**: `zig build` succeeds; `.elf` size does not regress; no orphan imports.

### Task 13 — `build.zig` test target
- **Action**: Edit `build.zig`: add `addTest` step for `src/control/mod.zig` with `target = target_native` (host triple), `.optimize = .Debug`. Wire `b.default.dependOn(&run_test.step);` so `zig build test` runs the control-layer unit tests on the dev machine.
- **Mirror**: Zig 0.16 standard `addTest` pattern.
- **Validate**: `zig build test` exits 0; tests report "all N passed".

### Task 14 — Hardware-in-the-loop smoke test
- **Action**: With `zig build` clean, run `probe-rs run zig-out/bin/wobbly-stick-light.elf --chip STM32F103RC` on a real board. Wave the wand at ~2 Hz; observe one complete L/K/M frame per stroke (no double image). Use a scope or logic analyzer on PA5/PA6/PA7 to confirm 3-byte SPI transactions fire at exactly 4 kHz.
- **Mirror**: 5-Phase 底层验证 (memory note) — same `probe-rs run` invocation, same chip.
- **Validate**: Visual confirmation of glyphs; SPI waveform matches 240 ticks × 250 µs = 60 ms/frame; no extraneous toggles.

---

## Validation

```sh
# 1. Clean build
zig build

# 2. Host-native unit tests (no cortex toolchain needed)
zig build test

# 3. Inspect decoder is reachable in the binary
llvm-objdump -d zig-out/bin/wobbly-stick-light.elf | grep -E "(LEDSHOW|LED_Loop1|UserLEDShowProcess|led_pov_tick)" | head -20

# 4. Confirm RAM arrays landed in .rodata (static const expected)
nm zig-out/bin/wobbly-stick-light.elf | grep -E "(LED_CAT_RAM|LED_MAP|LED_Show_RAM|FONT_LKM)"

# 5. Disassemble first 50 instructions to sanity-check reset vector + SysTick + TIM7 init
llvm-objdump -d zig-out/bin/wobbly-stick-light.elf | head -50

# 6. Flash and run on real hardware
probe-rs run zig-out/bin/wobbly-stick-light.elf --chip STM32F103RC

# 7. (Optional) Capture SPI traffic on PA5/PA6/PA7 with logic analyzer;
#    expect 3-byte bursts at ~4 kHz, each 250 µs apart, with 240 bursts per 60 ms frame.
```

**Pass criteria** (all of these must hold):
- `zig build` exit 0, no warnings on the LED decoder.
- `zig build test` exit 0, all N tests pass.
- `nm` shows the 4 expected symbols (3 static + FONT_LKM) in `.rodata`.
- `probe-rs run` boots; `g_systick_ms` advances; TIM7 fires at 4 kHz; SPI emits 3 bytes per tick.
- Waving the wand shows one frame per stroke (Requirement C).

---

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **40 vs 48 col discrepancy** (`board.h` says 48, user says 40) — silent miscompile if not caught. | **High** | Task 1 is the explicit resolution step: change `POV_COL_NUM` to 40 in `board.h` and propagate. PR description must call this out. Recommend 40 (matches car2025 source-of-truth). |
| TIM7 ISR overruns the 250 µs budget if `LEDSHOW` SPI transaction is slow. | Medium | SPI1 @ 9 MHz (PCLK2/8 default) gives ~333 ns/byte × 3 bytes = 1 µs per tick; well under 250 µs. Validate with scope; if overrun, raise `POV_TICK_US` to 500 µs (gives 120 ms/frame, still smooth). |
| `vibration_consume()` side-effect on `led_pov_on_vibration()` creates a race with the Zig FSM. | Medium | Task 7 splits the C side-effect into `vibration_consume_clear()`; the Zig FSM owns the policy. Add a unit test that calls `vibration_consume()` and asserts `g_LED_Show_state == IDLE` (no side effect). |
| Font bitmaps generated by hand contain row-flip or off-by-one errors. | Medium | Task 10 includes a comptime test: encode L glyph → compare against the golden 24-byte `g_LED_Show_RAM` snapshot for col 0. Visual confirmation on hardware (Task 14). |
| `g_LED_Show_RAM` / `g_LED_CAT_RAM` / `g_LED_MAP` accidentally exposed to Zig via header. | Low | Mark them `static const` in `c/drivers/led_pov.c`; do **not** add to `c/drivers/led_pov.h`. If they appear in `nm` with external linkage, the file-local `static` was lost. |
| `@cImport` temptation (Zig 0.16 convention is raw extern; deviating risks build-time slowdowns and silent errors). | Low | Bridge layer in Task 9 explicitly uses raw `extern fn`; no `@cImport` anywhere. Add a comment in `c_bridge.zig` citing the project rule. |
| One-way refresh (Requirement C) breaks if EXTI3 is configured for both edges. | Medium | Task 6 explicitly configures EXTI3 for **rising edge only**; verify with `HAL_GPIO_ReadPin` after a real shake event. If double-fires observed, add a 200 ms lockout in the foreground FSM. |
| `POV_ROW_COLOR` mapping (L=blue / K=green / M=red) differs from car2025's hardcoded 0x80/0x01/0x09. | Medium | Task 4 is explicit: "adapt byte values, do not copy car2025 constants". Add a `POV_ROW_COLOR[]` lookup table in `LED_Loop1`; preserve indirection. |
| Phase 1-5 PASS evidence becomes invalidated if `c/it.c` is touched. | Low | Task row says "Verify (no change)" for `c/it.c`. If a change is required, gate on re-running all 5 Phase tests. |
| `src/root.zig` deletion breaks any external import. | Low | Grep for `@import("root.zig")` before deletion; expected result: zero hits. |
| **NEW: Bit-domain formula mismatch** — Zig golden-output test uses one formula, C hardware uses another. | High | Task 4a + Task 10 explicitly cite the **frozen formula** `b = (byte >> 6) & 0x03; g = (byte >> 3) & 0x07; r = byte & 0x07`. Both sides cite the same constant. Code review gate. |
| **NEW: SRAM address drift** after adding `g_LED_key_down` (1 byte) + `g_LED_Show_RAM[24]` (24 bytes) — 11 SRAM addresses in `c/tests/README.md` §4.4 will shift by +0~40 bytes. | High | Task 0.5: re-measure with `nm` after Task 5; patch README; prefer symbol-based gdb reads over address-based probe-rs reads. |
| **NEW: Fence race** — Zig FSM writes `g_LED_key_down = 1` while TIM7 ISR is mid-execution of `led_pov_tick()`. Volatile access is atomic on Cortex-M3 for uint8_t, but ordering is not guaranteed without a memory barrier. | Low | Use `__DSB()` after writing `g_LED_key_down` in Zig (or declare volatile + accept eventual consistency, since the next TIM7 tick is at most 250 µs away — fence propagation is naturally delayed by IRQ latency). |
| **NEW: 200 ms cooldown too aggressive / too lenient** — if user shakes too fast (< 200 ms apart), strokes get dropped; if too slow (> 200 ms), back-swing ghost may appear during cooldown. | Medium | Make cooldown configurable: `pub const STROKE_COOLDOWN_MS: u32 = 200;` in `src/control/pov.zig`. Tune empirically with `probe-rs read` of `g_isr_count_tim7` during shake tests. |

---

## Acceptance

- [ ] `c/drivers/board.h` `POV_COL_NUM` is **40** (not 48); PR description notes the change.
- [ ] `c/drivers/led_pov.c` contains `LEDSHOW`, `LED_Loop1`, `UserLEDShowProcess` (or `led_pov_tick` with the same body) — line-for-line port of car2025 lines 60-214.
- [ ] `g_LED_Show_RAM[24]`, `g_LED_CAT_RAM[6]={0xFB,0xF7,0xEF,0xDF,0xBF,0x7F}`, `g_LED_MAP[2][6]={{0,10,7,4,1,2},{3,6,9,11,8,5}}` all present in `c/drivers/led_pov.c` as `static const`.
- [ ] **`g_LED_key_down` volatile uint8_t present** in `c/drivers/led_pov.c`; `led_pov_tick()` checks it at the top; clears on consume. **(Requirement J, Task 7.5)**
- [ ] **`led_pov_tick()` decodes byte via frozen formula**: `b = (byte >> 6) & 0x03; g = (byte >> 3) & 0x07; r = byte & 0x07`. **(Requirement D, Task 4a)**
- [ ] `c/drivers/vibration.c` exposes `vibration_consume()` (returns 1/0, no LED side effect) **and** `vibration_consume_clear()` (returns 1/0, clears pending).
- [ ] EXTI3 configured for **rising edge only**; `g_LED_key_down = 1` set on rising; nothing on falling.
- [ ] `c/drivers/font_pov.c` `FONT_LKM` contains real L/K/M glyphs (not the uniform-color placeholders).
- [ ] `src/c_bridge.zig`, `src/app.zig`, `src/control/{mod,pov,debounce,font}.zig` all created.
- [ ] **`src/c_bridge.zig` declares `extern var g_LED_key_down: volatile u8;`**.
- [ ] **`src/app.zig` FSM uses `led_pov_stop()` / `led_pov_start()` for 200 ms cooldown** and writes `g_LED_key_down = 1` on `vibration_consume_clear() == 1`. **(Requirement J)**
- [ ] `src/main.zig` is a thin shim into `app.run()`; `src/root.zig` deleted.
- [ ] `build.zig` has a host-native test target; `zig build test` passes.
- [ ] **`zig build test` includes `test "LEDSHOW byte decode col=0 cat=0"`** that verifies the frozen bit-domain formula. **(Task 4a + Task 10)**
- [ ] **`zig build test` includes `test "encodeAsciiTriple L glyph byte-exact"`** with hand-computed golden output. **(Task 10)**
- [ ] `zig build` clean; no warnings on the LED decoder.
- [ ] `nm zig-out/bin/wobbly-stick-light.elf` shows the 4 expected symbols in `.rodata` (g_LED_CAT_RAM, g_LED_MAP, g_LED_Show_RAM, FONT_LKM) **plus** `g_LED_key_down` in `.bss`.
- [ ] **`c/tests/README.md` §4.4 SRAM address table re-measured** via `nm` after Task 5; phase C/D validation commands still work with updated addresses. **(Requirement K, Task 0.5)**
- [ ] `probe-rs run zig-out/bin/wobbly-stick-light.elf --chip STM32F103RC` boots, SysTick advances, TIM7 fires at 4 kHz, SPI emits 3-byte bursts.
- [ ] Visual: waving the wand shows one L/K/M frame per stroke; no double image on the back-swing (Requirement C).
- [ ] Scope: 3-byte SPI transactions at 4 kHz, 240 transactions per 60 ms frame, 60 ms/frame matches the 240 × 250 µs budget.
- [ ] No empty-loop blocking (`while(i<N)i++;`) introduced anywhere; all timing via SysTick (`g_systick_ms`) or TIM7 (Requirement G).
- [ ] No Zig code in TIM7 or EXTI3 ISR (Requirement B); `nm` confirms `_ZN*` (Zig mangled) symbols appear only in `.text.main` and `.text.app.*`, not in `.text.TIM7_IRQHandler` or `.text.EXTI3_IRQHandler`.
- [ ] No `@cImport` anywhere in `src/` (project rule: raw extern fn only).
- [ ] All 5 Phase 底层验证 tests still pass (re-run after changes; gate on green).
