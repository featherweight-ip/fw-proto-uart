// UART transmit API (initiator). UART's two directions are independent
// one-way streams with no response on the wire, so transmit has its own
// API. Implemented by uart_tx_xtor_bridge.
interface class uart_tx_if;

    // Queue one character. Blocks until the transactor accepts it; the
    // frame then goes out on the line. The low cfg word_bits (5..8) are
    // sent; the bits above are ignored.
    pure virtual task send(input bit [7:0] data);

    // Break as a level (16550 LCR.BC, K4). on=1 drives the line to space at
    // once and holds back further characters; on=0 releases it. A character
    // already on the line when on=1 is lost, as in a 16550.
    pure virtual task set_break(input bit on);

    // A clean break of n_chars character times (at the current framing):
    // waits for everything queued to go out, drives space, then releases.
    // After any break the core holds mark for one bit before the next
    // character starts.
    pure virtual task send_break(input int unsigned n_chars);

endclass
