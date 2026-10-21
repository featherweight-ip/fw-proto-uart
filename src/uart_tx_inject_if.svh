// UART transmit error injection (K6). VIP-only: the frames are driven by
// the tx transactor interface, through an override on the line in the
// uart_tx_xtor wrapper, not by the synthesizable core (design D5). Each
// call waits for the transmitter to be idle and holds queued characters
// back until it is done. Implemented by uart_tx_xtor_bridge.
interface class uart_tx_inject_if;

    // One frame of `data` at the current framing, with errors:
    //   bad_parity  the parity bit inverted (no effect with parity off)
    //   bad_stop    the first stop bit driven as space (a framing error)
    //   baud_ppm    every bit lengthened by baud_ppm parts per million
    //               (negative: shortened); the error accumulates across
    //               the frame, as a real clock offset does
    //   glitch_at, glitch_len
    //               invert the line for glitch_len clocks, glitch_at
    //               clocks after the start-bit edge (glitch_len 0: none)
    // The frame is followed by one bit of mark, so a receiver that
    // resynchronized on a bad stop bit sees an idle line before the next
    // character.
    pure virtual task send_err(
            input bit [7:0]   data,
            input bit         bad_parity,
            input bit         bad_stop,
            input int         baud_ppm,
            input int unsigned glitch_at,
            input int unsigned glitch_len);

    // A pulse of space glitch_len clocks long on the idle line.
    pure virtual task glitch(input int unsigned glitch_len);

endclass
