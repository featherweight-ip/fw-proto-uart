// ----------------------------------------------------------------------------
// UART Monitor transactor (integration)
//
// Integrates the SV interface (egress FIFO + held config + task API) with the
// passive deframer core. The HVL side reaches the task API via u_if. The public tap
// (line) is an input -- the monitor drives nothing.
// ----------------------------------------------------------------------------
module uart_monitor_xtor #(
        parameter int MAX_DATA_BITS  = 8,
        parameter int DIV_WIDTH  = 16,
        parameter int OVERSAMPLE = 16
    ) (
        input  wire clock,
        input  wire reset,
        input  wire line
    );

    localparam int MON_WIDTH = MAX_DATA_BITS + 4;

    // RV egress channel between core and interface
    wire [MON_WIDTH-1:0] mon_dat;
    wire                 mon_valid;
    wire                 mon_ready;

    // Held configuration between interface and core
    wire [DIV_WIDTH-1:0] cfg_divisor;
    wire [3:0]           cfg_word_bits;
    wire                 cfg_parity_en;
    wire                 cfg_parity_even;
    wire                 cfg_parity_stick;
    wire [1:0]           cfg_stop_bits;

    uart_monitor_xtor_if #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH)
    ) u_if (
        .clock(clock),
        .reset(reset),
        .mon_dat(mon_dat),
        .mon_valid(mon_valid),
        .mon_ready(mon_ready),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits)
    );

    uart_monitor_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_core (
        .clock(clock),
        .reset(reset),
        .line(line),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits),
        .mon_dat(mon_dat),
        .mon_valid(mon_valid),
        .mon_ready(mon_ready)
    );

endmodule
