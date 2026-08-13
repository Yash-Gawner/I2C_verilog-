module tb_I2C;

reg clk = 0;
reg reset = 1;

wire SDA;
wire SCL;

// CHAT GPT 
// Real I2C buses have physical pull-up resistors, so an undriven
// line idles HIGH. Without this, an undriven 'bz reads as 'z' in
// simulation (effectively unknown), and START/STOP edge detection
// on the slave will never trigger.
pullup(SDA);

always #5 clk = ~clk;

reg [7:0] tx_data = 8'hA5;
reg [6:0] address = 7'h50;
reg       rw      = 1'b0;  

I2C_MASTER master (
    .clk(clk),
    .reset(reset),
    .SCL(SCL),
    .tx_data(tx_data),
    .address(address),
    .rw(rw),
    .SDA(SDA)
);

I2C_SLAVE slave (
    .SCL(SCL),
    .reset(reset),
    .my_address(7'h50),   // must match `address` above to be ACKed
    .data(),
    .address(),
    .rw(),
    .data_valid(),
    .SDA(SDA)
);

// ---- Latch the first completed transfer ----
// The master has no start/enable input, so it free-runs into
// repeated transactions. Checking data_valid at one fixed point in
// time is unreliable (a new START can clear it again). Latch on the
// first pulse instead.
reg seen_valid = 0;
reg [7:0] captured_data = 0;

always @(posedge slave.data_valid) begin
    seen_valid    <= 1'b1;
    captured_data <= slave.data;
end

initial begin
    $dumpfile("i2c_wave.vcd");
    $dumpvars(0, tb_I2C);

    #20 reset = 0;

    #6000000; // enough time for one full transaction to complete

    if (seen_valid && captured_data == tx_data && slave.address == address && slave.rw == rw)
        $display("PASS: data=0x%0h address=0x%0h rw=%0b", captured_data, slave.address, slave.rw);
    else
        $display("FAIL: seen_valid=%0b data=0x%0h(exp 0x%0h) address=0x%0h(exp 0x%0h) rw=%0b(exp %0b)",
                  seen_valid, captured_data, tx_data, slave.address, address, slave.rw, rw);

    $finish;
end

endmodule