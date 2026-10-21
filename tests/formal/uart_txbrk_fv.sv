// ======================================================================
// The tx core alone, with a free tick, a free break level and a free
// source (K2, K4). The tick may be any pattern, so the properties hold for
// any divisor and any change of it.
//
// Properties: tests/formal/PROPERTIES.md.
// ======================================================================
module uart_txbrk_fv #(
    parameter int MAX_DATA_BITS = 8,
    parameter int OVERSAMPLE    = 4
) (
    input  wire                     clock,
    input  wire                     reset,
    input  wire                     tick,
    input  wire                     brk,
    input  wire [MAX_DATA_BITS-1:0] src_char,
    input  wire                     src_valid,
    input  wire [3:0]               wbits,
    input  wire                     pen, pev, pst,
    input  wire [1:0]               stop
);
    wire txd, busy, ready;

    uart_tx_xtor_core #(.MAX_DATA_BITS(MAX_DATA_BITS), .OVERSAMPLE(OVERSAMPLE)) u_tx (
        .clock(clock), .reset(reset), .tick(tick),
        .txd(txd), .brk(brk), .busy(busy),
        .cfg_word_bits(wbits), .cfg_parity_en(pen), .cfg_parity_even(pev),
        .cfg_parity_stick(pst), .cfg_stop_bits(stop),
        .req_dat(src_char), .req_valid(src_valid), .req_ready(ready));

`ifdef FORMAL
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);
    always @(posedge clock) if (f_past_valid) assume (!reset);
    always @(*) assume (wbits >= 4'd5 && wbits <= 4'd8);

    // Ticks seen with brk low since brk was last high (saturating), and
    // whether the last break was a clean one: raised with the core idle.
    // A break raised over an accepted character loses that character (the
    // core's header), and its remains may follow the break at once.
    reg [3:0] f_since;
    reg       f_brk_seen;
    reg       f_brk_q;
    always @(posedge clock)
        if (reset) begin
            f_since <= '0; f_brk_seen <= 1'b0; f_brk_q <= 1'b0;
        end else begin
            f_brk_q <= brk;
            if (brk) begin
                f_since <= '0;
                if (!f_brk_q) f_brk_seen <= !busy;
            end else if (tick && f_since != 4'hF) begin
                f_since <= f_since + 1'b1;
            end
        end

    always @(posedge clock)
        if (f_past_valid && !reset && !$past(reset)) begin
            // (4) Break drives space at once and holds characters back.
            if (brk) assert (!txd);
            if (brk) assert (!ready);
            // (5) After a clean break, mark for at least one bit
            //     (OVERSAMPLE ticks) before the next start bit.
            if ($past(txd) && !txd && !brk && f_brk_seen)
                assert (f_since >= 4'(OVERSAMPLE));
            // (6) Bit edges are on ticks: with brk steady, txd changes
            //     only the clock after a tick.
            if (!brk && !$past(brk) && txd != $past(txd))
                assert ($past(tick));
            // (7) The core accepts only when idle or on a tick.
            if (ready && busy) assert (tick);
        end

    always @(posedge clock) begin
        cover (f_past_valid && !reset && f_brk_seen && $past(txd) && !txd && !brk);
        cover (f_past_valid && !reset && brk && busy);
    end
`endif
endmodule
