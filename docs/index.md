# fw-proto-uart: UART protocol kit

A [Featherweight-HDL](https://github.com/featherweight-hdl) **protocol kit**
that connects class-level transmit, receive and monitor APIs to an
asynchronous serial line with 16550-style framing. Test, model and VIP code
calls methods on SystemVerilog `interface class`es, and per-role
transactors drive and sample the line. A passive checker enforces the line
invariants; back-to-back sims and SymbiYosys proofs check the cores.

```{admonition} Status
:class: tip
tx, rx and monitor, with framing set at run time (5 to 8 bits; parity none,
odd, even, stick 0 or stick 1; 1, 1.5 or 2 stop bits). One shared baud tick
core (K2). Break as a level and as a timed clean break, with one BI
character per break (K4). VIP-side error injection: bad parity, bad stop,
baud offset, glitches (K6). The sims (`uart-proto`, `uart-proto-os4`,
`uart-proto-err`) pass. The BMC proofs (`fv-quick`, `fv`) pass, and
`fv-cover` reaches every cover goal. Lint has zero findings.
```

## UART in one paragraph

UART is an asynchronous serial line: there is no shared clock. A
transmitter sends each character as a frame: a start bit (space), 5 to 8
data bits LSB first, an optional parity bit, and 1, 1.5 or 2 stop bits
(mark). A receiver oversamples the line, finds the start edge, samples each
bit in its middle, and reports the character with its line status (parity,
framing, break, overrun). The two directions are independent one-way
streams.

## The roles

| Role | API | Line | Bridge |
| --- | --- | --- | --- |
| **tx** | `uart_tx_if`: `send`, `set_break`, `send_break`; `uart_tx_inject_if`: `send_err`, `glitch` | drives `txd` | provider (implements the APIs) |
| **rx** | `uart_rx_if`: `recv(data, status)` | samples `rxd` | consumer (holds a sink; `start_bridge()`) |
| **monitor** | `uart_monitor_if`: `observe(data, status, is_tx)` | taps a line | consumer (holds a subscriber; `start_bridge()`) |

All three also implement `uart_config_if.configure(...)`.

## Where to start

- {doc}`overview`: how the kit is built, and the 16550-driven choices.
- {doc}`getting-started`: build, run, and a first testbench.
- {doc}`api-reference`: every API, bridge and core port.
- {doc}`verification` and {doc}`protocol-property-checking`: what is
  checked, and how.

```{toctree}
:maxdepth: 2
:caption: Guide

overview
getting-started
api-reference
verification
protocol-property-checking
```
