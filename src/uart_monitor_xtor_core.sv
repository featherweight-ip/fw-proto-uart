`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART Monitor core transactor (pure module, signal-level ports)
//
// Passively observes ONE serial line (a tap on STX or SRX) and deframes it exactly
// as the receiver does -- start-bit detect, oversampled center sampling, parity /
// framing / break detection -- emitting one observed character + status per frame.
// It drives nothing onto the line. The is_tx tag (which line was tapped) is added
// by the monitor bridge, not by this core.
//
//   - line  : the tapped serial line (idle = mark = 1)
//   - cfg_* : held runtime framing configuration (must match the tapped link)
//   - mon_* : RV initiator port (core -> FIFO)  { data, status }
//
// The monitor cannot backpressure the line; if its single-entry buffer is still
// full when a new character completes, that character is dropped and the overrun
// status bit is set on the next delivered character (size the downstream FIFO
// generously -- design O-9).
// ----------------------------------------------------------------------------
module uart_monitor_xtor_core #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int OVERSAMPLE = 16,
        parameter int MON_WIDTH  = MAX_DATA_BITS + 4,
        parameter int BPW        = DIV_WIDTH + $clog2(OVERSAMPLE) + 1
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // UART serial line -- passively observed
        input  wire                     line,

        // Held runtime framing configuration
        input  wire [DIV_WIDTH-1:0]     cfg_divisor,
        input  wire [3:0]               cfg_word_bits,
        input  wire                     cfg_parity_en,
        input  wire                     cfg_parity_even,
        input  wire                     cfg_parity_stick,
        input  wire [1:0]               cfg_stop_bits,

        // RV egress channel of observed characters (core drives)
        output wire [MON_WIDTH-1:0]     mon_dat,
        output wire                     mon_valid,
        input  wire                     mon_ready
    );

    typedef `UART_RX_RSP_S(MAX_DATA_BITS) mon_s;

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
    reg [BPW-1:0]          scnt;
    reg [MAX_DATA_BITS-1:0] rxbuf;
    reg [3:0]              bit_idx;
    reg                    rx_parity;

    reg                    mon_valid_r;
    mon_s                  mon_q;
    reg                    overrun_q;

    assign mon_dat   = mon_q;
    assign mon_valid = mon_valid_r;

    wire mon_fire    = mon_valid_r && mon_ready;
    wire sample_tick = (state != IDLE) && (scnt == {BPW{1'b0}});

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

    logic [MAX_DATA_BITS-1:0] data_masked;
    logic                     exp_parity, stop_ok, is_break, fe, pe;
    always_comb begin
        logic [MAX_DATA_BITS-1:0] mask;
        mask        = (cfg_word_bits >= MAX_DATA_BITS) ? {MAX_DATA_BITS{1'b1}}
                                                       : ((1 << cfg_word_bits) - 1);
        data_masked = rxbuf & mask;
        exp_parity  = calc_parity(rxbuf, cfg_word_bits,
                                  cfg_parity_even, cfg_parity_stick);
        stop_ok     = (line == 1'b1);
        is_break    = (line == 1'b0) && (data_masked == 0) &&
                      (!cfg_parity_en || (rx_parity == 1'b0));
        fe          = (!stop_ok) && !is_break;
        pe          = cfg_parity_en && (rx_parity != exp_parity) && !is_break;
    end

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            scnt        <= '0;
            rxbuf       <= '0;
            bit_idx     <= '0;
            rx_parity   <= 1'b0;
            mon_valid_r <= 1'b0;
            mon_q       <= '0;
            overrun_q   <= 1'b0;
        end else begin
            if (mon_fire)
                mon_valid_r <= 1'b0;

            if (state != IDLE && scnt != 0)
                scnt <= scnt - 1'b1;

            case (state)
                IDLE: begin
                    if ((line == 1'b0) && (cfg_divisor != 0)) begin
                        state <= START;
                        scnt  <= (half_period == 0) ? '0 : (half_period - 1'b1);
                    end
                end
                START: begin
                    if (sample_tick) begin
                        if (line == 1'b1) begin
                            state <= IDLE;
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
                        rxbuf[bit_idx] <= line;
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
                        rx_parity <= line;
                        state     <= STOP;
                        scnt      <= (full_period == 0) ? '0 : (full_period - 1'b1);
                    end
                end
                STOP: begin
                    if (sample_tick) begin
                        if (!mon_valid_r || mon_fire) begin
                            mon_q.data        <= is_break ? '0 : data_masked;
                            mon_q.parity_err  <= pe;
                            mon_q.framing_err <= fe;
                            mon_q.brk         <= is_break;
                            mon_q.overrun     <= overrun_q;
                            mon_valid_r       <= 1'b1;
                            overrun_q         <= 1'b0;
                        end else begin
                            overrun_q         <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
