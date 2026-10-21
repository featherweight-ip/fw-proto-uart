// UART line configuration, set at run time. Each role's bridge implements
// it. tx, rx and a monitor on the same line must be configured alike to
// interoperate.
//
// The values are held levels into the cores, sampled at each character
// (tx: when it is accepted; rx: at its start bit), so a change applies from
// the next character. The oversampling factor and maximum word length are
// module parameters.
//
//   divisor      : clocks per tick; a bit is OVERSAMPLE ticks. 0 stops the
//                  line (16550 DLL/DLM)
//   word_bits    : data bits per character, 5..8 (LCR[1:0] + 5)
//   parity_en    : a parity bit is sent and checked (LCR[3])
//   parity_even  : even parity; 0 = odd (LCR[4])
//   parity_stick : the parity bit is fixed: 0 with parity_even, 1 without
//                  (LCR[5])
//   stop_bits    : 0 = 1 stop bit; otherwise 2, or 1.5 for 5-bit words
//                  (LCR[2])
interface class uart_config_if;

    pure virtual task configure(
            input bit [15:0] divisor,
            input bit [3:0]  word_bits,
            input bit        parity_en,
            input bit        parity_even,
            input bit        parity_stick,
            input bit [1:0]  stop_bits);

endclass
