//! Foreground application loop —— translates pure FSM decisions in
//! `control/pov.zig` into C driver calls via `c_bridge.zig`.
//!
//! == Boot (once) ==
//!   1. board_init()          : clock + SysTick 1ms tick (board_init.c)
//!   2. led_pov_init()        : SPI1 + TIM7 + frame buffer (led_pov.c)
//!   3. vibration_init()      : PC3 EXTI3 + 5ms soft-debounce window
//!   4. led_pov_set_pattern() : inject the FONT_LKM byte table
//!
//! == Per-tick (every 5 ms) ==
//!   1. Consume vibration (5 ms debounce already happened inside .c).
//!   2. Step pure FSM in control/pov.zig (no I/O).
//!   3. Translate FSM `action` → driver calls (start/stop/cooldown).
//!   4. Sleep until next 5 ms tick using `g_systick_ms`.
//!
//! == Boundary contracts honored ==
//!   A (delay): no busy-counter loops; cooldown + tick both use SysTick.
//!   D (ISR isolation): all Zig code lives here in foreground; TIM7/EXTI3
//!     ISRs only call C helpers (led_pov_tick / vibration_exti_isr) and
//!     never reach Zig.

const c_bridge = @import("c_bridge.zig");
const control = @import("control/mod.zig");

/// DEBUG ONLY (Diagnostic 4): set true to bypass FSM/ISR entirely and force
/// LEDSHOW(0,0) with RAM=0x80 every loop iteration.  Set false to restore
/// normal vibration-driven FSM behavior.
const DEBUG_FORCE_BLUE: bool = false;

/// DEBUG ONLY (Diagnostic 5): set true to skip FSM and just keep TIM7 ISR
/// running forever.  Verifies that the ISR-side LEDSHOW path works on its own.
const DEBUG_SKIP_FSM: bool = false;

/// Foreground loop entry —— exported with C ABI so the bare-metal startup
/// in `c/startup/startup_stm32f10x_hd.s` can `bl main → app.run`.
pub export fn run() callconv(.c) noreturn {
    c_bridge.board_init();
    c_bridge.led_pov_init();
    c_bridge.vibration_init();
    c_bridge.led_pov_set_pattern(@ptrCast(&c_bridge.FONT_LKM));

    if (DEBUG_FORCE_BLUE) {
        // === Diagnostic 4: bypass FSM/ISR. 直接推 LEDSHOW(0,0) + RAM=0x80 ===
        // 不依赖 TIM7 ISR、不依赖振动、不依赖 FSM。每 ~1ms 推一次。
        while (true) {
            c_bridge.led_pov_force_blue();
            const start = c_bridge.readSystickMs();
            while ((c_bridge.readSystickMs() -% start) < 1) {
                asm volatile ("nop");
            }
        }
    }

    if (DEBUG_SKIP_FSM) {
        // === Diagnostic 5: 跳过 FSM，开 ISR 后死循环。验证 ISR-side LEDSHOW ===
        c_bridge.led_pov_start();
        while (true) {
            asm volatile ("nop");
        }
    }

    var state: control.pov.PovState = .idle;
    var last_stroke_ms: u32 = 0;

    while (true) {
        const now = c_bridge.readSystickMs();

        // 1) Consume vibration. Result feeds the FSM; we do NOT branch on it
        //    outside FSM — that would create "FSM external routing" and break
        //    encapsulation. FSM owns all decisions about ISR start/stop/fence.
        const vibration_now = c_bridge.vibration_consume_clear();

        // 2) Pure FSM step (no I/O — fully covered by host tests).
        const step_result = control.pov.step(state, vibration_now, now, last_stroke_ms);
        state = step_result.next;
        last_stroke_ms = step_result.last_valid_stroke_ms;

        // 3) Translate FSM `action` → driver calls. FSM is the SOLE arbiter
        //    of side effects; we only route its decisions to the driver layer.
        switch (step_result.action) {
            .none => {},
            .request_start => {
                // FSM decided: idle → active.  Reset col/cat to frame origin
                // (fence) AND start ISR — both belong to this transition.
                c_bridge.writeLedKeyDown(1);
                c_bridge.led_pov_start();
            },
            .fully_stop => c_bridge.led_pov_stop(),
        }

        // 4) Sleep until next 5 ms tick ── SysTick polled, not a counter.
        sleepUntilMs(now + 5);
    }
}

/// Block until `g_systick_ms >= target_ms`. The volatile read of the
/// SysTick counter is the legal side-effect anchor (CLAUDE.md: -Os may
/// only delete reads whose result has no observable effect). `asm nop`
/// makes the loop body unambiguously an intentional spin.
fn sleepUntilMs(target_ms: u32) void {
    while (c_bridge.readSystickMs() < target_ms) {
        asm volatile ("nop");
    }
}
