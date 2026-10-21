// ----------------------------------------------------------------------------
// UART transmit transactor (integration): interface (task API) + baud tick
// core + transmit core. The task API is u_if. The public pin is txd.
//
// txd is the core's output, or, while the interface's error injection owns
// the line (K6), the interface's ovr_val. That mux is the only thing here
// that is not a kit core, and it is VIP-only: a design uses the cores.
// ----------------------------------------------------------------------------
module uart_tx_xtor #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH     = 16,
        parameter int OVERSAMPLE    = 16
    ) (
        input  wire clock,
        input  wire reset,
        output wire txd
    );

    wire [MAX_DATA_BITS-1:0] req_dat;
    wire                     req_valid;
    wire                     req_ready;
    wire                     busy;
    wire [DIV_WIDTH-1:0]     cfg_divisor;
    wire [3:0]               cfg_word_bits;
    wire                     cfg_parity_en;
    wire                     cfg_parity_even;
    wire                     cfg_parity_stick;
    wire [1:0]               cfg_stop_bits;
    wire                     brk;
    wire                     ovr_en;
    wire                     ovr_val;
    wire                     tick;
    wire                     core_txd;

    assign txd = ovr_en ? ovr_val : core_txd;

    uart_tx_xtor_if #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH)
    ) u_if (
        .clock(clock), .reset(reset), .oversample(8'(OVERSAMPLE)),
        .req_dat(req_dat), .req_valid(req_valid), .req_ready(req_ready),
        .busy(busy),
        .cfg_divisor(cfg_divisor), .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en), .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick), .cfg_stop_bits(cfg_stop_bits),
        .brk(brk), .ovr_en(ovr_en), .ovr_val(ovr_val)
    );

    uart_baud_xtor_core #(.DIV_WIDTH(DIV_WIDTH)) u_baud (
        .clock(clock), .reset(reset), .cfg_divisor(cfg_divisor), .tick(tick)
    );

    uart_tx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_core (
        .clock(clock), .reset(reset), .tick(tick),
        .txd(core_txd), .brk(brk), .busy(busy),
        .cfg_word_bits(cfg_word_bits), .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even), .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits),
        .req_dat(req_dat), .req_valid(req_valid), .req_ready(req_ready)
    );

endmodule
