// UART protocol kit -- class layer. The transactor SV interfaces and modules
// (uart_*_xtor*.sv) are separate compilation units (an interface or module
// cannot live in a package); they are listed alongside this file in the
// FileSet (src/flow.yaml).
//
// Like fw-proto-i2c and fw-proto-wb, the bridges implement the interface
// classes directly (plain `implements`), without the fw-hdl fw_export
// macros. The character carrier is a fixed 8 bits; the word length is run
// time configuration (uart_config_if).
`include "uart_xtor_macros.svh"

package fw_proto_uart_pkg;
    // API interface classes.
    `include "uart_config_if.svh"
    `include "uart_tx_if.svh"
    `include "uart_tx_inject_if.svh"
    `include "uart_rx_if.svh"
    `include "uart_monitor_if.svh"

    // Transactor bridges. They reference the transactor SV interfaces by
    // name, so those must be compiled in the same image.
    `include "uart_tx_bridge.svh"
    `include "uart_rx_bridge.svh"
    `include "uart_monitor_bridge.svh"

endpackage
