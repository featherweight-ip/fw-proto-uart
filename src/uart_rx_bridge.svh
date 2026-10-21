// Receive transactor bridge, the consumer side. Holds the signal-level
// transactor interface (uart_rx_xtor_if) and the host sink that implements
// uart_rx_if. start_bridge() forks run(): wait for each deframed character
// and hand it to the sink. Also implements uart_config_if.
class uart_rx_xtor_bridge implements uart_config_if;

    virtual uart_rx_xtor_if vif;
    uart_rx_if              sink;

    function new(virtual uart_rx_xtor_if vif, uart_rx_if sink);
        this.vif  = vif;
        this.sink = sink;
    endfunction

    task start_bridge();
        fork
            run();
        join_none
    endtask

    task run();
        bit [7:0] data;
        bit [3:0] status;
        forever begin
            vif.recv(data, status);
            sink.recv(data, status);
        end
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
