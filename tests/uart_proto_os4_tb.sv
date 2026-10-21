// ======================================================================
// uart_proto_tb at OVERSAMPLE 4, the smallest the formal harnesses use
// short of 2, with both test groups. A bit is 4 ticks, so the start-bit
// middle and the 1.5-stop length are at their coarsest.
//
// Run:  dfm run uart-proto-os4
// ======================================================================
module uart_proto_os4_tb;
    uart_proto_tb #(.OVERSAMPLE(4), .TESTS(3)) u_tb ();
endmodule
