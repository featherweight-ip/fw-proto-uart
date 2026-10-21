// ======================================================================
// Back-to-back formal harness: tx core -> line -> rx core, both driven by
// one uart_baud_xtor_core, as a 16550 shares its divisor (K2).
//
//   free src --req--> [tx core] --line--> [rx core] --rsp--> free snk
//                          \---- tick ----/
//
// Framing and divisor are anyconst: any word length 5..8, any parity mode,
// either stop setting, divisor 1 or 2. A frame at the real 16x rate is far
// too deep for BMC, so OVERSAMPLE is 2 (a frame is 14..24 ticks); the
// cores' timing is in ticks, so the shrink changes only the counts.
// Break is held off (tx_brk_fv.sv covers it).
//
// Properties: tests/formal/PROPERTIES.md.
// ======================================================================
module uart_proto_fv #(
    parameter int MAX_DATA_BITS = 8,
    parameter int OVERSAMPLE    = 2,
    parameter int RSP_WIDTH     = MAX_DATA_BITS + 4
) (
    input  wire                     clock,
    input  wire                     reset,
    input  wire [MAX_DATA_BITS-1:0] src_char,
    input  wire                     src_valid,
    input  wire                     snk_ready
);
    (* anyconst *) reg [1:0] f_div;
    (* anyconst *) reg [3:0] f_wbits;
    (* anyconst *) reg       f_pen, f_pev, f_pst;
    (* anyconst *) reg [1:0] f_stop;

    wire                 tick;
    wire                 txd;
    wire                 tx_ready;
    wire                 tx_busy;
    wire [RSP_WIDTH-1:0] rx_dat;
    wire                 rx_valid;

    uart_baud_xtor_core #(.DIV_WIDTH(2)) u_baud (
        .clock(clock), .reset(reset), .cfg_divisor(f_div), .tick(tick));

    uart_tx_xtor_core #(.MAX_DATA_BITS(MAX_DATA_BITS), .OVERSAMPLE(OVERSAMPLE)) u_tx (
        .clock(clock), .reset(reset), .tick(tick),
        .txd(txd), .brk(1'b0), .busy(tx_busy),
        .cfg_word_bits(f_wbits), .cfg_parity_en(f_pen), .cfg_parity_even(f_pev),
        .cfg_parity_stick(f_pst), .cfg_stop_bits(f_stop),
        .req_dat(src_char), .req_valid(src_valid), .req_ready(tx_ready));

    uart_rx_xtor_core #(.MAX_DATA_BITS(MAX_DATA_BITS), .OVERSAMPLE(OVERSAMPLE)) u_rx (
        .clock(clock), .reset(reset), .tick(tick),
        .rxd(txd),
        .cfg_word_bits(f_wbits), .cfg_parity_en(f_pen), .cfg_parity_even(f_pev),
        .cfg_parity_stick(f_pst),
        .rsp_dat(rx_dat), .rsp_valid(rx_valid), .rsp_ready(snk_ready));

    // Line invariants (reset -> mark, bit-period stability), checked at the
    // shrunk rate: every bit is exactly OVERSAMPLE * divisor clocks.
    uart_proto_checker #(.OVERSAMPLE(OVERSAMPLE)) u_chk (
        .clock(clock), .reset(reset), .line(txd),
        .cfg_divisor({14'b0, f_div}));

`ifdef FORMAL
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);
    always @(posedge clock) if (f_past_valid) assume (!reset);

    // Legal configuration.
    always @(*) begin
        assume (f_div == 2'd1 || f_div == 2'd2);
        assume (f_wbits >= 4'd5 && f_wbits <= 4'd8);
    end

    // The source holds valid and data until accepted (ready/valid).
    always @(posedge clock)
        if (f_past_valid && !$past(reset) && $past(src_valid) && !$past(tx_ready)) begin
            assume (src_valid);
            assume (src_char == $past(src_char));
        end

    // The sink takes a character within a frame, so nothing is lost; the
    // overrun path is the rx harness's.
    reg [5:0] f_stall;
    always @(posedge clock)
        if (reset || !rx_valid || snk_ready) f_stall <= '0;
        else                                 f_stall <= f_stall + 1'b1;
    always @(*) if (f_stall >= 6'd8) assume (snk_ready);

    wire in_char  = src_valid && tx_ready;
    wire out_char = rx_valid && snk_ready;

    // (1) Integrity: the f_idx-th character delivered is the f_idx-th
    //     accepted, masked to the word length, with clean status.
    localparam int CW = 3;
    (* anyconst *) reg [CW-1:0] f_idx;
    reg [CW-1:0]            in_cnt, out_cnt;
    reg [MAX_DATA_BITS-1:0] f_data;
    reg                     f_have;

    always @(posedge clock)
        if (reset) begin
            in_cnt <= '0; out_cnt <= '0; f_have <= 1'b0;
        end else begin
            if (in_char) begin
                if (in_cnt == f_idx) begin f_data <= src_char; f_have <= 1'b1; end
                in_cnt <= in_cnt + 1'b1;
            end
            if (out_char) out_cnt <= out_cnt + 1'b1;
        end

    wire [MAX_DATA_BITS-1:0] mask    = MAX_DATA_BITS'((9'd1 << f_wbits) - 9'd1);
    wire [MAX_DATA_BITS-1:0] rx_data = rx_dat[RSP_WIDTH-1 -: MAX_DATA_BITS];
    wire [3:0]               rx_stat = rx_dat[3:0];

    always @(posedge clock)
        if (!reset && out_char && out_cnt == f_idx) begin
            assert (f_have);
            assert (rx_data == (f_data & mask));
            assert (rx_stat == 4'h0);
        end

    // (2) Nothing arrives that was not sent.
    always @(posedge clock)
        if (!reset && out_char) assert (out_cnt != in_cnt || in_char);

    // (3) The link handshake: ready when idle, or at the very end of the
    //     stop bit (back-to-back frames).
    always @(*) if (!reset && tx_ready && tx_busy) assert (tick);

    always @(posedge clock) begin
        cover (!reset && out_char && out_cnt == f_idx && f_have);
        cover (!reset && out_char && out_cnt == 3'd1);
    end
`endif
endmodule
