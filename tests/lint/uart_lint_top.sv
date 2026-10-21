// Lint elaboration top: every synthesizable core of the kit and the
// checker, at default parameters, on one line, with tx and rx sharing one
// baud tick as a 16550 does (K2). Link ports left open on purpose.
module uart_lint_top (
    input wire        clock,
    input wire        reset,
    input wire [15:0] divisor,
    input wire        brk
);
    wire tick;
    wire txd;

    uart_baud_xtor_core u_baud (
        .clock, .reset, .cfg_divisor(divisor), .tick);

    uart_tx_xtor_core u_tx (
        .clock, .reset, .tick,
        .txd, .brk, .busy(),
        .cfg_word_bits(4'd8), .cfg_parity_en(1'b0), .cfg_parity_even(1'b0),
        .cfg_parity_stick(1'b0), .cfg_stop_bits(2'd0),
        .req_dat(), .req_valid(), .req_ready());

    uart_rx_xtor_core u_rx (
        .clock, .reset, .tick,
        .rxd(txd),
        .cfg_word_bits(4'd8), .cfg_parity_en(1'b0), .cfg_parity_even(1'b0),
        .cfg_parity_stick(1'b0),
        .rsp_dat(), .rsp_valid(), .rsp_ready());

    uart_monitor_xtor_core u_mon (
        .clock, .reset, .tick,
        .line(txd),
        .cfg_word_bits(4'd8), .cfg_parity_en(1'b0), .cfg_parity_even(1'b0),
        .cfg_parity_stick(1'b0),
        .mon_dat(), .mon_valid(), .mon_ready());

    uart_proto_checker u_chk (
        .clock, .reset, .line(txd),
        .cfg_divisor(divisor));
endmodule
