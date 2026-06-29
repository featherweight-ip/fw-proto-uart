# Protocol property checking

`uart_proto_checker.sv` is the kit's passive, reusable protocol-invariant checker. It
takes only inputs — the serial `line` and the active framing `cfg_*` — so it can be
instantiated or bound on any UART line tap: in the formal harness, the simulation
testbench, or alongside real RTL.

## What is a wire invariant — and what is not

A corrupted frame (bad parity, a missing stop bit, a break) is **protocol-legal on the
wire**: the *receiver* detects it and reports status. It is not a transmitter violation,
so the checker does **not** assert framing correctness. The true transmitter-side line
invariants are:

1. **Reset / idle (§5.1).** While in reset the line is held at **mark** (the idle level).
2. **Bit-period stability (§5.1).** The line is driven **stable for a whole bit period** —
   equivalently, two line transitions are never closer than one bit period
   (`OVERSAMPLE × cfg_divisor` cycles). This is the UART analog of a handshake
   "hold-until-accepted" rule and the single most valuable always-on line check. The
   first transition out of post-reset idle is exempt (idle has no minimum duration).

There is no response/qualifier *dependency* rule (UART has no wire handshake) and no
ordering/ID rule (one self-framed character per direction), so those checks — central to
a pipelined bus — simply do not apply here.

## Two-layer encoding

Each rule is emitted twice, with one source of truth per layer:

- **Synthesizable immediate-assert layer (always on).** Single-edge
  `always @(posedge clock)` with manually-registered history (a dwell counter; no
  `$past`). yosys/SymbiYosys read these directly after `sv2v --exclude=Assert`, and they
  also run in simulation. This is the authoritative form — it enforces the exact
  bit-period dwell bound.
- **Concurrent-SVA layer (sim).** Gated by `` `ifdef UART_PROTO_SVA ``: a reset-mark
  property and a value-domain (`$isunknown`) X-check on the line. The bit-period
  stability rule is intentionally **not** duplicated in SVA — SVA samples the
  combinational line in the preponed region, which disagrees with the clocked dwell
  counter for asynchronously-driven sim stimulus (e.g. a bit-banged test frame); the
  immediate layer covers it exactly.

## Non-vacuity covers

The checker ships `cover`s for a start edge (idle→space), a return to mark, and a
full-bit-period transition, so a green proof or sim run is demonstrably not vacuous.
`CHECK_STABILITY` (default on) lets a consumer disable the dwell check — the formal
harness disables it because at the shrunk bit period (2 cycles) it is near-vacuous, and
it is meaningfully exercised in the sim testbench at the real oversampled rate.

## Receiver-detected errors

The error taxonomy (parity / framing / break / overrun) is **not** in the checker — it is
produced by the RX/monitor cores and surfaced in the delivered `status` nibble, then
checked by the simulation testbench against the injected stimulus. See {doc}`verification`.
