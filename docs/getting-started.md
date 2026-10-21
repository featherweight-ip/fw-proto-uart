# Getting started

## Build and run

The kit builds with [DV Flow Manager](https://github.com/dv-flow/dv-flow-mgr)
(`dfm`) on the `project.dv` archetype. `ivpm update` (dep-set `dev`) fetches
the toolchain: Verilator for simulation, and yosys, SymbiYosys and sv2v for
formal. From the package root:

```bash
dfm run tests        # uart-proto, uart-proto-os4, uart-proto-err
dfm run lint-rtl     # zero findings
dfm run fv-quick     # per-push BMC (~30 s)
dfm run fv           # nightly BMC
dfm run fv-cover     # cover goals
```

Each sim prints `[uart_proto] PASS (OVERSAMPLE n, k checks)`, and `$fatal`s
on any error.

## A first testbench

```systemverilog
module my_tb;
    import fw_proto_uart_pkg::*;

    logic clk = 0, rst = 1;
    always #5ns clk = ~clk;
    initial begin repeat (3) @(posedge clk); rst = 0; end

    wire line;
    uart_tx_xtor u_tx (.clock(clk), .reset(rst), .txd(line));
    uart_rx_xtor u_rx (.clock(clk), .reset(rst), .rxd(line));

    class my_sink implements uart_rx_if;
        virtual task recv(input bit [7:0] data, input bit [3:0] status);
            $display("rx 0x%02h status %b", data, status);   // {OE, BI, FE, PE}
        endtask
    endclass

    uart_tx_xtor_bridge tx;
    uart_rx_xtor_bridge rx;

    initial begin
        my_sink sink = new();
        tx = new(u_tx.u_if);
        rx = new(u_rx.u_if, sink);
        @(negedge rst);
        rx.start_bridge();

        // 8N1, divisor 4: a bit is 16 * 4 clocks
        tx.configure(16'd4, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
        rx.configure(16'd4, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);

        tx.send(8'h41);
        tx.send_break(2);
        tx.send(8'h42);
        repeat (5000) @(posedge clk);
        $finish;
    end
endmodule
```

It prints `0x41`, then `0x00` with BI (`0100`), then `0x42`. The consumer
skill (`skills/fw-proto-uart/SKILL.md`) has the dv-flow setup, the monitor,
error injection, and the cores used directly in a design.

## `configure()` arguments

| Argument | Meaning (16550 field) |
| --- | --- |
| `divisor` | clocks per tick; a bit is `OVERSAMPLE` ticks; 0 stops the line (DLL/DLM) |
| `word_bits` | data bits, 5..8 (LCR[1:0] + 5) |
| `parity_en` | a parity bit is sent and checked (LCR[3]) |
| `parity_even` | even parity; 0 = odd (LCR[4]) |
| `parity_stick` | the parity bit is fixed at `!parity_even` (LCR[5]) |
| `stop_bits` | 0 = 1 stop bit; otherwise 2, or 1.5 with 5-bit words (LCR[2]) |

Configure tx, rx and monitor alike, between characters.
