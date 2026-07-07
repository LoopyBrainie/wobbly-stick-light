//! POV stroke FSM — pure state transitions, no I/O.
//!
//! Used by `src/app.zig` to decide what to ask of the C driver on each
//! main-loop iteration. Inputs:
//!   - `current`:               FSM state from the previous tick.
//!   - `vibration`:             nonzero when `vibration_consume_clear()` reports a raw edge.
//!   - `now_ms`:                current `g_systick_ms` snapshot.
//!   - `last_valid_stroke_ms`:  timestamp of the last valid stroke edge (post-blanking).
//!
//! Outputs:
//!   - `next`:                   FSM state for the next tick.
//!   - `last_valid_stroke_ms`:   updated timestamp on each valid-stroke event.
//!   - `action`:                 what the driver layer should do this tick.
//!
//! == Design ==
//!   Mechanical vibration sensors (SW-520D, Hall, etc.) inside a POV wand exhibit
//!   **contact chatter**: a single human-driven stroke generates 10s of edges in
//!   0–80 ms as the spring contact bounces. A naive "reset on every edge" design
//!   destroys the frame (each tiny mechanical bounce re-zeros s_col inside the
//!   active render window).
//!
//!   This FSM collapses all chatter via a **stroke blanking window**:
//!     - Any vibration within STATE_BLANKING_MS of the previous valid edge is
//!       treated as chatter: the FSM stays in `active` with `action = .none`,
//!       only refreshing `last_valid_stroke_ms`.
//!     - Only when the inter-edge gap *exceeds* STATE_BLANKING_MS do we recognise
//!       a new physical stroke (direction reversal), at which point the FSM
//!       returns `action = .request_start`, which causes the C bridge to write
//!       the gate fence and re-zero s_col/s_cat in the TIM7 ISR.
//!     - After INACTIVITY_TIMEOUT_MS of no valid edges, we transition to idle and
//!       fully_stop (auto-power-saving gate).

/// Stroke blanking window: edges within this gap are merged (mechanical chatter).
pub const STATE_BLANKING_MS: u32 = 150;

/// Auto-power-off after this many ms of no valid edge (no chatter, no real stroke).
pub const INACTIVITY_TIMEOUT_MS: u32 = 500;

pub const PovState = enum {
    /// ISR off, no display activity
    idle,
    /// ISR on, currently rendering a stroke (or holding the last frame)
    active,
};

pub const Action = enum {
    none,
    request_start,
    fully_stop,
};

pub const StepResult = struct {
    next: PovState,
    last_valid_stroke_ms: u32,
    action: Action,
};

/// Pure transition. The single invariant `last_valid_stroke_ms` (single timestamp)
/// gates both the chatter filter (no scattered patches in app.zig) and the
/// auto-stop timer — both kept as boundary conditions inside the FSM.
pub fn step(
    current: PovState,
    vibration: u8,
    now_ms: u32,
    last_valid_stroke_ms: u32,
) StepResult {
    // wrapping sub: safe because 0..2^31 is enough for INACTIVITY_TIMEOUT_MS range.
    const dt: u32 = now_ms -% last_valid_stroke_ms;
    const in_blanking: bool = last_valid_stroke_ms != 0 and dt < STATE_BLANKING_MS;

    return switch (current) {
        .idle => blk: {
            if (vibration != 0) {
                break :blk .{
                    .next = .active,
                    .last_valid_stroke_ms = now_ms,
                    .action = .request_start,
                };
            }
            break :blk .{
                .next = .idle,
                .last_valid_stroke_ms = last_valid_stroke_ms,
                .action = .none,
            };
        },
        .active => blk: {
            if (vibration != 0) {
                if (in_blanking) {
                    // CHATTER: trigger within blanking window of the previous
                    // valid edge.  Suppress fence; just refresh timestamp so the
                    // blanking window slides forward.
                    break :blk .{
                        .next = .active,
                        .last_valid_stroke_ms = now_ms,
                        .action = .none, // ISR keeps running, no fence, no reset
                    };
                }
                // NEW STROKE: gap > STATE_BLANKING_MS means the human hand has
                // physically reversed direction.  Issue fence to re-zero s_col.
                break :blk .{
                    .next = .active,
                    .last_valid_stroke_ms = now_ms,
                    .action = .request_start, // fence = reset col/cat
                };
            }
            // No vibration on this tick — check auto-stop.
            if (dt >= INACTIVITY_TIMEOUT_MS) {
                break :blk .{
                    .next = .idle,
                    .last_valid_stroke_ms = last_valid_stroke_ms,
                    .action = .fully_stop,
                };
            }
            break :blk .{
                .next = .active,
                .last_valid_stroke_ms = last_valid_stroke_ms,
                .action = .none,
            };
        },
    };
}