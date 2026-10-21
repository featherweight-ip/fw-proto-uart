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
// ----------------------------------------------------------------------------
module uart_baud_xtor_core #(
        parameter int DIV_WIDTH = 16
    ) (
        input  wire                 clock,
        input  wire                 reset,
        input  wire [DIV_WIDTH-1:0] cfg_divisor,
        output wire                 tick
    );

    reg [DIV_WIDTH-1:0] cnt;    // clocks to the next tick

    assign tick = (cfg_divisor != '0) && (cnt == '0);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            cnt <= '0;
        end else if (cnt != '0) begin
            cnt <= cnt - 1'b1;
        end else if (cfg_divisor != '0) begin
            cnt <= cfg_divisor - 1'b1;
        end
    end

endmodule
