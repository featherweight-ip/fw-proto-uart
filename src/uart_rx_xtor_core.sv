`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART Receive core transactor (pure module, signal-level ports)
//
// Bridges the asynchronous UART serial line (protocol side) to a ready/valid
// character stream (FIFO side): it DESERIALIZES each frame off the line and emits
// the recovered character plus its line-error status.
//
//   - rxd   : the serial input line (idle = mark = 1)
//   - cfg_* : held runtime framing configuration (sampled at start-bit detect)
//   - rsp_* : RV initiator port (core -> FIFO)  { data, status }
//
// Timing: the receiver OVERSAMPLES -- the oversampling sub-tick is cfg_divisor
// clocks, and one bit-period is OVERSAMPLE sub-ticks (§4.9). On the idle->start
// (mark->space) edge it waits half a bit-period to the CENTER of the start bit,
// re-confirms space, then samples every subsequent bit at its center (§5.1). It
// checks only the first stop bit (§4.5). cfg_divisor == 0 disables reception.
//
// Line errors (§4.7): parity (PE), framing (FE: first stop not mark), break (BI:
// full-frame space), overrun (OE: a completed character is dropped because the
// FIFO has not accepted the previous one -- the only LOSSY UART behaviour).
// ----------------------------------------------------------------------------
module uart_rx_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int OVERSAMPLE = 16,
        parameter int RSP_WIDTH  = MAX_DATA_BITS + 4,
        parameter int BPW        = DIV_WIDTH + $clog2(OVERSAMPLE) + 1
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // UART serial input (protocol) line
        input  wire                     rxd,

        // Held runtime framing configuration
        input  wire [DIV_WIDTH-1:0]     cfg_divisor,
        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,
        input  wire [1:0]               cfg_stop_bits,

        // RV response channel (core drives, FIFO accepts) -- deframed char + status
        output wire [RSP_WIDTH-1:0]     rsp_dat,
        output wire                     rsp_valid,
        input  wire                     rsp_ready
    );

    typedef `UART_RX_RSP_S(MAX_DATA_BITS) rsp_s;

    // Sample timing: half a bit to the start-bit center, then a full bit between
    // subsequent bit centers.
    wire [BPW-1:0] full_period = cfg_divisor * OVERSAMPLE;
    wire [BPW-1:0] half_period = cfg_divisor * (OVERSAMPLE/2);

    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        START  = 3'd1,
        DATA   = 3'd2,
        PARITY = 3'd3,
        STOP   = 3'd4
    } state_e;

    state_e                state;
    reg [BPW-1:0]          scnt;         // clocks down to the next sample point
    reg [MAX_DATA_BITS-1:0] rxbuf;       // accumulated data bits (LSB-first)
    reg [3:0]              bit_idx;       // next data bit to sample
    reg                    rx_parity;     // sampled parity bit

    // Output (single-entry) register + sticky overrun.
    reg                    rsp_valid_r;
    rsp_s                  rsp_q;
    reg                    overrun_q;     // a char was dropped; flagged on next deliver

    assign rsp_dat   = rsp_q;
    assign rsp_valid = rsp_valid_r;

    wire rsp_fire    = rsp_valid_r && rsp_ready;
    wire sample_tick = (state != IDLE) && (scnt == {BPW{1'b0}});

    // Parity over the significant data bits (same definition as the transmitter).
    function automatic logic calc_parity(input logic [MAX_DATA_BITS-1:0] d,
                                         input logic [3:0] wbits,
                                         input logic even, input logic stick);
        logic [MAX_DATA_BITS-1:0] mask;
        logic                     p;
        mask = (wbits >= MAX_DATA_BITS) ? {MAX_DATA_BITS{1'b1}}
                                        : ((1 << wbits) - 1);
        p = ^(d & mask);
        if (!even) p = ~p;
        if (stick) p = ~even;
        return p;
    endfunction

    // Frame-completion datapath (combinational), evaluated when STOP is sampled.
    logic [MAX_DATA_BITS-1:0] data_masked;
    logic                     exp_parity;
    logic                     stop_ok;
    logic                     is_break;
    logic                     fe, pe;
    always_comb begin
        logic [MAX_DATA_BITS-1:0] mask;
        mask        = (cfg_word_bits >= MAX_DATA_BITS) ? {MAX_DATA_BITS{1'b1}}
                                                       : ((1 << cfg_word_bits) - 1);
        data_masked = rxbuf & mask;
        exp_parity  = calc_parity(rxbuf, cfg_word_bits,
                                  cfg_parity_even, cfg_parity_stick);
        stop_ok     = (rxd == 1'b1);                         // first stop = mark?
        // break: the entire frame was space -- start + all data + parity + stop = 0
        is_break    = (rxd == 1'b0) && (data_masked == 0) &&
                      (!cfg_parity_en || (rx_parity == 1'b0));
        fe          = (!stop_ok) && !is_break;               // framing error
        pe          = cfg_parity_en && (rx_parity != exp_parity) && !is_break;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            scnt        <= '0;
            rxbuf       <= '0;
            bit_idx     <= '0;
            rx_parity   <= 1'b0;
            rsp_valid_r <= 1'b0;
            rsp_q       <= '0;
            overrun_q   <= 1'b0;
        end else begin
            // up-link consume
            if (rsp_fire)
                rsp_valid_r <= 1'b0;

            // sample-point countdown
            if (state != IDLE && scnt != 0)
                scnt <= scnt - 1'b1;

            case (state)
                IDLE: begin
                    // detect the start edge (line goes to space)
                    if ((rxd == 1'b0) && (cfg_divisor != 0)) begin
                        state <= START;
                        scnt  <= (half_period == 0) ? '0 : (half_period - 1'b1);
                    end
                end
                START: begin
                    if (sample_tick) begin
                        if (rxd == 1'b1) begin
                            state <= IDLE;          // false start (glitch)
                        end else begin
                            rxbuf   <= '0;
                            bit_idx <= 4'd0;
                            state   <= DATA;
                            scnt    <= (full_period == 0) ? '0 : (full_period - 1'b1);
                        end
                    end
                end
                DATA: begin
                    if (sample_tick) begin
                        rxbuf[bit_idx] <= rxd;
                        if ((bit_idx + 1) < cfg_word_bits) begin
                            bit_idx <= bit_idx + 1'b1;
                            scnt    <= (full_period == 0) ? '0 : (full_period - 1'b1);
                        end else if (cfg_parity_en) begin
                            state <= PARITY;
                            scnt  <= (full_period == 0) ? '0 : (full_period - 1'b1);
                        end else begin
                            state <= STOP;
                            scnt  <= (full_period == 0) ? '0 : (full_period - 1'b1);
                        end
                    end
                end
                PARITY: begin
                    if (sample_tick) begin
                        rx_parity <= rxd;
                        state     <= STOP;
                        scnt      <= (full_period == 0) ? '0 : (full_period - 1'b1);
                    end
                end
                STOP: begin
                    if (sample_tick) begin
                        // Frame complete: assemble the result and try to deliver it.
                        // If the up-link still holds an unconsumed character, drop
                        // this one and remember the overrun for the next delivery.
                        if (!rsp_valid_r || rsp_fire) begin
                            rsp_q.data        <= is_break ? '0 : data_masked;
                            rsp_q.parity_err  <= pe;
                            rsp_q.framing_err <= fe;
                            rsp_q.brk         <= is_break;
                            rsp_q.overrun     <= overrun_q;
                            rsp_valid_r       <= 1'b1;
                            overrun_q         <= 1'b0;
                        end else begin
                            overrun_q         <= 1'b1;   // character lost
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
