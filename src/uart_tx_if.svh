// UART transmit API -- the one-way TRANSMIT operation (initiator archetype).
// UART's TX and RX are asymmetric simplex streams with no wire-level response, so
// the transmit side has its own one-way API (there is no unified transfer API; see
// docs/uart-characterization.md §2/§8).
//
// PROVIDER: the uart_tx_xtor_bridge IMPLEMENTS send(); a driver calls it to enqueue
// one character. send() blocks only until the character is accepted into the TX
// FIFO (caller-side pipelining); the frame then shifts out on the serial line.
//
//   data : the character to transmit. Carried as MAX_DATA_BITS (8); the low
//          cfg_word_bits (5..8) are significant -- the upper bits are ignored by
//          the serializer (design O-4).
interface class uart_tx_if;

    // Enqueue one character for transmission (blocking until accepted).
    pure virtual task send(input [7:0] data);

endclass
