// ======================================================================
// Back-to-back FORMAL verification component for the UART kit (design §17).
//
// Wires the kit's two PROTOCOL CORES -- uart_tx_xtor_core (serializer) and
// uart_rx_xtor_core (oversampling deframer) -- directly together over a shared serial
// line and lets SymbiYosys prove the connection. The cores are the kit's real,
// synthesizable RTL (clocked FSMs). UART is two one-way streams, so the harness drives
// ONE free stream: a free CHARACTER producer into the transmitter's req-link, while
// the receiver's up-link is freely drained.
//
//   free char src --req--> [tx core] --serial line--> [rx core] --rsp--> free sink
//
// THE DEPTH PROBLEM (design §17). A character crosses in frame_bits*OVERSAMPLE*divisor
// cycles. At the real 16x rate this is >160 cycles -- far too deep for an end-to-end
// BMC. So the proof runs at a SHRUNK rate: OVERSAMPLE=2, divisor=1 => bit period = 2
// cycles, a frame ~24 cycles, which a modest BMC depth covers. The framing config is
// tied to constants so both cores are baud-locked (matched-config assumption, O-3).
//
// (yosys cannot read SV structs/packages, so the flow runs this file + the cores
// through sv2v -DFORMAL into plain Verilog first; see tests/formal/flow.yaml.)
//
// Run:  dfm run fw.proto.uart.fv
// ======================================================================
module uart_proto_fv #(
    parameter int MAX_DATA_BITS  = 8,
    parameter int DIV_WIDTH  = 16,
    parameter int OVERSAMPLE = 2,                 // shrunk for tractable BMC depth
    parameter int RSP_WIDTH  = MAX_DATA_BITS + 4
) (
    input  wire                  clock,
    input  wire                  reset,
    // free CHARACTER producer feeding the transmitter's req-link
    input  wire [MAX_DATA_BITS-1:0]  src_char,
    input  wire                  src_valid,
    // free sink draining the receiver's up-link
    input  wire                  snk_ready
);
    // ---- baud-locked framing configuration (constants: 8N1, divisor 1) ----
    localparam [DIV_WIDTH-1:0] CFG_DIV   = 1;
    localparam [3:0]           CFG_WBITS = 8;
    localparam                 CFG_PEN   = 1'b0;
    localparam                 CFG_PEVEN = 1'b0;
    localparam                 CFG_PSTK  = 1'b0;
    localparam [1:0]           CFG_STOP  = 2'd0;

    // ---- the shared serial line + internal link wires ----
    wire                  txd;
    wire                  tx_req_ready;            // tx req-link ready (to src)
    wire [RSP_WIDTH-1:0]  rx_rsp_dat;              // rx up-link (to sink)
    wire                  rx_rsp_valid;

    // transmitter core: req-link CONSUMER (from src), serial-line driver.
    uart_tx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS), .DIV_WIDTH(DIV_WIDTH), .OVERSAMPLE(OVERSAMPLE)
    ) u_tx (
        .clock(clock), .reset(reset),
        .txd(txd),
        .cfg_divisor(CFG_DIV), .cfg_word_bits(CFG_WBITS), .cfg_parity_en(CFG_PEN),
        .cfg_parity_even(CFG_PEVEN), .cfg_parity_stick(CFG_PSTK), .cfg_stop_bits(CFG_STOP),
        .req_dat(src_char), .req_valid(src_valid), .req_ready(tx_req_ready)
    );

    // receiver core: serial-line sampler, up-link PRODUCER (to sink).
    uart_rx_xtor_core #(
        .MAX_DATA_BITS(MAX_DATA_BITS), .DIV_WIDTH(DIV_WIDTH), .OVERSAMPLE(OVERSAMPLE)
    ) u_rx (
        .clock(clock), .reset(reset),
        .rxd(txd),
        .cfg_divisor(CFG_DIV), .cfg_word_bits(CFG_WBITS), .cfg_parity_en(CFG_PEN),
        .cfg_parity_even(CFG_PEVEN), .cfg_parity_stick(CFG_PSTK), .cfg_stop_bits(CFG_STOP),
        .rsp_dat(rx_rsp_dat), .rsp_valid(rx_rsp_valid), .rsp_ready(snk_ready)
    );

    // The line-protocol invariants (reset -> mark; bit-period stability) are checked
    // by the kit's reusable checker -- always on, so its immediate asserts become
    // proof obligations. CHECK_STABILITY is disabled here: at the shrunk bit period
    // (2 cycles) it is near-vacuous, and it is meaningfully exercised in the sim TB
    // at the real oversampled rate (design §17). This harness adds the property the
    // checker can't see: end-to-end DATA INTEGRITY.
    uart_proto_checker #(
        .OVERSAMPLE(OVERSAMPLE), .CHECK_STABILITY(1'b0)
    ) u_chk (
        .clock(clock), .reset(reset), .line(txd),
        .cfg_divisor(CFG_DIV), .cfg_word_bits(CFG_WBITS), .cfg_parity_en(CFG_PEN),
        .cfg_parity_even(CFG_PEVEN), .cfg_parity_stick(CFG_PSTK), .cfg_stop_bits(CFG_STOP)
    );

`ifdef FORMAL
    // ---- preamble: mask first cycle, start in reset, then run ----
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*)             if (!f_past_valid) assume (reset);
    always @(posedge clock) if (f_past_valid)  assume (!reset);

    // handshake events
    wire in_char  = src_valid    && tx_req_ready;   // a character enters the tx
    wire out_char = rx_rsp_valid && snk_ready;      // a character leaves the rx

    // SRC LINK CONTRACT: a ready/valid producer holds valid+data stable while the
    // consumer (the tx core) is not ready -- so the free source behaves like a real
    // upstream FIFO and the tracked character is well-defined.
    always @(posedge clock)
        if (f_past_valid && !$past(reset))
            if ($past(src_valid) && !$past(tx_req_ready)) begin
                assume (src_valid);
                assume (src_char == $past(src_char));
            end

    // DATA INTEGRITY end to end, via an arbitrary tracked position. One symbolic
    // index proves all positions: the f_idx-th character the receiver delivers equals
    // the f_idx-th character the transmitter accepted, with CLEAN status (matched
    // config, clean line, no overrun since snk drains => no loss).
    localparam int CW = 4;
    (* anyconst *) reg [CW-1:0] f_idx;

    reg [CW-1:0]        in_cnt, out_cnt;
    reg [MAX_DATA_BITS-1:0] f_data;
    reg                 f_have;

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

    // the f_idx-th delivered character equals the f_idx-th accepted, status clean
    wire [MAX_DATA_BITS-1:0] rx_data   = rx_rsp_dat[RSP_WIDTH-1 -: MAX_DATA_BITS];
    wire [3:0]           rx_status = rx_rsp_dat[3:0];
    always @(posedge clock)
        if (!reset)
            if (out_char && (out_cnt == f_idx)) begin
                assert (f_have);
                assert (rx_data   == f_data);
                assert (rx_status == 4'h0);
            end

    // non-vacuity: a tracked character actually traverses end to end
    always @(posedge clock)
        cover (!reset && out_char && (out_cnt == f_idx) && f_have);
`endif
endmodule
