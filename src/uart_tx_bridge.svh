// Transmit transactor bridge, the provider side. Holds the signal-level
// transactor interface (uart_tx_xtor_if) and implements the transmit,
// error-injection and configuration APIs on it directly.
class uart_tx_xtor_bridge implements uart_tx_if, uart_tx_inject_if, uart_config_if;

    virtual uart_tx_xtor_if vif;

    function new(virtual uart_tx_xtor_if vif);
        this.vif = vif;
    endfunction

    // Call-driven: nothing to start in the background.
    task start_bridge();
    endtask

    virtual task send(input bit [7:0] data);
        vif.send(data);
    endtask

    virtual task set_break(input bit on);
        vif.set_break(on);
    endtask

    virtual task send_break(input int unsigned n_chars);
        vif.send_break(n_chars);
    endtask

    virtual task send_err(
            input bit [7:0]   data,
            input bit         bad_parity,
            input bit         bad_stop,
            input int         baud_ppm,
            input int unsigned glitch_at,
            input int unsigned glitch_len);
        vif.send_err(data, bad_parity, bad_stop, baud_ppm, glitch_at, glitch_len);
    endtask

    virtual task glitch(input int unsigned glitch_len);
        vif.glitch(glitch_len);
    endtask

    virtual task configure(
            input bit [15:0] divisor,
            input bit [3:0]  word_bits,
            input bit        parity_en,
            input bit        parity_even,
            input bit        parity_stick,
            input bit [1:0]  stop_bits);
        vif.configure(divisor, word_bits, parity_en, parity_even, parity_stick, stop_bits);
    endtask

endclass
