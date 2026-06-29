# Getting started

## Prerequisites

The kit builds and runs through [DV Flow Manager](https://github.com/dv-flow/dv-flow-mgr)
(`dfm`). The toolchain (Verilator for simulation, yosys + SymbiYosys + sv2v for formal)
is pulled in via `ivpm.yaml`. From the package root:

```bash
dfm run fw.proto.uart.uart-proto    # back-to-back simulation  -> [uart_proto] PASS
dfm run fw.proto.uart.fv            # SymbiYosys BMC proof      -> DONE (PASS)
dfm run fw.proto.uart.fv-cover      # cover reachability        -> DONE (PASS)
```

## The back-to-back simulation test

`tests/uart_proto_tb.sv` wires a full **TX transactor** to a full **RX transactor**
over one shared serial line, taps a **monitor**, and runs the kit's protocol checker
on the line. It exercises:

- end-to-end integrity across framings: **8N1, 7E1, 8O1, 5-bit/2-stop, 8-bit stick**;
- a **parity error** (TX even / RX odd) → the `PE` status bit;
- a **framing error** and a **break** (bit-banged frames with a space stop / all-space);
- **overrun** (a stalled receive sink overflows the RX FIFO; the `OE` bit is flagged and
  characters are dropped — the one lossy UART behaviour);
- the **monitor** observing every framed character on the tapped line.

Expected console result: `[uart_proto] PASS`.

## Using the kit in your own testbench

Instance the transactors, build the bridges + your models, wire them by handle, then
`start()` the consumer bridges:

```systemverilog
import fw_proto_uart_pkg::*;

// 1. signal-level transactors on a shared line
wire txd;
uart_tx_xtor      u_tx  (.clock(clk), .reset(rst), .txd(txd));
uart_rx_xtor      u_rx  (.clock(clk), .reset(rst), .rxd(txd));
uart_monitor_xtor u_mon (.clock(clk), .reset(rst), .line(txd));

// 2. a host sink that consumes received characters
class my_sink implements uart_rx_if;
    virtual task recv(input [7:0] data, input [3:0] status);
        $display("rx: 0x%02h status=0x%1h", data, status);
    endtask
endclass

initial begin
    automatic uart_tx_xtor_bridge tx  = new(u_tx.u_if);
    automatic my_sink             snk = new();
    automatic uart_rx_xtor_bridge rx  = new(u_rx.u_if, snk);

    // 3. configure both ends to the same framing (8N1, divisor 2)
    tx.configure(16'd2, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
    rx.configure(16'd2, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);

    // 4. start the consumer loop, then transmit
    rx.start();
    tx.send(8'h41);   // 'A'
    tx.send(8'h42);   // 'B'
end
```

`send()` blocks only until the character is accepted into the TX FIFO; the frame then
shifts out on the line. The RX bridge's `run()` loop deframes each character and calls
your sink's `recv()`. To pull characters directly (without a sink), call
`u_rx.u_if.recv(data, status)` on the transactor interface.

## Configuration arguments

`configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits)`:

| Argument | Meaning |
| --- | --- |
| `divisor` | baud divider; one bit period = `OVERSAMPLE * divisor` system clocks (`0` disables I/O) |
| `word_bits` | data bits per character, `5`..`8` |
| `parity_en` | `1` = a parity bit is generated/checked |
| `parity_even` | `1` = even parity, `0` = odd |
| `parity_stick` | `1` = stick parity (parity forced to a fixed level) |
| `stop_bits` | `0` ⇒ 1 stop bit; `1` ⇒ 1.5 (5-bit char) / 2 stop bits |
