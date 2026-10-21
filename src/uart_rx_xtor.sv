// ----------------------------------------------------------------------------
// UART receive transactor (integration): interface (egress FIFO, held
// configuration, task API) + baud tick core + receive core. The task API is
// u_if. The public pin is rxd, which must already be synchronous to clock.
// ----------------------------------------------------------------------------
module uart_rx_xtor #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH     = 16,
        parameter int OVERSAMPLE    = 16
    ) (
        input  wire clock,
        input  wire reset,
        input  wire rxd
    );

    localparam int RSP_WIDTH = MAX_DATA_BITS + 4;

    wire [RSP_WIDTH-1:0] rsp_dat;
    wire                 rsp_valid;
    wire                 rsp_ready;
    wire [DIV_WIDTH-1:0] cfg_divisor;
    wire [3:0]           cfg_word_bits;
    wire                 cfg_parity_en;
    wire                 cfg_parity_even;
    wire                 cfg_parity_stick;
    wire [1:0]           cfg_stop_bits;     // the receiver checks one stop bit
    wire                 tick;

    uart_rx_xtor_if #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH)
    ) u_if (
        .clock(clock), .reset(reset),
        .rsp_dat(rsp_dat), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .cfg_divisor(cfg_divisor), .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en), .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick), .cfg_stop_bits(cfg_stop_bits)
    );

    uart_baud_xtor_core #(.DIV_WIDTH(DIV_WIDTH)) u_baud (
        .clock(clock), .reset(reset), .cfg_divisor(cfg_divisor), .tick(tick)
    );

    uart_rx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_core (
        .clock(clock), .reset(reset), .tick(tick),
        .rxd(rxd),
        .cfg_word_bits(cfg_word_bits), .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even), .cfg_parity_stick(cfg_parity_stick),
        .rsp_dat(rsp_dat), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready)
    );

endmodule
