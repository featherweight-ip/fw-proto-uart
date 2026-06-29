// ----------------------------------------------------------------------------
// uart_proto_checker -- protocol-invariant checker for the UART line protocol.
// Passive: every port is an input, so it can be instantiated (or bound) on any UART
// line tap -- in a formal harness, a sim testbench, or alongside real RTL. It is
// given the active framing configuration (the same held cfg_* the transactors use)
// so it can reconstruct the bit period. Protocol invariants belong WITH the
// protocol, so this ships in the kit.
//
// Two parallel layers checking the same rules (see docs/protocol-property-checking.md
// for the methodology):
//   * SYNTHESIZABLE immediate-assert checkers -- single-edge `always @(posedge
//     clock)` with manually-registered history (no $past), so SymbiYosys/yosys read
//     them directly and they also run in any simulator. Always on.
//   * Concurrent SVA properties, gated by `ifdef UART_PROTO_SVA -- richer, more
//     readable sim checking (incl. X-checks); excluded from the yosys/formal flow.
//
// What is a WIRE invariant vs. an RX-detected error. A corrupted frame (bad parity,
// missing stop, break) is protocol-LEGAL on the wire -- the receiver DETECTS it and
// reports status; it is not a transmitter violation. So this checker does NOT assert
// framing correctness. The true transmitter-side line invariants are:
//   §5.1   idle / reset: the line is held at MARK (1) when not transmitting.
//   §5.1   bit-period stability: the line is driven STABLE for a whole bit period --
//          equivalently, two line transitions are never closer than one bit period.
//          This is the UART analog of a handshake "hold-until-accepted" rule and the
//          single most valuable always-on line check.
// Bit period = OVERSAMPLE * cfg_divisor system clocks (§4.9).
// ----------------------------------------------------------------------------
module uart_proto_checker #(
        parameter int MAX_DATA_BITS      = 8,
        parameter int DIV_WIDTH      = 16,
        parameter int OVERSAMPLE     = 16,
        parameter bit CHECK_STABILITY = 1'b1,  // enable bit-period stability check
        parameter int BPW            = DIV_WIDTH + $clog2(OVERSAMPLE) + 1
    ) (
        input  wire                  clock,
        input  wire                  reset,
        input  wire                  line,         // the tapped serial line

        // active framing configuration (same held level the transactors use)
        input  wire [DIV_WIDTH-1:0]  cfg_divisor,
        input  wire [3:0]            cfg_word_bits,
        input  wire                  cfg_parity_en,
        input  wire                  cfg_parity_even,
        input  wire                  cfg_parity_stick,
        input  wire [1:0]            cfg_stop_bits
    );

    wire [BPW-1:0] bit_period = cfg_divisor * OVERSAMPLE;

    // ------------------------------------------------------------------------
    // Registered history (no $past), so the immediate-assert checkers are
    // self-contained and synthesizable.
    // ------------------------------------------------------------------------
    reg        past_valid;
    reg        reset_q;
    reg        line_q;

    initial past_valid = 1'b0;

    always @(posedge clock) begin
        past_valid <= 1'b1;
        reset_q    <= reset;
        line_q     <= line;
    end

    wire changed = past_valid && !reset && !reset_q && (line != line_q);

    // The dwell check applies to DRIVEN bits. The line's pre-first-frame idle has no
    // minimum duration, so the very first transition out of post-reset idle is exempt
    // (a short reset->first-start gap is not a bit-period violation). seen_first arms
    // the check once the first transition has occurred.
    reg seen_first;
    always @(posedge clock) begin
        if (reset)        seen_first <= 1'b0;
        else if (changed) seen_first <= 1'b1;
    end

    // Dwell counter: how many cycles the line has held its current value. Reset to 1
    // on a change (the new value's first cycle), saturates otherwise. At a change,
    // `hold` still reads the length of the run that just ENDED.
    reg [BPW-1:0] hold;
    always @(posedge clock) begin
        if (reset)               hold <= '0;
        else if (line != line_q) hold <= {{(BPW-1){1'b0}}, 1'b1};
        else if (~&hold)         hold <= hold + 1'b1;
    end

    // ------------------------------------------------------------------------
    // Synthesizable immediate-assert checkers (yosys/SymbiYosys + simulator).
    // ------------------------------------------------------------------------
    always @(posedge clock) begin
        // §5.1: while in reset, the line is held at mark (idle level). Registered so
        //       it is evaluated the cycle after reset is observed.
        if (past_valid && reset_q)
            assert (line == 1'b1);

        // §5.1: bit-period stability -- the line may only change after being driven
        //       for a full bit period, so consecutive transitions are >= bit_period
        //       cycles apart. (Vacuous when bit_period <= 1, e.g. a degenerate
        //       formal config; meaningful at real oversampled rates.)
        if (CHECK_STABILITY && changed && seen_first && (bit_period > 1))
            assert (hold >= bit_period);
    end

    // ------------------------------------------------------------------------
    // Non-vacuity covers -- prove the interesting cases are reachable.
    // ------------------------------------------------------------------------
    always @(posedge clock) begin
        if (!reset && past_valid && !reset_q) begin
            cover (line_q && !line);          // a start edge (idle mark -> space)
            cover (!line_q && line);          // a return to mark (bit/stop edge)
            cover (changed && (hold >= bit_period));  // a full-bit-period transition
        end
    end

`ifdef UART_PROTO_SVA
    // ------------------------------------------------------------------------
    // Concurrent SVA properties (simulation) -- the same rules, more readable, plus
    // value-domain (X) checks that have no meaning in the formal flow.
    // ------------------------------------------------------------------------
    default clocking cb @(posedge clock); endclocking

    // §5.1 reset -> mark (do not disable on reset for this one).
    a_reset_mark: assert property (@(posedge clock) $past(reset) |-> (line == 1'b1));

    // NOTE: bit-period stability (§5.1) is checked by the SYNTHESIZABLE immediate-
    // assert layer above (the authoritative, always-on, formal-relevant form). A
    // concurrent-SVA duplicate is intentionally omitted: SVA samples `line` in the
    // preponed region, which disagrees with the clocked dwell counter for a
    // combinational line driven by asynchronous sim stimulus (e.g. a bit-banged test
    // frame), producing false fires. The immediate layer enforces the exact bound.

    // value-domain (X) check -- the line is never unknown when sampled. Sim-only.
    a_no_x: assert property (@(posedge clock) disable iff (reset) !$isunknown(line));
`endif

endmodule
