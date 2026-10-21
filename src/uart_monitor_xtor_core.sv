`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART monitor core (pure module, signal-level ports)
//
// Passively deframes one tapped line (STX or SRX) exactly as the receiver
// does, by instantiating uart_rx_xtor_core, and emits one observed
// character with its status per frame. It drives nothing onto the line;
// which line it taps (is_tx) is added by the monitor bridge.
//
//   line   : the tapped serial line (idle = mark = 1)
//   tick   : the oversampling enable (uart_baud_xtor_core), at the tapped
//            link's rate
//   cfg_*  : framing; it must match the tapped link
//   mon_*  : ready/valid initiator (core -> link), { data, status }
//
// A monitor cannot backpressure the line. Its output is single-entry, so a
// character that completes while the previous one is still held is dropped
// and OE is set on the next one; the monitor xtor_if drains it every clock.
// ----------------------------------------------------------------------------
module uart_monitor_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int OVERSAMPLE    = 16,
        parameter int MON_WIDTH     = MAX_DATA_BITS + 4
    ) (
        input  wire                     clock,
        input  wire                     reset,
        input  wire                     tick,

        input  wire                     line,

        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,

        output wire [MON_WIDTH-1:0]     mon_dat,
        output wire                     mon_valid,
        input  wire                     mon_ready
    );

    uart_rx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .OVERSAMPLE(OVERSAMPLE),
        .RSP_WIDTH(MON_WIDTH)
    ) u_rx (
        .clock(clock),
        .reset(reset),
        .tick(tick),
        .rxd(line),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .rsp_dat(mon_dat),
        .rsp_valid(mon_valid),
        .rsp_ready(mon_ready)
    );

endmodule
