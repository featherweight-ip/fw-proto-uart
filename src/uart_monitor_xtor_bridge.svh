// Monitor transactor bridge -- the CONSUMER side. Holds a handle to the signal-level
// transactor interface (uart_monitor_xtor_if) AND a handle to the subscriber that
// implements uart_monitor_if. start() forks the run() loop: BLOCK on the transactor's
// wait_char() (one observed character), then publish it via the NON-BLOCKING monitor
// API observe(). The is_tx tag (which line this monitor taps) is fixed at construction
// and passed on every observe(). Also IMPLEMENTS uart_config_if so the monitor's
// deframer can be configured to match the tapped link.
class uart_monitor_xtor_bridge implements uart_config_if;

    virtual uart_monitor_xtor_if vif;
    uart_monitor_if              subscriber;
    bit                          is_tx;     // 1 = taps STX, 0 = taps SRX

    function new(virtual uart_monitor_xtor_if vif, uart_monitor_if subscriber, bit is_tx = 1'b0);
        this.vif        = vif;
        this.subscriber = subscriber;
        this.is_tx      = is_tx;
    endfunction

    // Launch the observe loop as a background thread.
    task start();
        fork
            run();
        join_none
    endtask

    // Publish each observed character to the subscriber (non-blocking).
    task run();
        forever begin
            automatic logic [7:0] data;
            automatic logic [3:0] status;
            vif.wait_char(data, status);              // blocking: next observed char
            subscriber.observe(data, status, is_tx);  // non-blocking publish
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
