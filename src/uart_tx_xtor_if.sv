// ----------------------------------------------------------------------------
// UART transmit transactor interface (SV; not synthesizable)
//
// Bridges the blocking task API to the core:
//   - an ingress FIFO from send() to the core's req link
//   - the held configuration (cfg_*), the break level (brk), and the
//     divisor for the wrapper's baud tick core
//   - error injection (K6, VIP-only): send_err() and glitch() drive the
//     line themselves, clock by clock, through ovr_en/ovr_val, which the
//     uart_tx_xtor wrapper muxes over the core's txd. The core never sees
//     these frames
//
// `hold` keeps queued characters on the FIFO while send_break(), send_err()
// or glitch() owns the line. Every level driven to the core goes through a
// clocked copy: a continuous assign from a variable written through a
// virtual interface does not reliably re-trigger in Verilator. The copy
// delays all of them by one clock alike.
// ----------------------------------------------------------------------------
interface uart_tx_xtor_if #(
        parameter int MAX_DATA_BITS = 8,
        parameter int DIV_WIDTH     = 16,
        parameter int REQ_WIDTH     = MAX_DATA_BITS,
        parameter int DEPTH         = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,
        // The wrapper's OVERSAMPLE, as a port rather than a parameter so
        // the bridge's `virtual uart_tx_xtor_if` matches every instance.
        input  wire [7:0]               oversample,

        output wire [REQ_WIDTH-1:0]     req_dat,
        output wire                     req_valid,
        input  wire                     req_ready,
        input  wire                     busy,

        output logic [DIV_WIDTH-1:0]    cfg_divisor,
        output logic [3:0]              cfg_word_bits,
        output logic                    cfg_parity_en,
        output logic                    cfg_parity_even,
        output logic                    cfg_parity_stick,
        output logic [1:0]              cfg_stop_bits,
        output logic                    brk,

        output logic                    ovr_en,
        output logic                    ovr_val
    );

    // --------------------------------------------------------------------
    // Held levels. Reset defaults: 8N1, divisor 16, no break, no override.
    // --------------------------------------------------------------------
    logic [DIV_WIDTH-1:0] cfg_divisor_r      = DIV_WIDTH'(16);
    logic [3:0]           cfg_word_bits_r    = 4'd8;
    logic                 cfg_parity_en_r    = 1'b0;
    logic                 cfg_parity_even_r  = 1'b0;
    logic                 cfg_parity_stick_r = 1'b0;
    logic [1:0]           cfg_stop_bits_r    = 2'd0;
    logic                 brk_r              = 1'b0;
    logic                 hold_r             = 1'b0;
    logic                 ovr_en_r           = 1'b0;
    logic                 ovr_val_r          = 1'b1;
    logic                 hold               = 1'b0;

    initial begin
        cfg_divisor      = DIV_WIDTH'(16);
        cfg_word_bits    = 4'd8;
        cfg_parity_en    = 1'b0;
        cfg_parity_even  = 1'b0;
        cfg_parity_stick = 1'b0;
        cfg_stop_bits    = 2'd0;
        brk              = 1'b0;
        ovr_en           = 1'b0;
        ovr_val          = 1'b1;
    end

    always @(posedge clock) begin
        cfg_divisor      <= cfg_divisor_r;
        cfg_word_bits    <= cfg_word_bits_r;
        cfg_parity_en    <= cfg_parity_en_r;
        cfg_parity_even  <= cfg_parity_even_r;
        cfg_parity_stick <= cfg_parity_stick_r;
        cfg_stop_bits    <= cfg_stop_bits_r;
        brk              <= brk_r;
        hold             <= hold_r;
        ovr_en           <= ovr_en_r;
        ovr_val          <= ovr_val_r;
    end

    // --------------------------------------------------------------------
    // Ingress FIFO: characters into the core
    // --------------------------------------------------------------------
    localparam int REQ_PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    logic [REQ_WIDTH-1:0] req_mem [0:DEPTH-1];
    logic [REQ_PTR_W-1:0] req_wr, req_rd;
    int unsigned          req_cnt;
    logic                 req_put_req = 1'b0;
    logic                 req_put_gnt;
    logic [REQ_WIDTH-1:0] req_put_dat = '0;

    assign req_valid = (req_cnt != 0) && !hold;
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
            if (do_pop)
                req_rd <= (req_rd == REQ_PTR_W'(DEPTH-1)) ? '0 : req_rd + 1'b1;
            case ({do_push, do_pop})
                2'b10:   req_cnt <= req_cnt + 1;
                2'b01:   req_cnt <= req_cnt - 1;
                default: req_cnt <= req_cnt;
            endcase
        end
    end

    // --------------------------------------------------------------------
    // Timing helpers
    // --------------------------------------------------------------------

    // Clocks in one bit at the current divisor.
    function automatic int unsigned bit_clocks();
        return int'(oversample) * int'(cfg_divisor_r);
    endfunction

    // Stop length in half bits.
    function automatic int unsigned stop_halves();
        if (cfg_stop_bits_r == 2'd0) return 2;
        return (cfg_word_bits_r == 4'd5) ? 3 : 4;
    endfunction

    // Clocks in one character at the current framing.
    function automatic int unsigned char_clocks();
        int unsigned halves;
        halves = 2 * (1 + int'(cfg_word_bits_r) + int'(cfg_parity_en_r)) + stop_halves();
        return (halves * bit_clocks()) / 2;
    endfunction

    // Wait until everything queued has gone out, then hold the FIFO so the
    // caller owns the idle line.
    task automatic take_line();
        do @(posedge clock); while (req_cnt != 0 || busy);
        hold_r = 1'b1;
        // hold reaches the FIFO one clock later; a character a concurrent
        // send() got in before that must finish first.
        repeat (2) @(posedge clock);
        while (busy) @(posedge clock);
    endtask

    task automatic give_line();
        hold_r = 1'b0;
    endtask

    // --------------------------------------------------------------------
    // Task API
    // --------------------------------------------------------------------

    task automatic configure(
            input bit [15:0] divisor,
            input bit [3:0]  word_bits,
            input bit        parity_en,
            input bit        parity_even,
            input bit        parity_stick,
            input bit [1:0]  stop_bits);
        cfg_divisor_r      = DIV_WIDTH'(divisor);
        cfg_word_bits_r    = word_bits;
        cfg_parity_en_r    = parity_en;
        cfg_parity_even_r  = parity_even;
        cfg_parity_stick_r = parity_stick;
        cfg_stop_bits_r    = stop_bits;
    endtask

    // Blocking push of a raw request.
    task automatic put(input [REQ_WIDTH-1:0] val);
        req_put_dat = val;
        req_put_req = 1'b1;
        do @(posedge clock); while (!req_put_gnt);
        req_put_req = 1'b0;
    endtask

    task automatic send(input bit [MAX_DATA_BITS-1:0] data);
        put(data);
    endtask

    task automatic set_break(input bit on);
        brk_r = on;
    endtask

    task automatic send_break(input int unsigned n_chars);
        take_line();
        brk_r = 1'b1;
        repeat (n_chars * char_clocks()) @(posedge clock);
        brk_r = 1'b0;
        // The core holds mark for a bit after the break by itself.
        repeat (2) @(posedge clock);
        give_line();
    endtask

    task automatic send_err(
            input bit [7:0]    data,
            input bit          bad_parity,
            input bit          bad_stop,
            input int          baud_ppm,
            input int unsigned glitch_at,
            input int unsigned glitch_len);
        bit          halves[$];
        bit          p;
        int unsigned nbits, total;
        real         half_len;

        // The frame, one entry per half bit.
        nbits = int'(cfg_word_bits_r);
        p = ^(data & 8'((1 << nbits) - 1));
        if (!cfg_parity_even_r)  p = ~p;
        if (cfg_parity_stick_r)  p = ~cfg_parity_even_r;
        if (bad_parity)          p = ~p;
        repeat (2) halves.push_back(1'b0);
        for (int i = 0; i < nbits; i++)
            repeat (2) halves.push_back(data[i]);
        if (cfg_parity_en_r)
            repeat (2) halves.push_back(p);
        repeat (2) halves.push_back(!bad_stop);
        repeat (stop_halves() - 2) halves.push_back(1'b1);

        half_len = real'(bit_clocks()) * (1.0 + real'(baud_ppm) / 1.0e6) / 2.0;
        total    = int'(real'(halves.size()) * half_len);

        take_line();
        ovr_en_r = 1'b1;
        for (int unsigned c = 0; c < total; c++) begin
            int unsigned h;
            bit          v;
            h = int'($floor(real'(c) / half_len));
            if (h >= halves.size()) h = halves.size() - 1;
            v = halves[h];
            if (glitch_len != 0 && c >= glitch_at && c < glitch_at + glitch_len)
                v = ~v;
            ovr_val_r = v;
            @(posedge clock);
        end
        // A bit of mark before anything else goes out: a receiver that
        // resynchronized on a bad stop bit (as a 16550 does) has to see an
        // idle line, not the next start bit.
        ovr_val_r = 1'b1;
        repeat (bit_clocks()) @(posedge clock);
        ovr_en_r  = 1'b0;
        repeat (2) @(posedge clock);
        give_line();
    endtask

    task automatic glitch(input int unsigned glitch_len);
        take_line();
        ovr_en_r  = 1'b1;
        ovr_val_r = 1'b0;
        repeat (glitch_len) @(posedge clock);
        ovr_val_r = 1'b1;
        ovr_en_r  = 1'b0;
        repeat (bit_clocks() + 2) @(posedge clock);
        give_line();
    endtask

endinterface
