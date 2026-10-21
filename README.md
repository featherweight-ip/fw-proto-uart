# fw-proto-uart: UART protocol kit

A Featherweight-HDL **protocol kit** that connects class-level transmit,
receive and monitor APIs to an asynchronous serial line (16550-style
framing). It follows the `fw-proto-kit` pattern, six elements per role, in
the same layout and conventions as `fw-proto-i2c` and `fw-proto-wb`.

**Status.** tx, rx and monitor roles, with framing configured at run time:
5 to 8 data bits, parity none, odd, even, stick 0 or stick 1, and 1, 1.5 or
2 stop bits. All three use one shared baud tick core (K2). Break is
supported both as a level and as a timed clean break, and the receiver
gives one BI character per break (K4). Error injection for the VIP side
covers bad parity, a bad stop bit, baud offset and glitches (K6). The
back-to-back sims pass at OVERSAMPLE 16 and 4. The formal BMC of the tx→rx
round trip, and of the tx and rx break rules, passes, and every cover goal
is reached; see
[`tests/formal/PROPERTIES.md`](tests/formal/PROPERTIES.md). Lint has zero
findings.

## Roles

| Role | Module | API | Bridge |
|---|---|---|---|
| tx | `uart_tx_xtor` | `uart_tx_if`: `send`, `set_break`, `send_break`; `uart_tx_inject_if`: `send_err`, `glitch` | `uart_tx_xtor_bridge`, implements them |
| rx | `uart_rx_xtor` | `uart_rx_if`: `recv(data, status)`, implemented by the host sink | `uart_rx_xtor_bridge`, holds the sink |
| monitor | `uart_monitor_xtor` | `uart_monitor_if`: `observe(data, status, is_tx)` | `uart_monitor_xtor_bridge`, holds the subscriber |

All three bridges also implement `uart_config_if.configure(divisor,
word_bits, parity_en, parity_even, parity_stick, stop_bits)`, which maps
onto 16550 DLL/DLM and LCR. Status is `{OE, BI, FE, PE}` in bits 3 to 0,
the order of LSR[4:1].

## Cores (`xtor-core`, synthesizable)

| Core | Does |
|---|---|
| `uart_baud_xtor_core` | `tick` once every `cfg_divisor` clocks. One instance can drive tx and rx together |
| `uart_tx_xtor_core` | Frames characters on `txd`, with every bit edge on a tick. Takes the `brk` level; reports `busy` (16550 TEMT) |
| `uart_rx_xtor_core` | One mid-bit sample per bit on ticks; PE, FE, BI, OE; waits for mark after a break |
| `uart_monitor_xtor_core` | The rx core on a tapped line |

The cores sample framing once per character (tx when it accepts a
character, rx at the start bit), so a change applies from the next
character. Each `uart_*_xtor` wrapper holds its own baud core for
standalone use. A design that wants one divider, as the 16550 has,
instantiates the cores directly.

Error injection (K6) is outside the cores. The tx transactor interface
drives injected frames clock by clock, through a mux in the `uart_tx_xtor`
wrapper, so a design that uses the cores carries no test logic.

## Layout

```
src/            uart_{tx,rx,monitor}_if.svh, uart_tx_inject_if.svh,
                uart_config_if.svh            (APIs)
                uart_{tx,rx,monitor}_bridge.svh
                uart_{tx,rx,monitor}_xtor_if.sv / _xtor_core.sv / _xtor.sv
                uart_baud_xtor_core.sv        (shared baud tick)
                uart_proto_checker.sv         (line invariants, export `checker`)
tests/          uart_proto_tb.sv              (back-to-back sim, all cases)
                uart_proto_os4_tb.sv, uart_proto_err_tb.sv
tests/formal/   uart_proto_fv.sv, uart_txbrk_fv.sv, uart_rxbrk_fv.sv
                PROPERTIES.md
tests/lint/     uart_lint_top.sv              (lint elaboration top)
skills/         fw-proto-uart/SKILL.md        (consumer guide)
```

## Build and run

`flow.yaml` builds on the `project.dv` archetype (dv-flow-libproject), so
the standard verbs apply. After `ivpm update` (dep-set `dev`):

```bash
dfm run tests        # uart-proto, uart-proto-os4, uart-proto-err
dfm run smoke        # the sims CI runs on every push
dfm run tests-info   # the case inventory, building nothing
dfm run lint-rtl     # Verilator lint of the cores and checker, zero findings
dfm run fv-quick     # formal BMC at per-push depth (~30 s)
dfm run fv           # formal BMC, nightly depth (~17 min)
dfm run fv-cover     # formal cover goals (non-vacuity)
```

`ci/run.sh` runs the same checks on either forge: push runs `smoke lint-rtl
fv-quick`, and nightly runs `tests lint-rtl fv fv-cover`.

## Consumers

`fw-uart16550` uses the cores (shared baud tick, break level, `busy`) under
its 16550 model, and `fwvip-uart` uses the transactors and the
error-injection API. Fetch this package with `dep-set: use`; see
[`skills/fw-proto-uart/SKILL.md`](skills/fw-proto-uart/SKILL.md).
