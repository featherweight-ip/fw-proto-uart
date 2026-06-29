`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART Transmit core transactor (pure module, signal-level ports)
//
// Bridges a ready/valid character stream (FIFO side) to the asynchronous UART
// serial line (protocol side): it SERIALIZES each accepted character into a frame
// -- start bit (space), cfg_word_bits data bits LSB-first, an optional parity bit,
// then cfg_stop_bits worth of stop bits (mark) -- driving one bit per bit-period.
//
//   - req_* : RV target port (FIFO -> core)  { data }   the character to send
//   - txd   : the serial output line (idle = mark = 1)
//   - cfg_* : held runtime framing configuration (sampled at frame start)
//
// Bit timing: one bit-period = OVERSAMPLE * cfg_divisor system clocks (§4.9). The
// transmitter does not oversample (only the receiver does); it counts whole
// bit-periods. cfg_divisor == 0 disables transmission (the line idles at mark).
// ----------------------------------------------------------------------------
module uart_tx_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int OVERSAMPLE = 16,
        parameter int REQ_WIDTH  = MAX_DATA_BITS,
        // bit-period counter width: max bit-period = (2^DIV_WIDTH-1)*OVERSAMPLE
        parameter int BPW        = DIV_WIDTH + $clog2(OVERSAMPLE) + 1
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // UART serial output (protocol) line
        output wire                     txd,

        // Held runtime framing configuration
        input  wire [DIV_WIDTH-1:0]     cfg_divisor,
        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,
        input  wire [1:0]               cfg_stop_bits,

        // RV request channel (FIFO drives, core accepts) -- the character to send
        input  wire [REQ_WIDTH-1:0]     req_dat,
        input  wire                     req_valid,
        output wire                     req_ready
    );

    typedef `UART_TX_REQ_S(MAX_DATA_BITS) req_s;

    req_s req_u;
    always_comb req_u = req_s'(req_dat);

    // ------------------------------------------------------------------------
    // Bit-period generator: one tick per transmitted bit. bit_period clocks =
    // OVERSAMPLE * cfg_divisor. Counts down from bit_period-1 to 0; bit_tick at 0.
    // ------------------------------------------------------------------------
    wire [BPW-1:0] bit_period = cfg_divisor * OVERSAMPLE;
    reg  [BPW-1:0] btime;
    // bit_tick depends on `running` (state), so it is declared below, after them
    // -- strict declare-before-use (never rely on Verilog implicit-net creation).

    // ------------------------------------------------------------------------
    // State / datapath
    // ------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        START  = 3'd1,
        DATA   = 3'd2,
        PARITY = 3'd3,
        STOP   = 3'd4
    } state_e;

    state_e                state;
    reg [MAX_DATA_BITS-1:0] shift;       // latched character (LSB-first source)
    reg [3:0]              bit_idx;      // index of the data bit on the line
    reg [1:0]              stop_idx;     // stop bits emitted so far
    reg                    txd_r;        // registered serial output (idle = mark)
    reg                    parity_bit;   // precomputed parity for the latched char

    assign txd       = txd_r;
    assign req_ready = (state == IDLE);
    wire   running   = (state != IDLE);
    wire   bit_tick  = running && (btime == {BPW{1'b0}});  // one tick per transmitted bit

    wire   req_fire  = req_valid && req_ready;

    // Number of stop bits to emit: 0 => 1 stop; otherwise 2 (1.5, which the spec
    // allows only for 5-bit chars, is emitted as 2 -- the receiver checks only the
    // first stop bit, so this is interoperable; see docs O-6).
    wire [1:0] n_stop = (cfg_stop_bits == 2'd0) ? 2'd1 : 2'd2;

    // Parity over the significant data bits (combinational, on the incoming char).
    // odd  (parity_even=0): make total #1s odd  -> ~^data
    // even (parity_even=1): make total #1s even ->  ^data
    // stick(parity_stick=1): forced -> ~parity_even (0 if even-select, 1 if odd).
    function automatic logic calc_parity(input logic [MAX_DATA_BITS-1:0] d,
                                         input logic [3:0] wbits,
                                         input logic even, input logic stick);
        logic [MAX_DATA_BITS-1:0] mask;
        logic                     p;
        mask = (wbits >= MAX_DATA_BITS) ? {MAX_DATA_BITS{1'b1}}
                                    : ((1 << wbits) - 1);
        p = ^(d & mask);                 // even parity of significant bits
        if (!even) p = ~p;               // odd parity
        if (stick) p = ~even;            // stick overrides
        return p;
    endfunction

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state      <= IDLE;
            shift      <= '0;
            bit_idx    <= '0;
            stop_idx   <= '0;
            txd_r      <= 1'b1;          // idle = mark
            parity_bit <= 1'b0;
            btime      <= '0;
        end else begin
            // bit-period countdown (only while transmitting)
            if (state == IDLE) begin
                btime <= (bit_period == 0) ? '0 : (bit_period - 1'b1);
            end else if (btime == 0) begin
                btime <= (bit_period == 0) ? '0 : (bit_period - 1'b1);
            end else begin
                btime <= btime - 1'b1;
            end

            case (state)
                IDLE: begin
                    txd_r <= 1'b1;       // hold mark
                    if (req_fire && (cfg_divisor != 0)) begin
                        shift      <= req_u.data;
                        parity_bit <= calc_parity(req_u.data, cfg_word_bits,
                                                  cfg_parity_even, cfg_parity_stick);
                        bit_idx    <= '0;
                        stop_idx   <= '0;
                        txd_r      <= 1'b0;   // drive the start bit (space)
                        state      <= START;
                        btime      <= (bit_period == 0) ? '0 : (bit_period - 1'b1);
                    end
                end
                START: begin
                    if (bit_tick) begin
                        // start bit done -> first data bit (LSB)
                        txd_r   <= shift[0];
                        bit_idx <= 4'd0;
                        state   <= DATA;
                    end
                end
                DATA: begin
                    if (bit_tick) begin
                        if ((bit_idx + 1) < cfg_word_bits) begin
                            bit_idx <= bit_idx + 1'b1;
                            txd_r   <= shift[bit_idx + 1];
                        end else if (cfg_parity_en) begin
                            txd_r <= parity_bit;
                            state <= PARITY;
                        end else begin
                            txd_r    <= 1'b1;   // stop = mark
                            stop_idx <= 2'd0;
                            state    <= STOP;
                        end
                    end
                end
                PARITY: begin
                    if (bit_tick) begin
                        txd_r    <= 1'b1;       // stop = mark
                        stop_idx <= 2'd0;
                        state    <= STOP;
                    end
                end
                STOP: begin
                    if (bit_tick) begin
                        if ((stop_idx + 1) < n_stop) begin
                            stop_idx <= stop_idx + 1'b1;
                            txd_r    <= 1'b1;   // additional stop bit
                        end else begin
                            txd_r <= 1'b1;      // back to idle (mark)
                            state <= IDLE;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
