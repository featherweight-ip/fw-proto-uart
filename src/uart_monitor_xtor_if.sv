`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART Monitor transactor interface (SV, signal-level RV port + held config)
//
// A hand-coded in-built egress FIFO bridges the core's observed-character stream to
// the blocking task API (HVL side):
//   - egress FIFO : wait_char()/get_char() pop <- captures (mon_dat, mon_valid)
//
// The monitor must be configured to match the framing of the tapped link; configure()
// latches the cfg_* registers driven to the core. The capture FIFO is deeper than the
// data-path FIFOs because the monitor cannot backpressure the line (design O-9).
// ----------------------------------------------------------------------------
interface uart_monitor_xtor_if #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int MON_WIDTH = MAX_DATA_BITS + 4,
        parameter int DEPTH     = 16
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV egress channel: core sources observed chars, interface accepts
        input  wire [MON_WIDTH-1:0]     mon_dat,
        input  wire                     mon_valid,
        output wire                     mon_ready,

        // Held runtime framing configuration, driven to the core (registered copy
        // of the cfg_*_r held values -- see the clocked block below).
        output logic [DIV_WIDTH-1:0]    cfg_divisor,
        output logic [3:0]              cfg_word_bits,
        output logic                    cfg_parity_en,
        output logic                    cfg_parity_even,
        output logic                    cfg_parity_stick,
        output logic [1:0]              cfg_stop_bits
    );

    typedef `UART_RX_RSP_S(MAX_DATA_BITS) mon_s;

    // --------------------------------------------------------------------
    // Held configuration registers (reset defaults: 8N1, divisor 16).
    // --------------------------------------------------------------------
    logic [DIV_WIDTH-1:0] cfg_divisor_r;
    logic [3:0]           cfg_word_bits_r;
    logic                 cfg_parity_en_r;
    logic                 cfg_parity_even_r;
    logic                 cfg_parity_stick_r;
    logic [1:0]           cfg_stop_bits_r;

    initial begin
        cfg_divisor_r      = DIV_WIDTH'(16);
        cfg_word_bits_r    = 4'd8;
        cfg_parity_en_r    = 1'b0;
        cfg_parity_even_r  = 1'b0;
        cfg_parity_stick_r = 1'b0;
        cfg_stop_bits_r    = 2'd0;
        cfg_divisor        = DIV_WIDTH'(16);
        cfg_word_bits      = 4'd8;
        cfg_parity_en      = 1'b0;
        cfg_parity_even    = 1'b0;
        cfg_parity_stick   = 1'b0;
        cfg_stop_bits      = 2'd0;
    end

    // Drive the held configuration onto the core ports through a clocked copy (a
    // continuous assign from a virtual-interface-written variable does not reliably
    // re-trigger in Verilator). One-cycle latency, harmless.
    always @(posedge clock) begin
        cfg_divisor      <= cfg_divisor_r;
        cfg_word_bits    <= cfg_word_bits_r;
        cfg_parity_en    <= cfg_parity_en_r;
        cfg_parity_even  <= cfg_parity_even_r;
        cfg_parity_stick <= cfg_parity_stick_r;
        cfg_stop_bits    <= cfg_stop_bits_r;
    end

    // --------------------------------------------------------------------
    // Egress FIFO : observed-character stream captured from the core
    // --------------------------------------------------------------------
    localparam int MON_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [MON_WIDTH-1:0] mon_mem [0:DEPTH-1];
    logic [MON_PTR_W-1:0] mon_wr, mon_rd;
    int unsigned          mon_cnt;
    logic                 mon_get_req, mon_get_gnt;
    logic [MON_WIDTH-1:0] mon_get_dat;

    assign mon_ready = (mon_cnt < DEPTH);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            mon_wr      <= '0;
            mon_rd      <= '0;
            mon_cnt     <= 0;
            mon_get_gnt <= 1'b0;
            mon_get_dat <= '0;
        end else begin
            automatic logic do_push = (mon_valid && mon_ready);
            automatic logic do_pop  = (mon_get_req && !mon_get_gnt && (mon_cnt != 0));
            mon_get_gnt <= 1'b0;
            if (do_push) begin
                mon_mem[mon_wr] <= mon_dat;
                mon_wr <= (mon_wr == MON_PTR_W'(DEPTH-1)) ? '0 : mon_wr + 1'b1;
            end
            if (do_pop) begin
                mon_get_dat <= mon_mem[mon_rd];
                mon_rd      <= (mon_rd == MON_PTR_W'(DEPTH-1)) ? '0 : mon_rd + 1'b1;
                mon_get_gnt <= 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   mon_cnt <= mon_cnt + 1;
                2'b01:   mon_cnt <= mon_cnt - 1;
                default: mon_cnt <= mon_cnt;
            endcase
        end
    end

    initial begin
        mon_get_req = 1'b0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------
    task wait_reset();
        if (reset) @(negedge reset);
        @(posedge clock);
    endtask

    task automatic configure(
            input [15:0] divisor,
            input [3:0]  word_bits,
            input        parity_en,
            input        parity_even,
            input        parity_stick,
            input [1:0]  stop_bits);
        cfg_divisor_r      = DIV_WIDTH'(divisor);
        cfg_word_bits_r    = word_bits;
        cfg_parity_en_r    = parity_en;
        cfg_parity_even_r  = parity_even;
        cfg_parity_stick_r = parity_stick;
        cfg_stop_bits_r    = stop_bits;
    endtask

    // Blocking pop of a raw observed-character vector.
    task automatic get_char(output [MON_WIDTH-1:0] val);
        mon_get_req = 1'b1;
        do @(posedge clock); while (!mon_get_gnt);
        val = mon_get_dat;
        mon_get_req = 1'b0;
    endtask

    // Wait for the next observed character; return data + status nibble.
    task automatic wait_char(output [MAX_DATA_BITS-1:0] data, output [3:0] status);
        mon_s r;
        get_char(r);
        data   = r.data;
        status = {r.overrun, r.brk, r.framing_err, r.parity_err};
    endtask

endinterface
