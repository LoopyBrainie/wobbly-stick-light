//! Board-level constants and pin mappings for the wobbly-stick-light.
//! Everything here is resolved at comptime — zero runtime overhead.

// ── MCU identification ──
pub const mcu = struct {
    pub const name = "STM32F103RCT6";
    pub const core = "Cortex-M3";
    pub const flash_kb = 256;
    pub const sram_kb = 48;
    pub const max_clock_hz = 72_000_000;
};

// ── LED pins (POV wand) ──
pub const led = struct {
    pub const port = "GPIOB";
    pub const pins = [_]u8{ 0, 1, 5, 6, 7, 8, 9 }; // PB0-PB1, PB5-PB9
};

// ── IMU (MPU6050) ──
pub const imu = struct {
    pub const i2c = "I2C1";
    pub const scl_port = "GPIOB";
    pub const scl_pin = 6;
    pub const sda_port = "GPIOB";
    pub const sda_pin = 7;
    pub const addr = 0x68; // AD0 low
};

// ── Peripheral clock enables ──
pub const rcc = struct {
    pub const ahb_prescaler = 1;
    pub const apb1_prescaler = 2;
    pub const apb2_prescaler = 1;
};
