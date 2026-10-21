// ======================================================================
// Back-to-back simulation test for the UART kit (K9).
//
// A tx transactor drives one line into an rx transactor, with a monitor
// tapping the line, through the whole stack: class API -> bridge ->
// xtor_if -> baud tick + core -> line and back. Every character the rx
// sink receives is checked against what was sent, and the monitor must
// report the same character and status as the receiver.
//
// TESTS selects the groups:
//   1  framing: word lengths 5..8, parity none/odd/even/stick 0/stick 1,
//      stop 1/1.5/2, at divisors 1, 2, 3; exact frame timing; parity
//      mismatch; break (send_break and the raw set_break level, K4);
//      overrun; divisor 0
//   2  error injection (K6): bad parity, bad stop, both; baud offset of
//      +-3% (received clean) and +-8% (must be corrupted); a glitch on the
//      idle line (rejected) and in a data bit (flips it)
//
// The kit's checker watches the tx CORE's output, not the line, since the
// injected frames break its bit-stability rule on purpose.
//
// Run:  dfm run uart-proto | uart-proto-os4 | uart-proto-err
// ======================================================================
module uart_proto_tb #(
        parameter int OVERSAMPLE = 16,
        parameter int TESTS      = 1
    );
    import fw_proto_uart_pkg::*;

    localparam int PE = 0, FE = 1, BI = 2, OE = 3;

    logic tb_clock = 1'b0;
    logic tb_reset = 1'b1;
    always #5ns tb_clock = ~tb_clock;

    longint cyc = 0;            // clock count, for timing checks
    always @(posedge tb_clock) cyc <= cyc + 1;

    // Receiving sink; `stall` blocks delivery to force an overrun.
    class rx_sink implements uart_rx_if;
        bit [7:0] data_q[$];
        bit [3:0] stat_q[$];
        bit       stall;
        virtual task recv(input bit [7:0] data, input bit [3:0] status);
            while (stall) @(posedge tb_clock);
            data_q.push_back(data);
            stat_q.push_back(status);
        endtask
    endclass

    class observer implements uart_monitor_if;
        bit [7:0] data_q[$];
        bit [3:0] stat_q[$];
        virtual function void observe(input bit [7:0] data, input bit [3:0] status,
                                      input bit is_tx);
            data_q.push_back(data);
            stat_q.push_back(status);
        endfunction
    endclass

    wire line;

    // Checker configuration, kept in step with set_cfg().
    logic [15:0] k_div  = 16'd2;
    logic [3:0]  k_wb   = 4'd8;
    logic        k_pen  = 1'b0, k_pev = 1'b0, k_pst = 1'b0;
    logic [1:0]  k_stop = 2'd0;

    uart_tx_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_tx (
        .clock(tb_clock), .reset(tb_reset), .txd(line));
    uart_rx_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_rx (
        .clock(tb_clock), .reset(tb_reset), .rxd(line));
    uart_monitor_xtor #(.OVERSAMPLE(OVERSAMPLE)) u_mon (
        .clock(tb_clock), .reset(tb_reset), .line(line));

    uart_proto_checker #(.OVERSAMPLE(OVERSAMPLE)) u_chk (
        .clock(tb_clock), .reset(tb_reset), .line(u_tx.core_txd),
        .cfg_divisor(k_div));

    uart_tx_xtor_bridge      tbr;
    uart_rx_xtor_bridge      rbr;
    uart_monitor_xtor_bridge mbr;
    rx_sink                  snk;
    observer                 obs;

    int errors = 0;
    int checked = 0;

    int unsigned cur_div = 2;

    function automatic int unsigned bit_clocks();
        return OVERSAMPLE * cur_div;
    endfunction

    function automatic int unsigned char_clocks();
        int unsigned halves;
        halves = 2 * (1 + int'(k_wb) + int'(k_pen)) +
                 ((k_stop == 0) ? 2 : (k_wb == 5) ? 3 : 4);
        return halves * bit_clocks() / 2;
    endfunction

    task automatic set_cfg(input int unsigned divisor, input bit [3:0] word_bits,
                           input bit parity_en, input bit parity_even,
                           input bit parity_stick, input bit [1:0] stop_bits,
                           input bit wait_idle = 1'b1);
        // Change the line only between characters.
        while (wait_idle && (u_tx.busy || u_tx.u_if.req_cnt != 0)) @(posedge tb_clock);
        tbr.configure(16'(divisor), word_bits, parity_en, parity_even, parity_stick, stop_bits);
        rbr.configure(16'(divisor), word_bits, parity_en, parity_even, parity_stick, stop_bits);
        mbr.configure(16'(divisor), word_bits, parity_en, parity_even, parity_stick, stop_bits);
        k_div = 16'(divisor); k_wb = word_bits; k_pen = parity_en;
        k_pev = parity_even; k_pst = parity_stick; k_stop = stop_bits;
        cur_div = divisor;
        repeat (2) @(posedge tb_clock);
    endtask

    task automatic wait_chars(input int n);
        repeat (n * char_clocks()) @(posedge tb_clock);
    endtask

    task automatic fail(input string msg);
        $display("FAIL: %s", msg);
        errors++;
    endtask

    // The next character at the sink, within a few character times. The
    // monitor's next character must be the same.
    task automatic next_rx(input string tag, output bit got,
                           output bit [7:0] d, output bit [3:0] s);
        int spins = 0;
        while ((snk.data_q.size() == 0 || obs.data_q.size() == 0) &&
               spins < 4 * char_clocks() + 64) begin
            @(posedge tb_clock);
            spins++;
        end
        got = 1'b0;
        if (snk.data_q.size() == 0) begin
            fail($sformatf("[%s] no character received", tag));
            return;
        end
        d = snk.data_q.pop_front();
        s = snk.stat_q.pop_front();
        got = 1'b1;
        if (obs.data_q.size() == 0) begin
            fail($sformatf("[%s] the monitor saw no character", tag));
        end else begin
            bit [7:0] md = obs.data_q.pop_front();
            bit [3:0] ms = obs.stat_q.pop_front();
            if (md !== d || ms !== s)
                fail($sformatf("[%s] monitor 0x%02h/%h != rx 0x%02h/%h", tag, md, ms, d, s));
        end
    endtask

    task automatic expect_rx(input bit [7:0] exp_d, input bit [3:0] exp_s, input string tag);
        bit got;
        bit [7:0] d;
        bit [3:0] s;
        next_rx(tag, got, d, s);
        if (!got) return;
        checked++;
        if (d !== exp_d || s !== exp_s)
            fail($sformatf("[%s] got 0x%02h status %h, expected 0x%02h status %h",
                           tag, d, s, exp_d, exp_s));
    endtask

    // Nothing more arrives in n character times.
    task automatic expect_none(input int n, input string tag);
        wait_chars(n);
        if (snk.data_q.size() != 0 || obs.data_q.size() != 0) begin
            fail($sformatf("[%s] unexpected character 0x%02h status %h", tag,
                           (snk.data_q.size() != 0) ? snk.data_q[0] : obs.data_q[0],
                           (snk.data_q.size() != 0) ? snk.stat_q[0] : obs.stat_q[0]));
            snk.data_q.delete(); snk.stat_q.delete();
            obs.data_q.delete(); obs.stat_q.delete();
        end
    endtask

    // ------------------------------------------------------------------
    // Group 1: framing
    // ------------------------------------------------------------------
    typedef struct {
        string    name;
        bit [3:0] wb;
        bit       pen, pev, pst;
        bit [1:0] stop;
    } framing_t;

    framing_t framings[] = '{
        '{"8N1",     4'd8, 1'b0, 1'b0, 1'b0, 2'd0},
        '{"8O1",     4'd8, 1'b1, 1'b0, 1'b0, 2'd0},
        '{"8E2",     4'd8, 1'b1, 1'b1, 1'b0, 2'd1},
        '{"7E1",     4'd7, 1'b1, 1'b1, 1'b0, 2'd0},
        '{"7O2",     4'd7, 1'b1, 1'b0, 1'b0, 2'd1},
        '{"6N1",     4'd6, 1'b0, 1'b0, 1'b0, 2'd0},
        '{"6E2",     4'd6, 1'b1, 1'b1, 1'b0, 2'd1},
        '{"5N1",     4'd5, 1'b0, 1'b0, 1'b0, 2'd0},
        '{"5O1.5",   4'd5, 1'b1, 1'b0, 1'b0, 2'd1},
        '{"8S0",     4'd8, 1'b1, 1'b1, 1'b1, 2'd0},
        '{"8S1",     4'd8, 1'b1, 1'b0, 1'b1, 2'd0}
    };

    task automatic sweep(input int unsigned divisor, input framing_t f);
        bit [7:0] mask = 8'((1 << f.wb) - 1);
        bit [7:0] pats[4] = '{8'h00, 8'hFF, 8'hA5, 8'h3C};
        string    tag = $sformatf("%s/div%0d", f.name, divisor);
        set_cfg(divisor, f.wb, f.pen, f.pev, f.pst, f.stop);
        // Back to back: queue them all, then check.
        foreach (pats[i]) tbr.send(pats[i]);
        foreach (pats[i]) expect_rx(pats[i] & mask, 4'h0, tag);
    endtask

    // Two back-to-back characters: their start edges are exactly one
    // character time apart, and the start bit is exactly one bit long.
    task automatic frame_timing(input int unsigned divisor, input framing_t f);
        longint t_fall0, t_fall1;
        string  tag = $sformatf("timing %s/div%0d", f.name, divisor);
        set_cfg(divisor, f.wb, f.pen, f.pev, f.pst, f.stop);
        fork
            begin
                tbr.send(8'h00);
                tbr.send(8'h00);
            end
        join_none
        @(negedge line); t_fall0 = cyc;
        // the second frame's start bit
        do @(negedge line); while ((cyc - t_fall0) < longint'(char_clocks()) - 1);
        t_fall1 = cyc;
        if ((t_fall1 - t_fall0) != longint'(char_clocks()))
            fail($sformatf("[%s] character period %0d clocks, expected %0d", tag,
                           t_fall1 - t_fall0, char_clocks()));
        expect_rx(8'h00, 4'h0, tag);
        expect_rx(8'h00, 4'h0, tag);
    endtask

    task automatic start_bit_width(input int unsigned divisor);
        longint t0, t1;
        set_cfg(divisor, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
        fork tbr.send(8'h01); join_none     // start (0) then data bit 0 (1)
        @(negedge line); t0 = cyc;
        @(posedge line); t1 = cyc;
        if ((t1 - t0) != longint'(bit_clocks()))
            fail($sformatf("[start bit/div%0d] %0d clocks, expected %0d", divisor,
                           t1 - t0, bit_clocks()));
        expect_rx(8'h01, 4'h0, "start bit");
    endtask

    task automatic group_framing();
        int unsigned divs[3] = '{1, 2, 3};
        foreach (divs[d]) begin
            foreach (framings[i]) sweep(divs[d], framings[i]);
            start_bit_width(divs[d]);
        end
        frame_timing(3, framings[0]);     // 8N1
        frame_timing(3, framings[8]);     // 5O1.5
        frame_timing(1, framings[2]);     // 8E2

        // Parity mismatch: tx even, rx and monitor odd.
        set_cfg(2, 4'd8, 1'b1, 1'b0, 1'b0, 2'd0);
        tbr.configure(16'd2, 4'd8, 1'b1, 1'b1, 1'b0, 2'd0);
        repeat (2) @(posedge tb_clock);
        tbr.send(8'h5A);
        expect_rx(8'h5A, 4'(1 << PE), "parity mismatch");

        // Break, K4. One character time or more of space gives one break
        // character; normal characters follow it.
        set_cfg(2, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
        tbr.send(8'h11);
        tbr.send_break(1);
        tbr.send(8'h22);
        expect_rx(8'h11, 4'h0, "before break");
        expect_rx(8'h00, 4'(1 << BI), "break 1");
        expect_rx(8'h22, 4'h0, "after break 1");
        tbr.send_break(3);
        tbr.send(8'h33);
        expect_rx(8'h00, 4'(1 << BI), "break 3");
        expect_rx(8'h33, 4'h0, "after break 3");
        expect_none(2, "break");

        // The raw level (LCR.BC): a character sent during the break waits
        // and goes out after it, not lost (OI-10).
        set_cfg(2, 4'd7, 1'b1, 1'b1, 1'b0, 2'd1);
        tbr.set_break(1'b1);
        tbr.send(8'h44);
        wait_chars(3);
        expect_rx(8'h00, 4'(1 << BI), "set_break");
        if (snk.data_q.size() != 0) fail("[set_break] a character got through the break");
        tbr.set_break(1'b0);
        expect_rx(8'h44, 4'h0, "after set_break");
        expect_none(2, "set_break");

        // Overrun: stall the sink so the bridge (1), rx FIFO (8) and core
        // (1) fill. 16 sent: the loop returns with 4 still in the tx FIFO.
        begin
            int got, saw_oe;
            set_cfg(1, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
            snk.stall = 1'b1;
            for (int i = 0; i < 16; i++) tbr.send(8'h60 + 8'(i));
            wait_chars(6);
            snk.stall = 1'b0;
            wait_chars(2);
            tbr.send(8'hC3);
            wait_chars(3);
            got = snk.data_q.size();
            saw_oe = 0;
            foreach (snk.stat_q[i]) if (snk.stat_q[i][OE]) saw_oe++;
            if (got >= 17) fail($sformatf("[overrun] no characters lost (%0d received)", got));
            if (saw_oe != 1) fail($sformatf("[overrun] OE on %0d characters, expected 1", saw_oe));
            if (snk.data_q[got-1] != 8'hC3) fail("[overrun] last character is not 0xC3");
            checked++;
            snk.data_q.delete(); snk.stat_q.delete();
            obs.data_q.delete(); obs.stat_q.delete();
        end

        // Divisor 0 stops the line; the character goes out once it is set.
        set_cfg(0, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
        tbr.send(8'h7E);
        cur_div = 2;
        expect_none(2, "divisor 0");
        if (line !== 1'b1) fail("[divisor 0] line is not at mark");
        set_cfg(2, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0, 1'b0);
        expect_rx(8'h7E, 4'h0, "divisor 0 released");
    endtask

    // ------------------------------------------------------------------
    // Group 2: error injection (K6)
    // ------------------------------------------------------------------
    task automatic group_inject();
        bit got;
        bit [7:0] d;
        bit [3:0] s;
        int unsigned b;
        int ok_ppm[2]  = '{30000, -30000};
        int bad_ppm[2] = '{80000, -80000};

        set_cfg(2, 4'd8, 1'b1, 1'b1, 1'b0, 2'd0);       // 8E1
        b = bit_clocks();
        tbr.send_err(8'h96, 1'b1, 1'b0, 0, 0, 0);
        expect_rx(8'h96, 4'(1 << PE), "bad parity");
        tbr.send_err(8'h96, 1'b0, 1'b1, 0, 0, 0);
        expect_rx(8'h96, 4'(1 << FE), "bad stop");
        tbr.send_err(8'h96, 1'b1, 1'b1, 0, 0, 0);
        expect_rx(8'h96, 4'((1 << PE) | (1 << FE)), "bad parity and stop");
        tbr.send_err(8'h96, 1'b0, 1'b0, 0, 0, 0);
        expect_rx(8'h96, 4'h0, "send_err clean");
        // A receiver resynchronizes on a bad stop bit; the next injected
        // frame must still be seen cleanly (send_err leaves a bit of mark).
        tbr.send_err(8'h96, 1'b0, 1'b1, 0, 0, 0);
        tbr.send_err(8'hC5, 1'b0, 1'b0, 30000, 0, 0);
        expect_rx(8'h96, 4'(1 << FE), "bad stop, then");
        expect_rx(8'hC5, 4'h0, "offset frame after bad stop");
        // Characters sent around injected frames keep their order.
        tbr.send(8'h01);
        tbr.send_err(8'h02, 1'b1, 1'b0, 0, 0, 0);
        tbr.send(8'h03);
        expect_rx(8'h01, 4'h0, "order 1");
        expect_rx(8'h02, 4'(1 << PE), "order 2");
        expect_rx(8'h03, 4'h0, "order 3");

        // Baud offset: +-3% is inside a mid-bit receiver's tolerance.
        foreach (ok_ppm[i]) begin
            int ppm = ok_ppm[i];
            tbr.send_err(8'hC5, 1'b0, 1'b0, ppm, 0, 0);
            expect_rx(8'hC5, 4'h0, $sformatf("baud %0d ppm", ppm));
        end
        // +-8% is not (teeth): 0x55 with even parity, 11 bits.
        foreach (bad_ppm[i]) begin
            int ppm = bad_ppm[i];
            tbr.send_err(8'h55, 1'b0, 1'b0, ppm, 0, 0);
            next_rx($sformatf("baud %0d ppm", ppm), got, d, s);
            if (got && d == 8'h55 && s == 4'h0)
                fail($sformatf("[baud %0d ppm] received clean", ppm));
            checked++;
            expect_none(2, "after baud offset");
        end

        // A glitch on the idle line shorter than half a bit is rejected.
        set_cfg(2, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);       // 8N1
        b = bit_clocks();
        tbr.glitch(b * 3 / 8);
        expect_none(2, "idle glitch");
        checked++;
        // A glitch over the middle of data bit 2 flips it.
        tbr.send_err(8'hF0, 1'b0, 1'b0, 0, 3 * b + b / 2 - b / 4, b / 2);
        expect_rx(8'hF4, 4'h0, "glitch in bit 2");
        // A glitch away from the middle of a bit does nothing.
        tbr.send_err(8'hF0, 1'b0, 1'b0, 0, 3 * b + 1, b / 8);
        expect_rx(8'hF0, 4'h0, "glitch off-centre");
    endtask

    initial begin
        tbr = new(u_tx.u_if);
        snk = new();
        obs = new();
        rbr = new(u_rx.u_if, snk);
        mbr = new(u_mon.u_if, obs, 1'b1);

        repeat (4) @(posedge tb_clock);
        tb_reset = 1'b0;
        @(posedge tb_clock);
        rbr.start_bridge();
        mbr.start_bridge();

        if ((TESTS & 1) != 0) group_framing();
        if ((TESTS & 2) != 0) group_inject();

        expect_none(2, "end");
        if (errors == 0 && checked > 0)
            $display("[uart_proto] PASS (OVERSAMPLE %0d, %0d checks)", OVERSAMPLE, checked);
        else
            $fatal(1, "[uart_proto] FAIL (%0d errors, %0d checks)", errors, checked);
        $finish;
    end

    initial begin
        #50ms;
        $fatal(1, "[uart_proto] TIMEOUT");
    end
endmodule
