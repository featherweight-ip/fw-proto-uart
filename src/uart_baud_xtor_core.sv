// ----------------------------------------------------------------------------
// UART baud tick core (pure module, K2)
//
// The oversampling enable shared by the tx, rx and monitor cores: `tick` is
// high for one clock in every cfg_divisor clocks, so one bit period is
// OVERSAMPLE ticks = OVERSAMPLE * cfg_divisor clocks. One instance can drive
// both directions of a UART, as the 16550's single divisor latch does; each
// xtor wrapper (uart_*_xtor.sv) holds its own for standalone use.
//
//   cfg_divisor == 0 : no ticks (the cores idle and the line holds mark)
//   cfg_divisor == 1 : a tick every clock
//
// A change of cfg_divisor takes effect at the next tick (the counter reloads
// from it then); the 16550's own reload behaviour (U24) is the model's.
//
// The counter runs from cfg_divisor down to 1 and the tick is at 1 (or 0,
// after reset or while stopped), so a reload needs no subtractor. `tick` is
// registered, a clock behind the counter: its consumers (each core's bit
// timing, a 16550's character timeout) then start from a flop rather than
// from the counter's and the divisor's zero tests.
// ----------------------------------------------------------------------------
module uart_baud_xtor_core #(
        parameter int DIV_WIDTH = 16
    ) (
        input  wire                 clock,
        input  wire                 reset,
        input  wire [DIV_WIDTH-1:0] cfg_divisor,
        output wire                 tick
    );

    reg [DIV_WIDTH-1:0] cnt;    // clocks to the next tick, plus 1 (0 at reset)
    wire                due = (cnt[DIV_WIDTH-1:1] == '0);   // cnt is 0 or 1

    reg                 tick_r;

    assign tick = tick_r;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            cnt    <= '0;
            tick_r <= 1'b0;
        end else begin
            tick_r <= (cfg_divisor != '0) && due;
            if (!due)
                cnt <= cnt - 1'b1;
            else if (cfg_divisor != '0)
                cnt <= cfg_divisor;
        end
    end

endmodule
