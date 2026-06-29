// Receive transactor bridge -- the CONSUMER side. Holds a handle to the signal-level
// transactor interface (uart_rx_xtor_if) AND a handle to the host SINK that
// implements uart_rx_if. start() forks the run() service loop: block for each
// deframed character, then push it to the sink (design O-2, push primary). Also
// IMPLEMENTS uart_config_if so the RX framing can be configured through the same
// API surface as the other roles.
class uart_rx_xtor_bridge implements uart_config_if;

    virtual uart_rx_xtor_if vif;
    uart_rx_if              sink;     // host consumer of deframed characters

    function new(virtual uart_rx_xtor_if vif, uart_rx_if sink);
        this.vif  = vif;
        this.sink = sink;
    endfunction

    // Launch the delivery loop as a background thread.
    task start();
        fork
            run();
        join_none
    endtask

    // Deliver each deframed character to the sink.
    task run();
        forever begin
            automatic logic [7:0] data;
            automatic logic [3:0] status;
            vif.recv(data, status);          // blocking: next deframed character
            sink.recv(data, status);         // hand it to the host sink
        end
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
