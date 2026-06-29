// UART receive API -- delivery of one deframed character (target archetype).
// The RX side is a one-way consumer: the receiver deframes a character off the
// serial line and delivers it, with its line-error status, to a host sink.
//
// CONSUMER wiring (design O-2, push primary): a host SINK implements uart_rx_if;
// the uart_rx_xtor_bridge HOLDS that sink handle and start()-forks a run() loop that
// pops each deframed character off the transactor interface and DELIVERS it to the
// sink by calling recv() -- so here `data`/`status` are INPUTS to the sink. recv() is
// a TASK so the sink may apply backpressure to the delivery path (it cannot
// backpressure the wire -- overrun drops data). For simple pull-style tests, the
// transactor interface also offers its own blocking recv(output ...) to pull
// characters directly.
//
//   data   : the deframed character (low cfg_word_bits significant; upper bits 0).
//   status : line-error nibble {overrun, brk, framing_err, parity_err}
//            = { [3]=OE, [2]=BI, [1]=FE, [0]=PE } (LSR-aligned; §8/§9).
interface class uart_rx_if;

    // Receive one deframed character + its line-error status (called by the bridge).
    pure virtual task recv(input [7:0] data, input [3:0] status);

endclass
