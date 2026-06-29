# Verification

The kit ships two complementary proofs of correctness: a **back-to-back simulation**
test that exercises the full stack, and a **back-to-back formal** proof of the
synthesizable cores. A passive protocol checker runs in both.

## Back-to-back simulation (`uart-proto`)

`tests/uart_proto_tb.sv` wires a full TX transactor to a full RX transactor over one
shared line, taps a monitor, and instantiates the checker (with `UART_PROTO_SVA`
defined so the concurrent-SVA layer also runs). It proves end-to-end character
integrity across framings, the full line-error taxonomy (parity / framing / break /
overrun), and monitor observation, through the real FIFO + bridge + class-API stack.

```bash
dfm run fw.proto.uart.uart-proto      # expect: [uart_proto] PASS
```

This is the layer the formal proof cannot reach: the FIFO depth/ordering, the
bridge `run()` loops, the blocking `send`/`recv` semantics, and the held-config path.

## Back-to-back formal (`fv`, `fv-cover`)

`tests/formal/uart_proto_fv.sv` wires the two **cores** — `uart_tx_xtor_core` and
`uart_rx_xtor_core` — directly together over the serial line, free-drives the TX
character stream, freely drains the RX up-link, and instantiates the checker. It adds
the property the checker can't see: **end-to-end data integrity** via an `anyconst`
tracked position — the `f_idx`-th character the receiver delivers equals the `f_idx`-th
the transmitter accepted, with clean status.

```bash
dfm run fw.proto.uart.fv          # BMC of all asserts   -> DONE (PASS)
dfm run fw.proto.uart.fv-cover    # cover reachability   -> DONE (PASS)
```

### The depth problem and how it's handled

A character crosses in `frame_bits × OVERSAMPLE × divisor` cycles — over 160 at the
real 16× rate, far too deep for an end-to-end BMC. The formal harness therefore runs
at a **shrunk rate**: `OVERSAMPLE=2`, `divisor=1` (bit period = 2 cycles, a frame ~24
cycles), and ties the framing config to constants so both cores are baud-locked. BMC
depth 48 lets a character fully traverse and the integrity tracker fire.

### Non-vacuity and teeth

A green BMC (asserts hold) **and** a green Cover (every `cover()` reachable — including
the end-to-end traversal of a tracked character) together rule out a vacuous proof. The
proof is also **mutation-checked**: corrupting a delivered data bit in the RX core makes
the BMC fail, confirming the data-integrity assert has teeth.

### Toolchain note

The bundled yosys cannot read SV structs/packages, so the cores + harness are flattened
to plain Verilog by `sv2v --exclude=Assert -DFORMAL` before SymbiYosys reads them.
`--exclude=Assert` is **mandatory** — without it sv2v silently strips every assertion and
the proof passes vacuously.

## The protocol checker

`uart_proto_checker.sv` is a passive module (line + config inputs only) that can be
bound to any UART line. It enforces the line invariants in two layers — a synthesizable
immediate-assert layer (always on, read directly by yosys and any simulator) and a
concurrent-SVA layer (`UART_PROTO_SVA`, richer sim checks). See
{doc}`protocol-property-checking` for the rule-by-rule catalogue.
