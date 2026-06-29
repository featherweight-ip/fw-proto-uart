// UART runtime-configuration API.
//
// UART framing is runtime-configurable -- the distinctive trait of the protocol.
// The configurable attributes (baud divisor, word length, parity mode, stop bits)
// are exposed through this interface class. Each role's transactor bridge
// IMPLEMENTS uart_config_if and forwards configure() to its transactor interface's
// configure() task, which latches the values into the held cfg_* level driven into
// the core (see docs/uart-characterization.md §7). TX, RX and a monitor that taps a
// line must all be configured consistently to interoperate.
//
// Configuration is a held LEVEL, not a per-character event: the core samples the
// current cfg_* when it starts (TX) or detects the start bit of (RX) a frame.
// Static, build-time attributes (oversample factor, FIFO depth, max word width)
// stay as module parameters.
//
//   divisor      : baud divider. One bit period = OVERSAMPLE*divisor system clocks
//                  (§4.9). divisor == 0 disables serial I/O (the core idles).
//   word_bits    : data bits per character, 5..8 (§4.5 bit 1-0).
//   parity_en    : 1 = a parity bit is generated/checked (§4.5 bit 3).
//   parity_even  : 1 = even parity, 0 = odd parity (§4.5 bit 4).
//   parity_stick : 1 = stick parity -- the parity bit is forced (and checked) to a
//                  fixed level: 0 when parity_even, 1 when odd (§4.5 bit 5).
//   stop_bits    : 0 => 1 stop bit; 1 => 1.5 (5-bit char) / 2 stop bits (§4.5 bit 2).
interface class uart_config_if;

    pure virtual task configure(
            input [15:0] divisor,
            input [3:0]  word_bits,
            input        parity_en,
            input        parity_even,
            input        parity_stick,
            input [1:0]  stop_bits);

endclass
