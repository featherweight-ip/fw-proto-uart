// UART protocol kit -- class layer. The transactor SV interfaces and modules
// (uart_*_xtor*.sv) are separate compilation units (an interface/module cannot live
// in a package); they are listed alongside this file in the FileSet.
//
// The APIs are one-way and fixed-width (the character carrier is a fixed [7:0]; the
// active word length is a runtime config, not a type parameter -- design O-4):
//   * uart_tx_if      -- transmit (provider: the TX bridge IMPLEMENTS send()).
//   * uart_rx_if      -- receive  (a host sink IMPLEMENTS recv(); the RX bridge
//                        HOLDS it and drives it from a start()-forked run() loop).
//   * uart_monitor_if -- observe  (a subscriber IMPLEMENTS the non-blocking
//                        observe(); the monitor bridge HOLDS it and drives it).
//   * uart_config_if  -- runtime framing config (each role's bridge IMPLEMENTS
//                        configure() and forwards it to the transactor interface).
package fw_proto_uart_pkg;

    // API interface-classes.
    `include "uart_tx_if.svh"
    `include "uart_rx_if.svh"
    `include "uart_monitor_if.svh"
    `include "uart_config_if.svh"

    // Transactor bridges -- hold a virtual transactor-interface and implement (or
    // drive) the API. They reference the transactor SV interfaces by their
    // (unmangled) names, so those interfaces must be compiled in the same image.
    `include "uart_tx_xtor_bridge.svh"
    `include "uart_rx_xtor_bridge.svh"
    `include "uart_monitor_xtor_bridge.svh"

endpackage
