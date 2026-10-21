// UART monitor API: one deframed character the passive monitor observed on
// a tapped line. A function: monitor APIs do not block. Implemented by a
// subscriber; uart_monitor_xtor_bridge calls it.
//
//   data   : the character (low word_bits significant)
//   status : {OE, BI, FE, PE}, as uart_rx_if
//   is_tx  : the line tapped: 1 = the transmit line, 0 = the receive line.
//            Set on the monitor bridge, not detected
interface class uart_monitor_if;

    pure virtual function void observe(
            input bit [7:0] data,
            input bit [3:0] status,
            input bit       is_tx);

endclass
