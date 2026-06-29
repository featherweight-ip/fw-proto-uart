// ----------------------------------------------------------------------------
// UART Transmit transactor (integration)
//
// Integrates the SV interface (FIFO + held config + task API) with the serializer
// core. The HVL side reaches the task API via the inner interface instance: u_if.
// Public UART pin uses a bare name (txd). OVERSAMPLE is the only knob a consumer
// overrides (e.g. shrunk for a tractable formal proof).
// ----------------------------------------------------------------------------
module uart_tx_xtor #(
        parameter int MAX_DATA_BITS  = 8,
        parameter int DIV_WIDTH  = 16,
        parameter int OVERSAMPLE = 16
    ) (
        input  wire clock,
        input  wire reset,
        output wire txd
    );

    // RV request channel between interface and core
    wire [MAX_DATA_BITS-1:0] req_dat;
    wire                 req_valid;
    wire                 req_ready;

    // Held configuration between interface and core
    wire [DIV_WIDTH-1:0] cfg_divisor;
    wire [3:0]           cfg_word_bits;
    wire                 cfg_parity_en;
    wire                 cfg_parity_even;
    wire                 cfg_parity_stick;
    wire [1:0]           cfg_stop_bits;

    uart_tx_xtor_if #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH)
    ) u_if (
        .clock(clock),
        .reset(reset),
        .req_dat(req_dat),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits)
    );

    uart_tx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS),
        .DIV_WIDTH(DIV_WIDTH),
        .OVERSAMPLE(OVERSAMPLE)
    ) u_core (
        .clock(clock),
        .reset(reset),
        .txd(txd),
        .cfg_divisor(cfg_divisor),
        .cfg_word_bits(cfg_word_bits),
        .cfg_parity_en(cfg_parity_en),
        .cfg_parity_even(cfg_parity_even),
        .cfg_parity_stick(cfg_parity_stick),
        .cfg_stop_bits(cfg_stop_bits),
        .req_dat(req_dat),
        .req_valid(req_valid),
        .req_ready(req_ready)
    );

endmodule
