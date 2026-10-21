// UART receive API (target). The rx bridge holds a host sink that
// implements this, and calls recv() for each character the receiver
// deframes, so `data` and `status` are inputs to the sink. recv() is a
// task so the sink can apply backpressure to the delivery path; it cannot
// backpressure the line, so a slow sink loses characters (OE).
//
//   data   : the character, low word_bits significant, upper bits 0
//   status : {OE, BI, FE, PE} = bits {3, 2, 1, 0}, LSR-aligned
//            (uart_xtor_macros.svh)
interface class uart_rx_if;

    pure virtual task recv(input bit [7:0] data, input bit [3:0] status);

endclass
