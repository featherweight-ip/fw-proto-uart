// ======================================================================
// The rx core alone, on a free line with a free tick (K4): whatever the
// line does, the status the core reports is consistent, and one break
// gives one break character. The sink always takes the character, so
// every completed character is seen.
//
// Properties: tests/formal/PROPERTIES.md.
// ======================================================================
module uart_rxbrk_fv #(
    parameter int MAX_DATA_BITS = 8,
    parameter int OVERSAMPLE    = 2,
    parameter int RSP_WIDTH     = MAX_DATA_BITS + 4
) (
    input  wire clock,
    input  wire reset,
    input  wire tick,
    input  wire rxd
);
    (* anyconst *) reg [3:0] f_wbits;
    (* anyconst *) reg       f_pen, f_pev, f_pst;

    wire [RSP_WIDTH-1:0] rsp_dat;
    wire                 rsp_valid;

    uart_rx_xtor_core #(.MAX_DATA_BITS(MAX_DATA_BITS), .OVERSAMPLE(OVERSAMPLE)) u_rx (
        .clock(clock), .reset(reset), .tick(tick),
        .rxd(rxd),
        .cfg_word_bits(f_wbits), .cfg_parity_en(f_pen), .cfg_parity_even(f_pev),
        .cfg_parity_stick(f_pst),
        .rsp_dat(rsp_dat), .rsp_valid(rsp_valid), .rsp_ready(1'b1));

    wire [MAX_DATA_BITS-1:0] data = rsp_dat[RSP_WIDTH-1 -: MAX_DATA_BITS];
    wire oe = rsp_dat[3], bi = rsp_dat[2], fe = rsp_dat[1], pe = rsp_dat[0];

`ifdef FORMAL
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);
    always @(posedge clock) if (f_past_valid) assume (!reset);
    always @(*) assume (f_wbits >= 4'd5 && f_wbits <= 4'd8);

    // Set by a break character, cleared by mark seen on a tick.
    reg f_wait_mark;
    reg f_bi_seen;
    always @(posedge clock)
        if (reset) begin
            f_wait_mark <= 1'b0; f_bi_seen <= 1'b0;
        end else begin
            // The core is already waiting when the break character is
            // valid, so a mark tick in that same clock counts.
            if (rsp_valid && bi) f_bi_seen <= 1'b1;
            f_wait_mark <= ((rsp_valid && bi) || f_wait_mark) && !(tick && rxd);
        end

    wire [MAX_DATA_BITS-1:0] mask = MAX_DATA_BITS'((9'd1 << f_wbits) - 9'd1);

    always @(posedge clock)
        if (!reset && rsp_valid) begin
            // (8) A break character is data 0 with BI alone.
            if (bi) assert (data == '0 && !fe && !pe);
            // (9) One break, one character: none completes until the
            //     line has been mark on a tick.
            assert (!f_wait_mark);
            // (10) Bits above the word length are 0; PE only with parity
            //      on; the sink always takes, so nothing overruns.
            assert ((data & ~mask) == '0);
            if (pe) assert (f_pen);
            assert (!oe);
        end

    always @(posedge clock) begin
        cover (!reset && rsp_valid && bi);
        cover (!reset && rsp_valid && !bi && f_bi_seen);
        cover (!reset && rsp_valid && fe);
        cover (!reset && rsp_valid && pe);
    end
`endif
endmodule
