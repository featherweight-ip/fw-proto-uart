# Overview

`fw-proto-uart` lets model and test code work in characters ("send this
byte", "here is the next byte received, with its status") while the kit
handles the frame: start bit, data LSB first, parity, stop bits, the
oversampled receiver, and the line status.

## Layers

```
   API (interface class)          what your code calls
        |  send / recv / observe / configure / set_break / send_err
   bridge (plain class)           API <-> transactor tasks
        |  blocking tasks
   transactor interface (SV)      FIFO, held configuration, error injection
        |  ready/valid + cfg_* levels + brk
   cores (SV modules)             baud tick, tx, rx, monitor: synthesizable
        |  txd / rxd
   the line
```

Each role has the kit's six elements:

- **API** (`uart_<role>_if.svh`), an `interface class`.
- **Transactor interface** (`uart_<role>_xtor_if.sv`): a FIFO, the held
  configuration, and the blocking tasks. Not synthesizable.
- **Core** (`uart_<role>_xtor_core.sv`): the clocked FSM, between the line
  and a ready/valid character link. No queues or classes, so it
  synthesizes and goes through SymbiYosys.
- **Wrapper** (`uart_<role>_xtor.sv`): the interface, a baud tick core and
  the role's core, with `clock`, `reset` and the bare pin.
- **Bridge** (`uart_<role>_bridge.svh`): connects the tasks to the API.
- The **package** `fw_proto_uart_pkg` holds the APIs and bridges.

## Shared baud tick (K2)

`uart_baud_xtor_core` makes the oversampling enable: `tick` is high one
clock in every `divisor`. The tx, rx and monitor cores count bit time in
ticks (`OVERSAMPLE`, default 16, per bit) and have no divider of their own.
The 16550 has one divisor latch for both directions, so a 16550-style
design instantiates one baud core and gives its tick to tx and rx. That
saves a second 16-bit counter. Each wrapper holds its own baud core, so the
transactors also work standalone, as a VIP needs.

Every tx bit edge is on a tick, so each bit is exactly `OVERSAMPLE ×
divisor` clocks. A character is accepted on the tick that ends the previous
stop bit, so back-to-back frames have no gap.

## Configuration

The framing is set at run time: `divisor`, `word_bits` (5 to 8), parity
(none, odd, even, stick), and stop bits. It is a held level into the cores,
sampled once per character: tx samples it when it accepts the character, rx
at the start bit. A change therefore applies from the next character (K1).
The character carrier is always 8 bits, and `word_bits` says how many low
bits count.

## Break (K4)

The tx core takes `brk` as a level, as 16550 LCR.BC. While `brk` is 1 the
line is space and no new character is accepted. Characters sent meanwhile
wait, and go out after the break; a 16550 would send them invisibly and
lose them. A character already started when `brk` rises carries on
underneath and is lost, as on a 16550. After `brk` falls, the core holds
mark for one bit before the next start bit, so a receiver sees the break
end.

The rx core reports a break (the whole frame space) as one character, data
0 with BI, then waits for the line to return to mark before it looks for a
start bit. One break gives one character.

## Error injection (K6)

Error injection is for the VIP only, so it is outside the cores. The tx
transactor interface builds an injected frame (bad parity, bad stop bit, a
baud offset in ppm, a glitch at any clock) and drives it clock by clock
through `ovr_en`/`ovr_val`. The `uart_tx_xtor` wrapper muxes that over the
core's `txd`. A design that uses the cores carries none of it.

## Fixed and parameterized

The character carrier (8 bits), status (4 bits) and divisor (16 bits) are
fixed widths. `OVERSAMPLE` is a build-time parameter: the formal harnesses
run at 2 and 4, so that a frame fits in a tractable BMC depth.
