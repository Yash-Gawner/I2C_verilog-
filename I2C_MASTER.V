module I2C_MASTER(
    input clk,
    input reset,

    input [7:0]tx_data,
    input [6:0]address,
    input rw,

    output reg SCL,

    inout SDA
);

reg [2:0]state;

reg [24:0]clock_div;

reg [2:0]count_data;
reg [2:0]count_address;

reg [7:0]shift_data;
reg [7:0]shift_address;

wire receiv_ack;
reg sda_drive_low;

parameter IDLE     = 3'b000,
          ADDRESS  = 3'b001,
          ACK_ADD  = 3'b010,
          DATA     = 3'b011,
          ACK_DATA = 3'b100,
          STOP     = 3'b101;

assign SDA = sda_drive_low ? 1'b0 : 1'bz;

assign receive_ack = ~SDA;

// SCL clocl generation
always @(posedge clk or posedge reset)begin
    
    if(reset)begin
        clock_div <= 0;
        SCL <= 0;
    end

    else if(clock_div == 24)begin
        clock_div <= 0;
        SCL <= ~SCL;
    end

    else 
        clock_div <= clock_div + 1;

end

// wire scl_about_to_toggle = (clock_div == 24);
// wire scl_rising  = scl_about_to_toggle & ~SCL;
// wire scl_falling = scl_about_to_toggle & SCL;


// kipping this verision makes SDA/SCL causality actually match what the I2C protocol requires.
//chat gpt
// Registered edge-detector: scl_d lags SCL by one clk cycle, so
// scl_rising/scl_falling pulse ONE clk cycle AFTER SCL has actually
// transitioned and settled -- not before. This guarantees any SDA
// change made in response happens strictly after SCL is stable,
// never on the same simulation instant as SCL's own edge. That
// simultaneity was breaking START-condition detection on the slave
// when this was written as a predictive "about to toggle" signal.
reg scl_d;
always @(posedge clk or posedge reset) begin
    if (reset) scl_d <= 1'b1;
    else       scl_d <= SCL;
end

wire scl_rising  =  SCL & ~scl_d;
wire scl_falling = ~SCL &  scl_d;

always @(posedge clk or posedge reset)begin

    if(reset)begin

        sda_drive_low <= 1'b0;

        count_data <= 0;
        count_address <= 0;

        shift_data <= 0;
        shift_address <= 0;

        state <= IDLE;

    end

    else if(scl_rising)begin

        case(state)

        IDLE : begin

            count_data <= 0;
            count_address <= 0;

            shift_data <= tx_data;
            shift_address <= {address, rw};
            
            // START: pull SDA low while SCL is high
            sda_drive_low <= 1'b1;
            state <= ADDRESS;

        end

        ADDRESS : begin

            if(count_address == 3'd7)
                state <= ACK_ADD;
            
            else 
                count_address <= count_address + 1;

        end

        ACK_ADD : begin

            if(receive_ack)
                state <= DATA;

            else 
                state <= STOP;

        end

        DATA : begin

            if(count_data == 3'd7)
                state <= ACK_DATA;
            
            else 
                count_data <= count_data + 1;

        end

        ACK_DATA : begin

            state <= STOP;

        end

        STOP : begin
            
            sda_drive_low <= 1'b0;
            state <= IDLE;

        end

        default : state <= IDLE;

        endcase
    end

    else if(scl_falling)begin

        case(state)

        ADDRESS : begin

            sda_drive_low <= ~shift_address[7];
            shift_address <= {shift_address[6:0], 1'b0};

        end

        ACK_ADD : begin

            sda_drive_low <= 1'b0;

        end

        DATA : begin

            sda_drive_low <= ~shift_data[7];
            shift_data <= {shift_data[6:0],1'b0};

        end

        ACK_DATA : begin

            sda_drive_low <= 1'b0;

        end
        default : ;
        endcase
    end
end
endmodule