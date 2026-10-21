---
name: fw-proto-uart
description: >
  Use this skill to USE the Featherweight-HDL UART protocol kit (package
  `fw.proto.uart`, in fw-proto-uart) from a testbench, VIP or design: how to
  reference the package from a dv-flow build, instance the tx/rx/monitor
  transactors on a serial line, drive and receive characters through the
  class APIs (`uart_tx_if`, `uart_rx_if`, `uart_monitor_if`,
  `uart_config_if`), inject line errors (`uart_tx_inject_if`), and use the
  synthesizable cores directly with one shared baud tick (16550 style).
  This is the CONSUMER guide; to BUILD a protocol kit see `fw-proto-kit`.
---

# Using the UART protocol kit (fw.proto.uart)

The kit connects class-level APIs to an asynchronous serial line. Code
written against an API never touches pins; a transactor does. You instance
the transactor modules on your line, wrap each in a bridge, and call the
API.

| Role | Module (pins) | API | Bridge |
|---|---|---|---|
| tx | `uart_tx_xtor` (`txd`) | `uart_tx_if`, `uart_tx_inject_if`, `uart_config_if` | `uart_tx_xtor_bridge`: implements them; call it |
| rx | `uart_rx_xtor` (`rxd`) | you implement `uart_rx_if.recv(data, status)` | `uart_rx_xtor_bridge`: holds your sink and calls it |
| monitor | `uart_monitor_xtor` (`line`) | you implement `uart_monitor_if.observe(data, status, is_tx)` | `uart_monitor_xtor_bridge`: holds your subscriber |

Every module has `clock`, `reset` (active high, asynchronous) and the
parameters `MAX_DATA_BITS` (8), `DIV_WIDTH` (16) and `OVERSAMPLE` (16
ticks per bit).

## 1. Reference the package

Fetch the package with ivpm `dep-set: use` (it then brings nothing but
fw-hdl), import it by name through the package map, and depend on one of
its exports:

| Export | Contents | Use it for |
|---|---|---|
| `fw.proto.uart.files` | everything: class package, interfaces, wrappers, cores, checker | a testbench or VIP |
| `fw.proto.uart.xtor-core` | the four synthesizable cores | a design (RTL only) |
| `fw.proto.uart.checker` | `uart_proto_checker` alone | a bind on real RTL |
| `fw.proto.uart.class` | the class package (needs the interfaces) | layering |

```yaml
package:
  name: myapp
  package-map: "${{ env.IVPM_PACKAGES }}/dv-flow-package-map.yaml"
  imports:
  - hdlsim
  - fw.proto.uart
  tasks:
  - name: tb
    uses: std.FileSet
    with: {type: systemVerilogSource, include: [my_tb.sv]}
  - name: img
    uses: hdlsim.vlt.SimImage
    needs: [fw.proto.uart.files, tb]
    with: {top: [my_tb]}
  - name: run
    uses: hdlsim.vlt.SimRun
    needs: [img]
```

## 2. Instance and wire

```systemverilog
import fw_proto_uart_pkg::*;

wire line;
uart_tx_xtor      u_tx  (.clock(clk), .reset(rst), .txd(line));
uart_rx_xtor      u_rx  (.clock(clk), .reset(rst), .rxd(line));
uart_monitor_xtor u_mon (.clock(clk), .reset(rst), .line(line));
```

`rxd` must already be synchronous to `clock`; put a 2-flop synchronizer in
front of a real pad.

## 3. Bridges and APIs

```systemverilog
class my_sink implements uart_rx_if;
    virtual task recv(input bit [7:0] data, input bit [3:0] status);
        $display("rx 0x%02h status %b", data, status);   // {OE, BI, FE, PE}
    endtask
endclass

class my_mon implements uart_monitor_if;
    virtual function void observe(input bit [7:0] data, input bit [3:0] status,
                                  input bit is_tx);
    endfunction
endclass

uart_tx_xtor_bridge      tx;
uart_rx_xtor_bridge      rx;
uart_monitor_xtor_bridge mon;

initial begin
    my_sink sink = new();
    my_mon  m    = new();
    tx  = new(u_tx.u_if);
    rx  = new(u_rx.u_if, sink);
    mon = new(u_mon.u_if, m, 1'b1);     // is_tx = 1: this taps the tx line
    @(negedge rst);
    rx.start_bridge();                  // forks the delivery loops
    mon.start_bridge();

    // 8N1 at divisor 4: a bit is 16 * 4 clocks. Configure every role.
    tx.configure(16'd4, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
    rx.configure(16'd4, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);
    mon.configure(16'd4, 4'd8, 1'b0, 1'b0, 1'b0, 2'd0);

    tx.send(8'h41);                     // returns once queued
    tx.send_break(2);                   // two character times of space
    tx.send(8'h42);
end
```

`configure(divisor, word_bits, parity_en, parity_even, parity_stick,
stop_bits)`:

| Argument | Meaning (16550 field) |
|---|---|
| `divisor` | clocks per tick; a bit is `OVERSAMPLE` ticks; 0 stops the line (DLL/DLM) |
| `word_bits` | 5..8 (LCR[1:0] + 5) |
| `parity_en`, `parity_even`, `parity_stick` | LCR[3], LCR[4], LCR[5]. Stick: the parity bit is `!parity_even` |
| `stop_bits` | 0: 1 stop; else 2, or 1.5 for 5-bit words (LCR[2]) |

A change applies from the next character. Configure between characters.

## 4. Break and error injection

- `set_break(1)` / `set_break(0)`: the level, as 16550 LCR.BC. The line goes
  to space at once; characters sent meanwhile wait and go out after it. A
  character already on the line is lost, as on a 16550.
- `send_break(n_chars)`: waits for everything queued to go out, then a
  clean break of `n_chars` character times.
- The receiver gives one character per break: data 0, status BI. It then
  waits for mark. The transmitter holds mark for one bit after any break.

Error injection (`uart_tx_inject_if`, on the tx bridge) drives the line from
the transactor interface, not the core:

```systemverilog
tx.send_err(8'h96, /*bad_parity*/1, /*bad_stop*/0, /*baud_ppm*/0, 0, 0);  // PE, if parity is on
tx.send_err(8'h96, 0, 1, 0, 0, 0);                                         // FE
tx.send_err(8'hC5, 0, 0, 30000, 0, 0);       // +3% slow; a 16x receiver takes it
tx.send_err(8'hF0, 0, 0, 0, at, len);        // invert the line for len clocks
tx.glitch(len);                              // a space pulse on the idle line
```

Each call waits for the line to be idle and holds queued characters back
until it is done, so `send()` and `send_err()` from one thread keep their
order. An injected frame is followed by one bit of mark: a receiver that
resynchronized on a bad stop bit needs an idle line before the next
start bit.

## 5. Cores in a design (one divider, 16550 style)

A design instantiates the cores from `xtor-core` and shares one baud tick:

```systemverilog
uart_baud_xtor_core u_baud (.clock, .reset, .cfg_divisor(dl), .tick);
uart_tx_xtor_core   u_tx   (.clock, .reset, .tick, .txd(stx), .brk(lcr_bc), .busy(tx_busy),
                            .cfg_word_bits(wbits), .cfg_parity_en(pen), .cfg_parity_even(eps),
                            .cfg_parity_stick(sp), .cfg_stop_bits({1'b0, stb}),
                            .req_dat(thr), .req_valid(thr_valid), .req_ready(thr_ready));
uart_rx_xtor_core   u_rx   (.clock, .reset, .tick, .rxd(srx_sync),
                            .cfg_word_bits(wbits), .cfg_parity_en(pen), .cfg_parity_even(eps),
                            .cfg_parity_stick(sp),
                            .rsp_dat({rbr, oe, bi, fe, pe}), .rsp_valid(rx_valid),
                            .rsp_ready(rx_ready));
```

- `req_*` and `rsp_*` are ready/valid. The rx output is single-entry: a
  character that completes before the last one was taken is dropped, and
  OE is set on the next.
- `busy` is 1 while a character is in the tx core, so 16550 TEMT is
  `!busy` and the FIFO empty. `req_ready` and `busy` are both 1 only on
  the tick that ends a stop bit: back-to-back frames have no gap.
- The cores reset asynchronously.

## Tasks in this repo

| Command | Runs |
|---|---|
| `dfm run tests` / `smoke` | `uart-proto`, `uart-proto-os4`, `uart-proto-err` |
| `dfm run lint-rtl` | Verilator lint of the cores and checker, zero findings |
| `dfm run fv-quick` / `fv` / `fv-cover` | formal (tests/formal/PROPERTIES.md) |

## Gotchas

- The bridges take `virtual uart_*_xtor_if` of the default parameters.
  Change `OVERSAMPLE` on the wrapper (it is a port of the interface, not a
  parameter); keep `MAX_DATA_BITS` and `DIV_WIDTH` at their defaults when
  using the bridges.
- `uart_proto_checker`'s bit-stability rule fails on frames from
  `send_err`/`glitch` and on a `set_break` raised in the middle of a
  character, both on purpose. Check the tx core's output
  (`u_tx.core_txd`), not the line, when you inject.
- Configure tx, rx and monitor alike. A mismatch is a valid way to make PE
  or FE, but it is not an error in the kit.
