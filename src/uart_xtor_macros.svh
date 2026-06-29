
`ifndef INCLUDED_UART_XTOR_MACROS_SVH
`define INCLUDED_UART_XTOR_MACROS_SVH

// ----------------------------------------------------------------------
// Packed struct templates for the signal-level UART transactor cores and
// interfaces. UART carries two INDEPENDENT one-way data streams (TX and RX),
// so unlike a request/response bus there is no shared transfer payload:
//   * TX request  -- the character to serialize onto the line
//   * RX response -- the deframed character plus its line-error status
//
// The character carrier is fixed at the MAX_DATA_BITS maximum (8) regardless of the
// runtime-configured word length; the active `word_bits` (5..8) selects how many
// low bits are significant (design O-4). The wire/struct width never changes with
// configuration -- only the significant-bit count does.
//
// Runtime framing configuration (divisor / word_bits / parity / stop) is NOT a
// streamed payload: it is a held level driven into the cores as discrete cfg_*
// ports (set via the transactor interface's configure() task), so it is not
// represented as a packed struct here.
// ----------------------------------------------------------------------

// TX request: one character to transmit (low cfg_word_bits significant).
`define UART_TX_REQ_S(MAX_DATA_BITS) \
    struct packed { \
        bit [MAX_DATA_BITS-1:0] data; \
    }

// RX response: one deframed character + its line-error status. The status nibble
// is {overrun, brk, framing_err, parity_err} -- i.e. parity_err is bit[0],
// framing_err bit[1], brk bit[2], overrun bit[3], matching the LSR-aligned
// assignment in docs/uart-characterization.md (§8).
`define UART_RX_RSP_S(MAX_DATA_BITS) \
    struct packed { \
        bit [MAX_DATA_BITS-1:0] data; \
        bit                 overrun;     /* status[3] -- OE: char lost, FIFO full */ \
        bit                 brk;         /* status[2] -- BI: full-frame space      */ \
        bit                 framing_err; /* status[1] -- FE: stop bit not mark     */ \
        bit                 parity_err;  /* status[0] -- PE: parity mismatch       */ \
    }

`endif /* INCLUDED_UART_XTOR_MACROS_SVH */
