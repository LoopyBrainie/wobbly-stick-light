//! Time-window helpers — pure functions, no I/O.
//!
//! `g_systick_ms` is a `volatile u32` that wraps around every ~49 days.
//! Subtraction handles the wrap naturally when both operands are unsigned
//! and the result is interpreted modulo 2^32.

/// True if `(now - then)` has not yet reached `window_ms`.
/// Handles u32 wrap-around: when `now < then` the subtraction underflows
/// to a huge value, which is the correct "very long ago" answer.
pub fn within_ms(now: u32, then: u32, window_ms: u32) bool {
    return now -% then < window_ms;
}