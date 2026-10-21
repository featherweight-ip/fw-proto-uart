`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART receive core (pure module, signal-level ports)
//
// Deframes the serial input and puts each character, with its line status,
// on the rsp link.
//
//   rxd    : the serial input (idle = mark = 1), already synchronized
//   tick   : the oversampling enable from uart_baud_xtor_core (K2). A bit is
//            OVERSAMPLE ticks
//   rsp_*  : ready/valid initiator (core -> link), { data, status }
//   cfg_*  : framing, sampled at the start bit, so a change applies from the
//            next character (K1). Only the first stop bit is checked, so the
//            stop-bit count is not an input
//
// Sampling: the line is looked at on ticks. The first tick that sees space
// starts a character; each bit is then sampled once, OVERSAMPLE/2 ticks into
// it (a single mid-bit sample, as the 16550 does). A start bit that is mark
// again at its middle is a glitch, and the core goes back to idle.
//
// Status (LSR-aligned, uart_xtor_macros.svh):
//   PE  the parity bit does not match
//   FE  the first stop bit is space
//   BI  the whole frame was space: data 0, parity 0, stop 0 (K4). The
//       character is delivered as data 0 with BI alone, and the core then
//       waits for the line to return to mark before it looks for a start
//       bit, so one break gives one character, as a 16550 does
//   OE  characters were lost because the link had not taken the one before
//       (single-entry output); set on the next character delivered
// ----------------------------------------------------------------------------
module uart_rx_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int OVERSAMPLE    = 16,
        parameter int RSP_WIDTH     = MAX_DATA_BITS + 4
    ) (
        input  wire                     clock,
        input  wire                     reset,
        input  wire                     tick,

        input  wire                     rxd,

        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,

        output wire [RSP_WIDTH-1:0]     rsp_dat,
        output wire                     rsp_valid,
        input  wire                     rsp_ready
    );

    typedef `UART_RX_RSP_S(MAX_DATA_BITS) rsp_s;

    localparam int SW = $clog2(OVERSAMPLE);
    localparam [SW-1:0] HALF_TICKS = SW'(OVERSAMPLE/2 - 1);
    localparam [SW-1:0] BIT_TICKS  = SW'(OVERSAMPLE - 1);

    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        START  = 3'd1,
        DATA   = 3'd2,
        PARITY = 3'd3,
        STOP   = 3'd4,
        BREAK  = 3'd5       // after a break character: wait for mark
    } state_e;

    state_e                 state;
    reg [SW-1:0]            scnt;        // ticks to the next sample
    reg [MAX_DATA_BITS-1:0] rxbuf;
    reg [3:0]               bit_idx;
    reg                     rx_parity;
    reg [3:0]               wbits_q;
    reg                     parity_en_q;
    reg                     parity_even_q;
    reg                     parity_stick_q;

    reg                     rsp_valid_r;
    rsp_s                   rsp_q;
    reg                     overrun_q;

    assign rsp_dat   = rsp_q;
    assign rsp_valid = rsp_valid_r;

    wire rsp_fire = rsp_valid_r && rsp_ready;
    wire sample   = tick && (scnt == '0);

    function automatic logic calc_parity(input logic [MAX_DATA_BITS-1:0] d,
                                         input logic even, input logic stick);
        logic p;
        p = ^d;                 // rxbuf is cleared at the start bit, so the
        if (!even) p = ~p;      // bits above the word length are 0
        if (stick) p = ~even;
        return p;
    endfunction

    // At the stop-bit sample.
    wire is_break = !rxd && (rxbuf == '0) && (!parity_en_q || !rx_parity);
    wire fe       = !rxd && !is_break;
    wire pe       = parity_en_q && !is_break &&
                    (rx_parity != calc_parity(rxbuf, parity_even_q, parity_stick_q));

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            scnt           <= '0;
            rxbuf          <= '0;
            bit_idx        <= '0;
            rx_parity      <= 1'b0;
            wbits_q        <= 4'd8;
            parity_en_q    <= 1'b0;
            parity_even_q  <= 1'b0;
            parity_stick_q <= 1'b0;
            rsp_valid_r    <= 1'b0;
            rsp_q          <= '0;
            overrun_q      <= 1'b0;
        end else begin
            if (rsp_fire)
                rsp_valid_r <= 1'b0;

            if (tick && scnt != '0)
                scnt <= scnt - 1'b1;

            case (state)
                IDLE: begin
                    if (tick && !rxd) begin
                        scnt  <= HALF_TICKS;
                        state <= START;
                    end
                end
                START: begin
                    if (sample) begin
                        if (rxd) begin
                            state <= IDLE;
                        end else begin
                            rxbuf          <= '0;
                            bit_idx        <= 4'd0;
                            wbits_q        <= cfg_word_bits;
                            parity_en_q    <= cfg_parity_en;
                            parity_even_q  <= cfg_parity_even;
                            parity_stick_q <= cfg_parity_stick;
                            scnt           <= BIT_TICKS;
                            state          <= DATA;
                        end
                    end
                end
                DATA: begin
                    if (sample) begin
                        rxbuf[bit_idx[$clog2(MAX_DATA_BITS)-1:0]] <= rxd;
                        scnt <= BIT_TICKS;
                        if ((bit_idx + 4'd1) < wbits_q)
                            bit_idx <= bit_idx + 4'd1;
                        else if (parity_en_q)
                            state <= PARITY;
                        else
                            state <= STOP;
                    end
                end
                PARITY: begin
                    if (sample) begin
                        rx_parity <= rxd;
                        scnt      <= BIT_TICKS;
                        state     <= STOP;
                    end
                end
                STOP: begin
                    if (sample) begin
                        if (!rsp_valid_r || rsp_fire) begin
                            rsp_q.data        <= rxbuf;
                            rsp_q.parity_err  <= pe;
                            rsp_q.framing_err <= fe;
                            rsp_q.brk         <= is_break;
                            rsp_q.overrun     <= overrun_q;
                            rsp_valid_r       <= 1'b1;
                            overrun_q         <= 1'b0;
                        end else begin
                            overrun_q         <= 1'b1;
                        end
                        state <= is_break ? BREAK : IDLE;
                    end
                end
                BREAK: begin
                    if (tick && rxd)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
