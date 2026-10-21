# API reference

The APIs are `interface class`es in `fw_proto_uart_pkg`. The character
carrier is a fixed 8 bits; the word length is run-time configuration.

## `uart_tx_if`: transmit (provider)

```systemverilog
interface class uart_tx_if;
    pure virtual task send(input bit [7:0] data);
    pure virtual task set_break(input bit on);
    pure virtual task send_break(input int unsigned n_chars);
endclass
```

- `send()` queues one character. It blocks until the transactor's FIFO
  takes it; the frame then goes out on `txd`. The low `word_bits` are sent.
- `set_break(on)` is the break level, 16550 LCR.BC. The line goes to space
  at once, and characters queued meanwhile wait until it is released. A
  character already on the line is lost, as on a 16550.
- `send_break(n_chars)` waits for everything queued to go out, then drives
  space for `n_chars` character times at the current framing.

After any break the core holds mark for one bit before the next start bit.

## `uart_tx_inject_if`: error injection (provider, VIP only)

```systemverilog
interface class uart_tx_inject_if;
    pure virtual task send_err(
            input bit [7:0]    data,
            input bit          bad_parity,
            input bit          bad_stop,
            input int          baud_ppm,
            input int unsigned glitch_at,
            input int unsigned glitch_len);
    pure virtual task glitch(input int unsigned glitch_len);
endclass
```

- `send_err()` sends one frame at the current framing, driven by the
  transactor interface rather than the core:
  - `bad_parity` inverts the parity bit (no effect with parity off);
  - `bad_stop` makes the first stop bit space;
  - `baud_ppm` makes every bit longer by that many parts per million
    (negative: shorter), accumulating across the frame;
  - `glitch_len` clocks of inverted line start `glitch_at` clocks after the
    start edge (`glitch_len` 0: none).

  One bit of mark follows the frame.
- `glitch()` drives a pulse of space on the idle line.

Both wait for the line to be idle and hold queued characters back while
they run, so calls from one thread keep their order.

## `uart_rx_if`: receive (host sink)

```systemverilog
interface class uart_rx_if;
    pure virtual task recv(input bit [7:0] data, input bit [3:0] status);
endclass
```

A host sink implements it. `uart_rx_xtor_bridge` holds the sink and calls
`recv()` for each character, from the loop that `start_bridge()` forks.
`recv()` is a task, so the sink can hold up delivery; it cannot hold up
the line, so a slow sink loses characters (OE). The transactor interface
also has its own blocking `recv(output data, output status)` for pull-style
use.

## `uart_monitor_if`: observe (subscriber)

```systemverilog
interface class uart_monitor_if;
    pure virtual function void observe(input bit [7:0] data, input bit [3:0] status,
                                       input bit is_tx);
endclass
```

A function: monitors do not block. `is_tx` is set on the bridge (1: the
monitor taps the transmit line, 0: the receive line).

## `uart_config_if`: framing

```systemverilog
interface class uart_config_if;
    pure virtual task configure(
            input bit [15:0] divisor,
            input bit [3:0]  word_bits,
            input bit        parity_en,
            input bit        parity_even,
            input bit        parity_stick,
            input bit [1:0]  stop_bits);
endclass
```

Implemented by all three bridges. The values are held levels, sampled once
per character, so a change applies from the next character. See
{doc}`getting-started` for the argument table.

## Status

`status` is `{OE, BI, FE, PE}`, the order of 16550 LSR[4:1]:

| Bit | Name | Meaning |
| --- | --- | --- |
| 0 | PE | the parity bit does not match (parity on) |
| 1 | FE | the first stop bit is space |
| 2 | BI | the whole frame was space; data is 0, FE and PE are 0; one per break |
| 3 | OE | characters were lost before this one: the core's single-entry output was still full |

A clean character has status 0.

## Bridges

| Bridge | Constructor | Implements or holds |
| --- | --- | --- |
| `uart_tx_xtor_bridge` | `new(vif)` | implements `uart_tx_if`, `uart_tx_inject_if`, `uart_config_if` |
| `uart_rx_xtor_bridge` | `new(vif, sink)` | holds a `uart_rx_if`; implements `uart_config_if`; `start_bridge()` |
| `uart_monitor_xtor_bridge` | `new(vif, subscriber, is_tx = 0)` | holds a `uart_monitor_if`; implements `uart_config_if`; `start_bridge()` |

`vif` is the wrapper's `u_if` (`u_tx.u_if` and so on). The bridges take the
interfaces at their default parameters.

## Cores (`xtor-core`)

| Core | Ports besides `clock`, `reset` |
| --- | --- |
| `uart_baud_xtor_core #(DIV_WIDTH)` | `cfg_divisor` in; `tick` out |
| `uart_tx_xtor_core #(MAX_DATA_BITS, OVERSAMPLE)` | `tick`, `brk`, `cfg_word_bits`, `cfg_parity_en/even/stick`, `cfg_stop_bits`, `req_dat/valid` in; `txd`, `busy`, `req_ready` out |
| `uart_rx_xtor_core #(MAX_DATA_BITS, OVERSAMPLE)` | `tick`, `rxd`, `cfg_word_bits`, `cfg_parity_en/even/stick`, `rsp_ready` in; `rsp_dat` (`{data, OE, BI, FE, PE}`), `rsp_valid` out |
| `uart_monitor_xtor_core` | as rx, with `line` and `mon_*` |

The cores reset asynchronously. `busy` is 1 while a character is in the tx
core. `req_ready` and `busy` are both 1 only on the tick that ends a stop
bit.
