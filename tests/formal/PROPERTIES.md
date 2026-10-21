# UART kit: invariant properties and checkers

The spec → invariant → checker map for the kit's three formal harnesses:

- `uart_proto_fv.sv`: the tx core drives the line into the rx core, and one
  `uart_baud_xtor_core` gives both their tick, as a 16550's single divisor
  does (K2). A free source feeds the tx core; a free sink drains the rx
  core.
- `uart_txbrk_fv.sv`: the tx core alone, with a free tick, a free break
  level, free framing and a free source (K2, K4).
- `uart_rxbrk_fv.sv`: the rx core alone, on a free line with a free tick
  (K4).

```
dfm run fv-quick    # BMC, per push: round trip at depth 32, txbrk 30, rxbrk 40 (~30 s)
dfm run fv          # BMC, nightly: round trip at depth 64 (~17 min), txbrk 30, rxbrk 40
dfm run fv-cover    # every cover goal of the three (~10 s)
```

## Harness shape

**Rate.** A frame at the real 16× rate is 160 or more clocks, far too deep
for BMC. The cores count bit time in ticks, so the round-trip harness runs
at `OVERSAMPLE = 2` with the divisor 1 or 2 (a frame is 14 to 24 ticks).
The shrink changes only the counter values. The sims run the same cores at
16 and 4.

**Configuration.** In the round trip, word length (5 to 8), parity mode
(none, odd, even, stick 0, stick 1), stop setting and divisor are all
`anyconst`, one value per trace. Both cores see the same values, so they
are baud-locked and framing-matched. The break harnesses take the framing
as free inputs (txbrk) or `anyconst` (rxbrk).

**Free tick.** In the two break harnesses the tick is a free input, so their
properties hold for any divisor, including a divisor that changes.

**Break is off in the round trip** (`brk = 0`): the break properties are
the txbrk and rxbrk harnesses'.

## The properties

| # | Spec / design rule | Invariant | Harness |
|---|---|---|---|
| 1 | Data integrity (the reason for the link) | The k-th character delivered is the k-th accepted, masked to the word length, with status 0. k is an `anyconst` index | proto |
| 2 | No spurious characters | A character is delivered only if one is in flight | proto |
| 3 | Link handshake | `req_ready` with `busy` only on a tick (the end of a stop bit, back to back) | proto |
| — | Line idles at mark in reset; every bit lasts a whole bit period | `uart_proto_checker` immediate asserts, with the stability check on | proto |
| 4 | Break (16550 LCR.BC) acts at once and holds characters back | `brk → !txd`, `brk → !req_ready` | txbrk |
| 5 | A receiver must see a break end | After a clean break (raised with the core idle), at least `OVERSAMPLE` ticks of mark before the next start bit | txbrk |
| 6 | Bit edges are tick-aligned (K2) | With `brk` steady, `txd` changes only the clock after a tick | txbrk |
| 7 | Handshake | `req_ready` with `busy` only on a tick | txbrk |
| 8 | BI character (16550 LSR[4]) | A character with BI is data 0 with FE = PE = 0 | rxbrk |
| 9 | One break, one character (16550: "waits for a valid start bit") | After a BI character, none completes until the line was mark on a tick | rxbrk |
| 10 | Status consistency | Bits above the word length are 0; PE only with parity on; no OE when the sink always takes | rxbrk |

Property 5 is for a clean break. A break raised over a character already
accepted loses that character, as on a 16550, and the rest of the frame can
follow the break at once. The core's header says so, and `send_break()`
always raises a clean one.

## Cover goals (non-vacuity)

| Harness | Goals | Reached by step |
|---|---|---|
| proto | the tracked character delivered; a second character delivered; the checker's start edge, return to mark, full-period transition | 31 |
| txbrk | a start bit after a clean break; `brk` raised over a busy core | 8 |
| rxbrk | a BI character; a character after a BI character; an FE character; a PE character | 31 |

The round trip's first character arrives at step 17 (5-bit, no parity,
divisor 1) and its second at step 31, so `fv-quick` at depth 32 checks
properties 1 to 3 on one or two characters of the shortest framings. `fv`
at depth 64 reaches characters at divisor 2 and two 8-bit characters at
divisor 1.

## Teeth

Each mutation below was put into a copy of the kit, and `uart-proto` and
`fv-quick` were run on it:

| Mutation | Caught by |
|---|---|
| rx core does not wait for mark after a break | sim (`break`, `set_break`: extra BI characters); rxbrk property 9 |
| tx core owes no mark after a break (`BRK_MARK = 0`) | sim (checker: a bit of 3 clocks); txbrk property 5 |
| tx core cannot accept on the last stop tick (a gap between frames) | sim (`timing`: period 3 clocks long at divisor 3) |
| rx parity: odd computed as even | sim (every odd-parity sweep: PE); proto property 1 |

The back-to-back gap is a timing property, which is checked only in the
sims.

## What is not proved

- **Error injection (K6)** is in the transactor interface, which is not
  synthesizable. The sims check it (`uart-proto-err`, `uart-proto-os4`).
- **Overrun** of the rx core's single-entry output: the sims check it
  (`overrun`). In the round trip the sink is bounded-fair.
- **Configuration changes** between characters (K1 latching) are not
  driven in the round trip, where the configuration is `anyconst`.
