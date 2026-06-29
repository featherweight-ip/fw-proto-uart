# Overview

`fw-proto-uart` packages the UART **line protocol** as a reusable transactor kit.
The goal is to let model and test code work in terms of *characters* — "send this
byte", "give me the next received byte and its status" — while the kit handles the
entire serial frame: start bit, LSB-first data, parity, stop bits, oversampled
receive, and the line-error taxonomy.

## Layered architecture

```
   method API (interface class)        <- what your code calls
        |  send() / recv() / observe() / configure()
   bridge (plain class)                <- adapts API <-> transactor task API
        |  blocking tasks
   transactor interface (SV interface) <- synthesizable FIFOs + held config
        |  ready/valid character stream + cfg_* level
   transactor core (SV module)         <- the clocked serializer / deserializer
        |  serial line (txd / rxd)
   the UART wire
```

Every role is built from the same four files:

- **core** (`uart_<role>_xtor_core.sv`) — the clocked FSM. TX serializes a character
  into a frame; RX/monitor oversample the line and deframe. The core converts between
  the serial pins and a ready/valid character **stream**, and reads the current
  framing from a held `cfg_*` level. It contains no SV queues or classes, so it is
  synthesizable and can be driven through SymbiYosys.
- **interface** (`uart_<role>_xtor_if.sv`) — hand-coded synthesizable FIFOs plus a
  blocking individual-argument **task API** (`send`, `recv`, `wait_char`), and the
  held configuration registers (`configure`) driven to the core.
- **wrapper** (`uart_<role>_xtor.sv`) — instances the interface and the core and wires
  them together; exposes `clock`, `reset`, and the bare serial pin.
- **bridge** (`uart_<role>_xtor_bridge.svh`) — a plain class connecting the task API to
  the method API. The TX bridge **implements** `uart_tx_if` (a provider). The RX and
  monitor bridges **hold** a handle to a sink/subscriber and fork a `run()` loop in
  `start()` (consumers). All bridges implement `uart_config_if`.

## Why two independent streams

UART is full-duplex over two physically separate wires; each wire is **simplex**
(one direction) and the two directions are fully decoupled — there is no response
travelling back to the transmitter. So the kit gives TX and RX **separate one-way
APIs** rather than a single request/response transfer. This is the defining shape of
the protocol and the reason the method layer looks different from a memory-mapped bus.

## Runtime configuration as a held level

The framing is runtime-configurable: baud `divisor`, `word_bits` (5–8), parity
(`none`/`odd`/`even`/`stick`), and stop bits. Rather than a per-character payload,
configuration is a **held level**: `configure(...)` latches the `cfg_*` registers in
the transactor interface, which are driven continuously to the core and sampled when
a frame starts (TX) or a start bit is detected (RX). The character carrier is a fixed
8-bit maximum; the active `word_bits` selects how many low bits are significant — the
interface width never changes with configuration.

## What's fixed vs. parameterized

The character width (8), status width (4), and divisor width (16) are fixed. The
**oversample factor** is a build-time parameter (`OVERSAMPLE`, default 16) so the
formal harness can shrink it for a tractable bounded-model-check depth — at the real
16× rate a character crosses in >160 cycles, too deep for end-to-end BMC. The kit's
formal proof runs at `OVERSAMPLE=2`, `divisor=1`.
