// ----------------------------------------------------------------------------
// UART Receive transactor (integration)
//
// Integrates the SV interface (egress FIFO + held config + task API) with the
// oversampling deframer core. The HVL side reaches the task API via u_if.
// Public UART pin uses a bare name (rxd).
// ----------------------------------------------------------------------------
module uart_rx_xtor #(
        parameter int MAX_DATA_BITS  = 8,
        parameter int DIV_WIDTH  = 16,
        parameter int OVERSAMPLE = 16
    ) (
        input  wire clock,
        input  wire reset,
        input  wire rxd
    );

    localparam int RSP_WIDTH = MAX_DATA_BITS + 4;

    // RV response channel between core and interface
    wire [RSP_WIDTH-1:0] rsp_dat;
    wire                 rsp_valid;
    wire                 rsp_ready;

    // Held configuration between interface and core
    wire [DIV_WIDTH-1:0] cfg_divisor;
    wire [3:0]           cfg_word_bits;
    wire                 cfg_parity_en;
    wire                 cfg_parity_even;
    wire                 cfg_parity_stick;
    wire [1:0]           cfg_stop_bits;

    uart_rx_xtor_if #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH)
    ) u_if (
        .clock(clock),
        .reset(reset),
        .rsp_dat(rsp_dat),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits)
    );

    uart_rx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_core (
        .clock(clock),
        .reset(reset),
        .rxd(rxd),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits),
        .rsp_dat(rsp_dat),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready)
    );

endmodule
