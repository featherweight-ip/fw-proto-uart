// Transmit transactor bridge -- the PROVIDER side. Holds a handle to the signal-
// level transactor interface (uart_tx_xtor_if) and IMPLEMENTS both the transmit API
// (uart_tx_if) and the runtime-config API (uart_config_if). send() enqueues a
// character; configure() updates the held framing config. A driver holds this bridge
// as a uart_tx_if (and/or uart_config_if) handle.
class uart_tx_xtor_bridge implements uart_tx_if, uart_config_if;

    virtual uart_tx_xtor_if vif;

    function new(virtual uart_tx_xtor_if vif);
        this.vif = vif;
    endfunction

    // The transmitter is call-driven (send() pushes inline), so nothing to start.
    task start();
    endtask

    // uart_tx_if: enqueue one character for transmission.
    virtual task send(input [7:0] data);
        vif.send(data);
    endtask

    // uart_config_if: set the held framing configuration.
    virtual task configure(
            input [15:0] divisor,
            input [3:0]  word_bits,
            input        parity_en,
            input        parity_even,
            input        parity_stick,
            input [1:0]  stop_bits);
        vif.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
    endtask
endclass
