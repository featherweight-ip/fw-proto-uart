# Verification

Back-to-back sims check the whole stack, formal proofs check the cores,
and `uart_proto_checker` runs in both.

## Simulation (K9)

`tests/uart_proto_tb.sv` drives a tx transactor into an rx transactor over
one line, with a monitor on the line. Every character the sink receives is
checked against what was sent, and the monitor must report the same
character and status as the receiver. The checker watches the tx core's
output, and the image defines `UART_PROTO_SVA`, so its concurrent layer
runs too.

| Case | OVERSAMPLE | Checks |
| --- | --- | --- |
| `uart-proto` | 16 | 11 framings (5 to 8 bits; parity none, odd, even, stick 0, stick 1; 1, 1.5, 2 stop) at divisors 1, 2, 3, back to back; start-bit width and character period exact to the clock; parity mismatch; `send_break` of 1 and 3 characters (one BI each); the `set_break` level with a character waiting behind it; overrun; divisor 0 |
| `uart-proto-err` | 16 | error injection (K6): bad parity, bad stop, both; a bad stop followed by a frame at +3%; order kept around injected frames; ±3% baud received clean; ±8% must not be; an idle glitch of 3/8 bit rejected; a glitch over the middle of a data bit flips it, one off the middle does not |
| `uart-proto-os4` | 4 | both groups |

```bash
dfm run tests      # all three; `smoke` is the same set
```

## Formal

Three harnesses in `tests/formal`, each through `sv2v --exclude=Assert
-DFORMAL` and SymbiYosys:

- `uart_proto_fv`: tx core → line → rx core on one shared baud tick, with
  any framing and divisor 1 or 2 (`anyconst`), at `OVERSAMPLE = 2`. It
  checks data integrity of the k-th character, no spurious characters, the
  handshake, and the checker's line rules.
- `uart_txbrk_fv`: the tx core with a free tick and a free break level.
  Break gives space at once and holds characters back; a clean break is
  followed by a bit of mark; bit edges fall on ticks.
- `uart_rxbrk_fv`: the rx core on a free line. A BI character is data 0
  with BI alone; one break gives one character; status is consistent.

The property table, depths, cover goals and the mutation checks are in
`tests/formal/PROPERTIES.md`.

```bash
dfm run fv-quick   # per push
dfm run fv         # nightly
dfm run fv-cover   # every cover goal reached
```

`--exclude=Assert` is required: without it sv2v drops every immediate
assert, assume and cover, and the proof passes vacuously.

## Teeth

Four mutations were each put into a copy of the kit (no mark wait in rx,
no post-break mark in tx, a gap between frames, odd parity computed as
even). Each one fails a sim, a proof, or both (PROPERTIES.md, "Teeth").

## CI

`ci/run.sh` runs the checks on either forge (`.github`, `.forgejo`): push
runs `smoke lint-rtl fv-quick`; nightly runs `tests lint-rtl fv fv-cover`.
