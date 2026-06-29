// UART monitor API -- receive one deframed character the passive monitor observed
// on a tapped line. observe() is a FUNCTION (non-blocking) -- monitor APIs may not
// block. Implemented by a subscriber; the monitor transactor bridge
// (uart_monitor_xtor_bridge) calls it for each observed character.
//
//   data   : the observed deframed character (low word_bits significant).
//   status : line-error nibble {overrun, brk, framing_err, parity_err}
//            = { [3]=OE, [2]=BI, [1]=FE, [0]=PE } (§8/§9).
//   is_tx  : which line was tapped -- 1 if the transmit line (STX), 0 if the
//            receive line (SRX). Set by the monitor instance, not detected.
interface class uart_monitor_if;

    // Publish one observed character to the subscriber (non-blocking).
    pure virtual function void observe(
            input [7:0] data,
            input [3:0] status,
            input       is_tx);

endclass
