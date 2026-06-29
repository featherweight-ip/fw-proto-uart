# API reference

All APIs are SystemVerilog `interface class`es in `fw_proto_uart_pkg`. The character
carrier is a fixed `[7:0]`; the active word length is a runtime configuration, not a
type parameter.

## `uart_tx_if` — transmit (provider)

```systemverilog
interface class uart_tx_if;
    pure virtual task send(input [7:0] data);
endclass
```

Enqueue one character for transmission. `send()` blocks only until the character is
accepted into the TX FIFO (caller-side pipelining); the frame then shifts out on `txd`.
The low `word_bits` of `data` are significant. **Implemented by** `uart_tx_xtor_bridge`
(the provider); a driver calls it.

## `uart_rx_if` — receive (host sink)

```systemverilog
interface class uart_rx_if;
    pure virtual task recv(input [7:0] data, input [3:0] status);
endclass
```

Receive one deframed character and its line-error status. A **host sink implements**
this; the `uart_rx_xtor_bridge` holds the sink and calls `recv()` from a `run()` loop
forked in `start()` — so `data`/`status` are *inputs to the sink*. `recv()` is a task so
the sink may backpressure the delivery path (it cannot backpressure the wire — overrun
drops data). For pull-style use, the transactor interface also offers its own blocking
`recv(output data, output status)`.

## `uart_monitor_if` — observe (subscriber)

```systemverilog
interface class uart_monitor_if;
    pure virtual function void observe(input [7:0] data, input [3:0] status, input is_tx);
endclass
```

Publish one observed character. `observe()` is a **function** (non-blocking — monitor
APIs may not block). A subscriber implements it; the `uart_monitor_xtor_bridge` holds the
subscriber and calls it for each deframed character. `is_tx` (fixed at construction) tells
the subscriber which line this monitor taps (`1` = STX, `0` = SRX).

## `uart_config_if` — runtime framing configuration

```systemverilog
interface class uart_config_if;
    pure virtual task configure(
        input [15:0] divisor,
        input [3:0]  word_bits,
        input        parity_en,
        input        parity_even,
        input        parity_stick,
        input [1:0]  stop_bits);
endclass
```

Set the held framing. Implemented by **all three role bridges** (each forwards to its
transactor interface). Configuration is a held level sampled at frame start; configure
before transmitting/receiving. See {doc}`getting-started` for the argument table.

## The status nibble

`recv()` / `observe()` deliver a 4-bit `status` = `{overrun, brk, framing_err, parity_err}`:

| Bit | Name | Meaning |
| --- | --- | --- |
| `[0]` | `parity_err` (PE) | received parity ≠ computed parity (when parity enabled) |
| `[1]` | `framing_err` (FE) | the first stop bit was sampled as space, not mark |
| `[2]` | `brk` (BI) | a full-frame space (break); the delivered character is `0` |
| `[3]` | `overrun` (OE) | a completed character was dropped because the FIFO was full |

A clean character has `status == 4'h0`.

## Bridges (plain classes)

| Bridge | Constructor | Implements / holds |
| --- | --- | --- |
| `uart_tx_xtor_bridge` | `new(vif)` | implements `uart_tx_if`, `uart_config_if` |
| `uart_rx_xtor_bridge` | `new(vif, sink)` | holds `uart_rx_if` sink; implements `uart_config_if`; `start()` forks `run()` |
| `uart_monitor_xtor_bridge` | `new(vif, subscriber, is_tx)` | holds `uart_monitor_if`; implements `uart_config_if`; `start()` forks `run()` |

Bridges are handle-wired plain classes — no component/port/export framework.
