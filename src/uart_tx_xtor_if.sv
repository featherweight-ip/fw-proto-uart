// ----------------------------------------------------------------------------
// UART Transmit transactor interface (SV, signal-level RV port + held config)
//
// A hand-coded in-built FIFO bridges the blocking task API (HVL side) to the
// ready/valid character channel of the core:
//   - ingress FIFO : send()/put() push -> drives (req_dat, req_valid)
//
// Runtime framing configuration is a held LEVEL (not a stream): configure() latches
// the cfg_* registers, which are driven continuously to the core and sampled when a
// frame starts. The interface presents only the maximum-width character carrier
// (MAX_DATA_BITS); the active word length is selected by cfg_word_bits (design O-4).
// ----------------------------------------------------------------------------
interface uart_tx_xtor_if #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH = 16,
        parameter int REQ_WIDTH = MAX_DATA_BITS,
        parameter int DEPTH     = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV request channel: interface sources, core accepts
        output wire [REQ_WIDTH-1:0]     req_dat,
        output wire                     req_valid,
        input  wire                     req_ready,

        // Held runtime framing configuration, driven to the core (registered copy
        // of the cfg_*_r held values -- see the clocked block below).
        output logic [DIV_WIDTH-1:0]    cfg_divisor,
        output logic [3:0]              cfg_word_bits,
        output logic                    cfg_parity_en,
        output logic                    cfg_parity_even,
        output logic                    cfg_parity_stick,
        output logic [1:0]              cfg_stop_bits
    );

    // --------------------------------------------------------------------
    // Held configuration registers (reset defaults: 8 data bits, no parity, 1 stop,
    // divisor 16 -- a sane nonzero so a frame can move before explicit setup).
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

    // Drive the held configuration onto the core ports through a clocked copy. A
    // continuous assign from a variable written via a VIRTUAL interface handle
    // (configure()) does not reliably re-trigger in Verilator; sampling the held
    // value every clock edge propagates it robustly (one-cycle latency, harmless --
    // configuration is set while idle, well before a frame starts).
    always @(posedge clock) begin
        cfg_divisor      <= cfg_divisor_r;
        cfg_word_bits    <= cfg_word_bits_r;
        cfg_parity_en    <= cfg_parity_en_r;
        cfg_parity_even  <= cfg_parity_even_r;
        cfg_parity_stick <= cfg_parity_stick_r;
        cfg_stop_bits    <= cfg_stop_bits_r;
    end

    // --------------------------------------------------------------------
    // Ingress FIFO : character stream into the core
    // --------------------------------------------------------------------
    localparam int REQ_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [REQ_WIDTH-1:0] req_mem [0:DEPTH-1];
    logic [REQ_PTR_W-1:0] req_wr, req_rd;
    int unsigned          req_cnt;
    logic                 req_put_req, req_put_gnt;
    logic [REQ_WIDTH-1:0] req_put_dat;

    assign req_valid = (req_cnt != 0);
    assign req_dat   = req_mem[req_rd];

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            req_wr      <= '0;
            req_rd      <= '0;
            req_cnt     <= 0;
            req_put_gnt <= 1'b0;
        end else begin
            automatic logic do_push = (req_put_req && !req_put_gnt && (req_cnt < DEPTH));
            automatic logic do_pop  = (req_valid && req_ready);
            req_put_gnt <= 1'b0;
            if (do_push) begin
                req_mem[req_wr] <= req_put_dat;
                req_wr      <= (req_wr == REQ_PTR_W'(DEPTH-1)) ? '0 : req_wr + 1'b1;
                req_put_gnt <= 1'b1;
            end
            if (do_pop) begin
                req_rd <= (req_rd == REQ_PTR_W'(DEPTH-1)) ? '0 : req_rd + 1'b1;
            end
            case ({do_push, do_pop})
                2'b10:   req_cnt <= req_cnt + 1;
                2'b01:   req_cnt <= req_cnt - 1;
                default: req_cnt <= req_cnt;
            endcase
        end
    end

    initial begin
        req_put_req = 1'b0;
        req_put_dat = '0;
    end

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------

    // Set the held framing configuration (takes effect on the next frame start).
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

    // Blocking push of a raw character vector.
    task automatic put(input [REQ_WIDTH-1:0] val);
        req_put_dat = val;
        req_put_req = 1'b1;
        do @(posedge clock); while (!req_put_gnt);
        req_put_req = 1'b0;
    endtask

    // Enqueue one character to transmit.
    task automatic send(input [MAX_DATA_BITS-1:0] data);
        put(data);
    endtask

endinterface
