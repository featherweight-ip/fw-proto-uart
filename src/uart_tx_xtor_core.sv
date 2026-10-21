`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART transmit core (pure module, signal-level ports)
//
// Serializes each character accepted on the req link into a frame: a start
// bit (space), cfg_word_bits data bits LSB first, an optional parity bit,
// and the stop bits (mark).
//
//   req_*  : ready/valid target (link -> core), { data }
//   txd    : the serial output (idle = mark = 1)
//   tick   : the oversampling enable from uart_baud_xtor_core (K2). A bit is
//            OVERSAMPLE ticks; every bit edge is on a tick, so each bit is
//            exactly OVERSAMPLE * divisor clocks
//   brk    : break (K4, 16550 LCR.BC), a level. While it is 1, txd is 0 at
//            once and no new character is accepted. A character already
//            started carries on underneath and is lost, as in a 16550;
//            characters behind it wait on the link (OI-10). After brk
//            falls the line holds mark for one bit before the next start
//            bit, so a receiver sees the break end. Raise it with busy = 0
//            for a clean break
//   busy   : a character is in the core (16550 LSR.TEMT = !busy and the
//            FIFO empty). req_ready and busy are both 1 only on the tick
//            that ends a stop bit
//   cfg_*  : framing, sampled when a character is accepted, so a change
//            applies from the next character (K1)
//
// Stop bits: cfg_stop_bits == 0 gives 1; otherwise 2, or 1.5 for a 5-bit
// character.
// ----------------------------------------------------------------------------
module uart_tx_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int OVERSAMPLE    = 16,
        parameter int REQ_WIDTH     = MAX_DATA_BITS
    ) (
        input  wire                     clock,
        input  wire                     reset,
        input  wire                     tick,

        output wire                     txd,
        input  wire                     brk,
        output wire                     busy,

        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,
        input  wire [1:0]               cfg_stop_bits,

        input  wire [REQ_WIDTH-1:0]     req_dat,
        input  wire                     req_valid,
        output wire                     req_ready
    );

    typedef `UART_TX_REQ_S(MAX_DATA_BITS) req_s;

    // Ticks left in the current bit; the longest is two stop bits.
    localparam int TW = $clog2(2*OVERSAMPLE);
    localparam [TW-1:0] BIT_TICKS  = TW'(OVERSAMPLE - 1);
    localparam [TW-1:0] BRK_MARK   = TW'(OVERSAMPLE);      // see IDLE
    localparam [TW-1:0] STOP1      = TW'(OVERSAMPLE - 1);
    localparam [TW-1:0] STOP15     = TW'(OVERSAMPLE + OVERSAMPLE/2 - 1);
    localparam [TW-1:0] STOP2      = TW'(2*OVERSAMPLE - 1);

    typedef enum logic [2:0] {
        IDLE   = 3'd0,
        LOAD   = 3'd1,      // accepted; the start bit begins at the next tick
        START  = 3'd2,
        DATA   = 3'd3,
        PARITY = 3'd4,
        STOP   = 3'd5
    } state_e;

    req_s                   req_u;
    state_e                 state;
    reg [MAX_DATA_BITS-1:0] shift;       // data bits still to send, LSB next
    reg [3:0]               bits_left;   // data bits after the one on the line
    reg [TW-1:0]            tcnt;
    reg                     txd_r;
    reg                     parity_bit;
    reg                     parity_en_q;
    reg [TW-1:0]            stop_len_q;  // stop length in ticks, minus 1

    always_comb req_u = req_s'(req_dat);

    assign txd       = txd_r && !brk;
    assign busy      = (state != IDLE);
    wire bit_end  = tick && (tcnt == '0);

    // A character is accepted when idle, or on the tick that ends the stop
    // bit, so back-to-back frames have no gap. In IDLE, tcnt is the mark
    // still owed after a break.
    assign req_ready = !brk && (((state == IDLE) && (tcnt == '0)) ||
                                ((state == STOP) && bit_end));

    wire req_fire = req_valid && req_ready;

    // odd (parity_even=0): an odd number of 1s in data+parity; even: even;
    // stick: the parity bit is fixed at !parity_even.
    function automatic logic calc_parity(input logic [MAX_DATA_BITS-1:0] d,
                                         input logic [3:0] wbits,
                                         input logic even, input logic stick);
        logic [MAX_DATA_BITS-1:0] mask;
        logic                     p;
        mask = (wbits >= 4'(MAX_DATA_BITS)) ? {MAX_DATA_BITS{1'b1}}
                                            : MAX_DATA_BITS'((1 << wbits) - 1);
        p = ^(d & mask);
        if (!even) p = ~p;
        if (stick) p = ~even;
        return p;
    endfunction

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            shift       <= '0;
            bits_left   <= '0;
            tcnt        <= '0;
            txd_r       <= 1'b1;
            parity_bit  <= 1'b0;
            parity_en_q <= 1'b0;
            stop_len_q  <= STOP1;
        end else begin
            if (tick && tcnt != '0)
                tcnt <= tcnt - 1'b1;

            case (state)
                IDLE: begin
                    // Mark from brk falling to the next start bit: the
                    // start goes out on the tick after tcnt reaches 0,
                    // BRK_MARK ticks on, which is at least a bit.
                    if (brk)
                        tcnt <= BRK_MARK;
                end
                LOAD: begin
                    if (tick) begin
                        txd_r <= 1'b0;
                        tcnt  <= BIT_TICKS;
                        state <= START;
                    end
                end
                START: begin
                    if (bit_end) begin
                        txd_r <= shift[0];
                        shift <= shift >> 1;
                        tcnt  <= BIT_TICKS;
                        state <= DATA;
                    end
                end
                DATA: begin
                    if (bit_end) begin
                        if (bits_left != 4'd0) begin
                            bits_left <= bits_left - 4'd1;
                            txd_r     <= shift[0];
                            shift     <= shift >> 1;
                            tcnt      <= BIT_TICKS;
                        end else if (parity_en_q) begin
                            txd_r <= parity_bit;
                            tcnt  <= BIT_TICKS;
                            state <= PARITY;
                        end else begin
                            txd_r <= 1'b1;
                            tcnt  <= stop_len_q;
                            state <= STOP;
                        end
                    end
                end
                PARITY: begin
                    if (bit_end) begin
                        txd_r <= 1'b1;
                        tcnt  <= stop_len_q;
                        state <= STOP;
                    end
                end
                STOP: begin
                    if (bit_end)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase

            // Accept: the start bit begins on this tick, or the next one.
            if (req_fire) begin
                shift       <= req_u.data;
                bits_left   <= cfg_word_bits - 4'd1;
                parity_bit  <= calc_parity(req_u.data, cfg_word_bits,
                                           cfg_parity_even, cfg_parity_stick);
                parity_en_q <= cfg_parity_en;
                stop_len_q  <= (cfg_stop_bits == 2'd0) ? STOP1 :
                               (cfg_word_bits == 4'd5) ? STOP15 : STOP2;
                if (tick) begin
                    txd_r <= 1'b0;
                    tcnt  <= BIT_TICKS;
                    state <= START;
                end else begin
                    state <= LOAD;
                end
            end
        end
    end

endmodule
