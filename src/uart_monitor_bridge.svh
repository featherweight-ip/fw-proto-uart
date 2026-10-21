// Monitor transactor bridge, the consumer side. Holds the signal-level
// transactor interface (uart_monitor_xtor_if) and the subscriber that
// implements uart_monitor_if. start_bridge() forks run(): wait for each
// observed character and publish it through the non-blocking observe().
// is_tx (the line tapped) is fixed at construction. Also implements
// uart_config_if, to match the monitor to the tapped link.
class uart_monitor_xtor_bridge implements uart_config_if;

    virtual uart_monitor_xtor_if vif;
    uart_monitor_if              subscriber;
    bit                          is_tx;

    function new(virtual uart_monitor_xtor_if vif, uart_monitor_if subscriber,
                 bit is_tx = 1'b0);
        this.vif        = vif;
        this.subscriber = subscriber;
        this.is_tx      = is_tx;
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
            vif.wait_char(data, status);
            subscriber.observe(data, status, is_tx);
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
