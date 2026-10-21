// ======================================================================
// uart_proto_tb's error-injection group (K6) at OVERSAMPLE 16.
//
// Run:  dfm run uart-proto-err
// ======================================================================
module uart_proto_err_tb;
    uart_proto_tb #(.OVERSAMPLE(16), .TESTS(2)) u_tb ();
endmodule
