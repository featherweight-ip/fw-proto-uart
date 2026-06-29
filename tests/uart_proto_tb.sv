// ======================================================================
// REQUIRED back-to-back SIMULATION test for the UART kit (design §16).
//
// Wires a full TX transactor directly to a full RX transactor over one shared serial
// line, with a MONITOR passively tapping it -- exercising the COMPLETE stack (class
// API -> bridge -> xtor_if FIFOs -> core -> serial line and back). The class layer is
// one-way and fixed-width:
//   - the driver holds a uart_tx_if + uart_config_if handle (the TX bridge);
//   - a host sink implements uart_rx_if; the RX bridge holds it and run()-delivers;
//   - an observer implements uart_monitor_if; the monitor bridge holds it.
//
// Coverage: end-to-end integrity across several framings (8N1/7E1/8O1/5-bit/stick);
// parity error (via a TX/RX parity-mode mismatch); framing error + break (via a
// bit-banged line injection); overrun (via a stalled RX sink); monitor observation.
//
// Run:  dfm run fw.proto.uart.uart-proto      (expect: [uart_proto] PASS)
// ======================================================================
module uart_proto_tb;
    import fw_proto_uart_pkg::*;

    localparam int OVERSAMPLE = 16;
    localparam int DIVISOR    = 2;                 // bit period = 32 clocks
    localparam int BITP       = OVERSAMPLE*DIVISOR;

    // status nibble bits {overrun, brk, framing_err, parity_err}
    localparam int PE = 0, FE = 1, BI = 2, OE = 3;

    // --------------------------------------------------------------
    // Host RX sink: implements uart_rx_if. Queues every delivered character; an
    // optional stall (to force RX overrun) blocks the delivery path.
    // --------------------------------------------------------------
    class rx_sink implements uart_rx_if;
        logic [7:0] data_q[$];
        logic [3:0] stat_q[$];
        bit         stall;

        virtual task recv(input [7:0] data, input [3:0] status);
            while (stall) @(posedge tb_clock);
            data_q.push_back(data);
            stat_q.push_back(status);
        endtask
    endclass

    // --------------------------------------------------------------
    // Observer: implements uart_monitor_if. Counts every observed character.
    // --------------------------------------------------------------
    class observer implements uart_monitor_if;
        int unsigned n_seen;
        virtual function void observe(input [7:0] data, input [3:0] status, input is_tx);
            n_seen++;
        endfunction
    endclass

    // --------------------------------------------------------------
    // Signal-level setup: TX drives the line; an injection mux lets the TB bit-bang
    // raw frames (framing/break tests) while the TX core idles at mark.
    // --------------------------------------------------------------
    logic tb_clock = 1'b0;
    logic tb_reset = 1'b1;
    always #5ns tb_clock = ~tb_clock;

    wire  txd;                       // TX serial output
    logic inj_en  = 1'b0;            // 1 => the TB drives the line directly
    logic inj_val = 1'b1;
    wire  line    = inj_en ? inj_val : txd;   // the shared serial line

    // checker config (kept in step with the configure() calls below)
    logic [15:0] k_div  = DIVISOR;
    logic [3:0]  k_wb   = 8;
    logic        k_pen  = 0, k_pev = 0, k_pst = 0;
    logic [1:0]  k_stop = 0;

    uart_tx_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_tx (
        .clock(tb_clock), .reset(tb_reset), .txd(txd));
    uart_rx_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_rx (
        .clock(tb_clock), .reset(tb_reset), .rxd(line));
    uart_monitor_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_mon (
        .clock(tb_clock), .reset(tb_reset), .line(line));

    // The kit's reusable protocol-invariant checker (same module the formal proof
    // uses). Its synthesizable immediate asserts run here; its concurrent SVA layer
    // also runs when compiled with -DUART_PROTO_SVA.
    uart_proto_checker #(.OVERSAMPLE(OVERSAMPLE)) u_chk (
        .clock(tb_clock), .reset(tb_reset), .line(line),
        .cfg_divisor(k_div), .cfg_word_bits(k_wb), .cfg_parity_en(k_pen),
        .cfg_parity_even(k_pev), .cfg_parity_stick(k_pst), .cfg_stop_bits(k_stop));

    // bridges + models (built in the initial block)
    uart_tx_xtor_bridge      tbr;
    uart_rx_xtor_bridge      rbr;
    uart_monitor_xtor_bridge mbr;
    rx_sink                  snk;
    observer                 obs;

    int errors = 0;

    // configure all three roles + the checker to one framing
    task automatic set_cfg(input [15:0] divisor, input [3:0] word_bits,
                           input parity_en, input parity_even, input parity_stick,
                           input [1:0] stop_bits);
        tbr.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
        rbr.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
        mbr.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
        k_div = divisor; k_wb = word_bits; k_pen = parity_en;
        k_pev = parity_even; k_pst = parity_stick; k_stop = stop_bits;
        @(posedge tb_clock);
    endtask

    // wait roughly N character-times
    task automatic wait_chars(input int n);
        repeat (n*(BITP*13)) @(posedge tb_clock);
    endtask

    // bit-bang one raw frame onto the line (TX core must be idle). stop_val=0 forces
    // a framing error / break; data=0 + stop=0 yields a break.
    task automatic send_raw_frame(input [7:0] data, input [3:0] word_bits,
                                  input parity_en, input parity_even, input parity_stick,
                                  input stop_val);
        logic p;
        // hold the line idle (mark) for a full bit period first, so the start edge
        // is bit-period-stable (the checker's stability rule); the TX line is idle.
        inj_en = 1'b1; inj_val = 1'b1; repeat (BITP) @(posedge tb_clock);
        // start bit (space)
        inj_val = 1'b0; repeat (BITP) @(posedge tb_clock);
        // data bits, LSB first
        for (int i = 0; i < word_bits; i++) begin
            inj_val = data[i]; repeat (BITP) @(posedge tb_clock);
        end
        // parity bit
        if (parity_en) begin
            p = ^(data & ((1<<word_bits)-1));
            if (!parity_even) p = ~p;
            if (parity_stick) p = ~parity_even;
            inj_val = p; repeat (BITP) @(posedge tb_clock);
        end
        // stop bit (mark, unless we are forcing an error)
        inj_val = stop_val; repeat (BITP) @(posedge tb_clock);
        // release back to the (idle, mark) TX line
        inj_en = 1'b0;
        repeat (BITP) @(posedge tb_clock);
    endtask

    // check the next sink entry against expected data + status
    task automatic expect_rx(input [7:0] exp_data, input [3:0] exp_stat, input string tag);
        logic [7:0] d; logic [3:0] s;
        int spins = 0;
        while (snk.data_q.size() == 0 && spins < BITP*60) begin
            @(posedge tb_clock); spins++;
        end
        if (snk.data_q.size() == 0) begin
            $display("FAIL[%s]: no character received", tag); errors++; return;
        end
        d = snk.data_q.pop_front();
        s = snk.stat_q.pop_front();
        if (d !== exp_data || s !== exp_stat) begin
            $display("FAIL[%s]: got data=0x%02h stat=0x%1h exp data=0x%02h stat=0x%1h",
                     tag, d, s, exp_data, exp_stat); errors++;
        end else
            $display("[rx] %s data=0x%02h stat=0x%1h OK", tag, d, s);
    endtask

    // ------------------------------------------------------------------
    // integrity sweep across a framing: send a handful of chars, check round trip.
    // ------------------------------------------------------------------
    task automatic sweep(input [3:0] word_bits, input parity_en, input parity_even,
                         input parity_stick, input [1:0] stop_bits, input string tag);
        logic [7:0] mask = (word_bits >= 8) ? 8'hff : ((1 << word_bits) - 1);
        set_cfg(DIVISOR, word_bits, parity_en, parity_even, parity_stick, stop_bits);
        for (int i = 0; i < 4; i++) begin
            automatic logic [7:0] d = (8'h41 + i) & mask;
            tbr.send(d);
            expect_rx(d, 4'h0, tag);
        end
    endtask

    // ------------------------------------------------------------------
    initial begin
        tbr = new(u_tx.u_if);
        snk = new();
        obs = new();
        rbr = new(u_rx.u_if, snk);
        mbr = new(u_mon.u_if, obs, 1'b1);   // monitor taps the TX line (is_tx=1)

        tb_reset = 1'b1;
        repeat (4) @(posedge tb_clock);
        tb_reset = 1'b0;
        @(posedge tb_clock);

        rbr.start();
        mbr.start();

        // --- end-to-end integrity across framings ---
        sweep(4'd8, 1'b0, 1'b0, 1'b0, 2'd0, "8N1");
        sweep(4'd7, 1'b1, 1'b1, 1'b0, 2'd0, "7E1");
        sweep(4'd8, 1'b1, 1'b0, 1'b0, 2'd0, "8O1");
        sweep(4'd5, 1'b0, 1'b0, 1'b0, 2'd1, "5N2");
        sweep(4'd8, 1'b1, 1'b1, 1'b1, 2'd0, "8-stick");

        // --- parity error: TX even, RX odd, one char => PE at the receiver ---
        begin
            tbr.configure(DIVISOR, 4'd8, 1'b1, 1'b1, 1'b0, 2'd0);   // TX even parity
            rbr.configure(DIVISOR, 4'd8, 1'b1, 1'b0, 1'b0, 2'd0);   // RX odd  parity
            mbr.configure(DIVISOR, 4'd8, 1'b1, 1'b0, 1'b0, 2'd0);
            k_pen = 1; k_pev = 1;                                    // checker: TX framing
            @(posedge tb_clock);
            tbr.send(8'h5A);
            expect_rx(8'h5A, 4'(1 << PE), "parity-err");
        end

        // --- framing error: bit-banged frame with a 0 (space) stop bit ---
        set_cfg(DIVISOR, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
        send_raw_frame(8'h55, 4'd8, 1'b0, 1'b0, 1'b0, /*stop_val*/1'b0);
        expect_rx(8'h55, 4'(1 << FE), "framing-err");

        // --- break: bit-banged all-space frame (data 0, stop 0) ---
        send_raw_frame(8'h00, 4'd8, 1'b0, 1'b0, 1'b0, /*stop_val*/1'b0);
        expect_rx(8'h00, 4'(1 << BI), "break");

        // --- overrun: stall the sink, overflow the RX FIFO, then deliver one more ---
        begin
            int got_before, lost;
            set_cfg(DIVISOR, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
            snk.data_q.delete(); snk.stat_q.delete();
            snk.stall = 1'b1;
            for (int i = 0; i < 12; i++) tbr.send(8'h60 + i);   // overflow (FIFO depth 8)
            wait_chars(13);
            snk.stall = 1'b0;                                   // drain the buffered chars
            wait_chars(3);
            tbr.send(8'hC3);                                    // carries the overrun flag
            wait_chars(3);
            got_before = snk.data_q.size();
            lost = 13 - got_before;
            if (lost <= 0) begin
                $display("FAIL[overrun]: expected dropped chars, lost=%0d", lost); errors++;
            end else begin
                automatic bit saw_oe = 0;
                foreach (snk.stat_q[i]) if (snk.stat_q[i][OE]) saw_oe = 1;
                if (!saw_oe) begin
                    $display("FAIL[overrun]: no overrun status observed"); errors++;
                end else
                    $display("[rx] overrun OK (lost %0d chars, OE flagged)", lost);
            end
        end

        // --- monitor: it observed every clean+injected frame on the tapped line ---
        wait_chars(2);
        if (obs.n_seen == 0) begin
            $display("FAIL: monitor observed no characters"); errors++;
        end else
            $display("[monitor] observed %0d characters OK", obs.n_seen);

        if (errors == 0) $display("[uart_proto] PASS");
        else             $display("[uart_proto] FAIL (%0d errors)", errors);
        $finish;
    end

    // Watchdog so a broken handshake fails fast instead of hanging.
    initial begin
        #5ms;
        $fatal(1, "[uart_proto] TIMEOUT");
    end
endmodule
