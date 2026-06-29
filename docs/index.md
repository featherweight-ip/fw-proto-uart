# fw-proto-uart — UART Protocol Kit

A [Featherweight-HDL](https://github.com/featherweight-hdl) **protocol kit** that
bridges a clean, method-level API to the signal-level **UART line protocol**. Test,
model, and verification code calls blocking transfer methods on a SystemVerilog
`interface class`, while per-role transactors serialize and deserialize the real
serial line. A passive protocol checker enforces the line invariants, and a
back-to-back simulation test plus SymbiYosys formal proofs keep the kit honest.

```{admonition} Status
:class: tip
The kit builds green: the back-to-back simulation test (`uart-proto`) passes
(`[uart_proto] PASS`), the SymbiYosys BMC proof (`fv`) completes with
`DONE (PASS)`, and the cover-reachability proof (`fv-cover`, non-vacuity) reaches
every cover. The data-integrity proof is mutation-checked (a corrupted byte makes
the proof fail).
```

## What UART is, in one paragraph

UART is an **asynchronous serial line protocol**: there is no shared clock. A
transmitter (TX) serializes a character into a *frame* — a start bit (space),
5–8 data bits LSB-first, an optional parity bit, and 1–2 stop bits (mark) — driving
one bit per *bit period*. A receiver (RX) **oversamples** the line, finds the start
edge, samples each bit at its center, and recovers the character plus its line-error
status (parity / framing / break / overrun). The two directions are independent
simplex streams. The framing is **runtime-configurable** (baud divisor, word length,
parity, stop bits). See {doc}`uart-characterization` for the full analysis.

## The roles

Each role is a full transactor — a clocked signal-level **core**, a hand-coded
synthesizable **interface** (FIFOs + held config + blocking task API), a **wrapper**
module binding the two, and a plain-class **bridge** that connects the transactor to
the method API.

| Role | API it speaks | Drives / observes | Bridge role |
| --- | --- | --- | --- |
| **TX** | `uart_tx_if` — `send(data)` | serializes onto `txd` | provider (implements API) |
| **RX** | `uart_rx_if` — `recv(data, status)` | oversamples `rxd` | consumer (holds a sink, `start()`s) |
| **monitor** | `uart_monitor_if` — `observe(...)` | taps a line, drives nothing | consumer (holds a subscriber, `start()`s) |

UART's roles are **asymmetric one-way** streams (TX only sends, RX only receives;
there is no wire-level response), so unlike a request/response bus each role has its
own one-way API. All three roles also speak `uart_config_if` — `configure(...)` —
to set the runtime framing.

## Where to start

- New here? Read the {doc}`overview` for the design, then {doc}`getting-started`
  to build and run the demonstrators.
- Writing code against the kit? See the {doc}`api-reference`.
- Curious how it stays synthesizable and provable? See {doc}`verification` and
  {doc}`protocol-property-checking`.
- Want the protocol analysis the kit was built from? See {doc}`uart-characterization`.

```{toctree}
:maxdepth: 2
:caption: Guide

overview
getting-started
api-reference
verification
protocol-property-checking
uart-characterization
```
