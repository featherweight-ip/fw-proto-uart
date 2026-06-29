`include "uart_xtor_macros.svh"

// ----------------------------------------------------------------------------
// UART Receive transactor interface (SV, signal-level RV port + held config)
//
// A hand-coded in-built egress FIFO bridges the core's deframed-character stream to
// the blocking task API (HVL side):
//   - egress FIFO : recv()/get_rsp() pop <- captures (rsp_dat, rsp_valid)
//
// Runtime framing configuration is a held LEVEL: configure() latches the cfg_*
// registers driven continuously to the core (sampled at start-bit detect).
// ----------------------------------------------------------------------------
interface uart_rx_xtor_if #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int RSP_WIDTH = MAX_DATA_BITS + 4,
        parameter int DEPTH     = 8
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV response channel: core sources deframed chars, interface accepts
        input  wire [RSP_WIDTH-1:0]     rsp_dat,
        input  wire                     rsp_valid,
        output wire                     rsp_ready,

        // Held runtime framing configuration, driven to the core (registered copy
        // of the cfg_*_r held values -- see the clocked block below).
        output logic [DIV_WIDTH-1:0]    cfg_divisor,
        output logic [3:0]              cfg_word_bits,
        output logic                    cfg_parity_en,
        output logic                    cfg_parity_even,
        output logic                    cfg_parity_stick,
        output logic [1:0]              cfg_stop_bits
    );

    typedef `UART_RX_RSP_S(MAX_DATA_BITS) rsp_s;

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
    // Egress FIFO : deframed-character stream captured from the core
    // --------------------------------------------------------------------
    localparam int RSP_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [RSP_WIDTH-1:0] rsp_mem [0:DEPTH-1];
    logic [RSP_PTR_W-1:0] rsp_wr, rsp_rd;
    int unsigned          rsp_cnt;
    logic                 rsp_get_req, rsp_get_gnt;
    logic [RSP_WIDTH-1:0] rsp_get_dat;

    assign rsp_ready = (rsp_cnt < DEPTH);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            rsp_wr      <= '0;
            rsp_rd      <= '0;
            rsp_cnt     <= 0;
            rsp_get_gnt <= 1'b0;
            rsp_get_dat <= '0;
        end else begin
            automatic logic do_push = (rsp_valid && rsp_ready);
            automatic logic do_pop  = (rsp_get_req && !rsp_get_gnt && (rsp_cnt != 0));
            rsp_get_gnt <= 1'b0;
            if (do_push) begin
                rsp_mem[rsp_wr] <= rsp_dat;
                rsp_wr <= (rsp_wr == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_wr + 1'b1;
            end
            if (do_pop) begin
                rsp_get_dat <= rsp_mem[rsp_rd];
                rsp_rd      <= (rsp_rd == RSP_PTR_W'(DEPTH-1)) ? '0 : rsp_rd + 1'b1;
                rsp_get_gnt <= 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   rsp_cnt <= rsp_cnt + 1;
                2'b01:   rsp_cnt <= rsp_cnt - 1;
                default: rsp_cnt <= rsp_cnt;
            endcase
        end
    end

    initial begin
        rsp_get_req = 1'b0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------
    task wait_reset();
        if (reset) @(negedge reset);
        @(posedge clock);
    endtask

    // Set the held framing configuration.
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

    // Blocking pop of a raw response vector.
    task automatic get_rsp(output [RSP_WIDTH-1:0] val);
        rsp_get_req = 1'b1;
        do @(posedge clock); while (!rsp_get_gnt);
        val = rsp_get_dat;
        rsp_get_req = 1'b0;
    endtask

    // Block for the next deframed character; return its data + status nibble
    // {overrun, brk, framing_err, parity_err}.
    task automatic recv(output [MAX_DATA_BITS-1:0] data, output [3:0] status);
        rsp_s r;
        get_rsp(r);
        data   = r.data;
        status = {r.overrun, r.brk, r.framing_err, r.parity_err};
    endtask

endinterface
