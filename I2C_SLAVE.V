module I2C_SLAVE(
        input SCL,
        input reset,
        input [6:0]my_address,
    
        output reg [7:0]data,
        output reg [6:0]address,
        output reg rw,
        output reg data_valid,

        inout SDA
    );

    reg [2:0]state;

    reg [7:0]shift_data;
    reg [7:0]shift_address;

    reg [2:0]count_data;
    reg [2:0]count_address;

    //reg rw_bit;

    reg sda_drive_low;

    parameter IDLE     = 3'b000,
              ADDRESS  = 3'b001,
              ACK_ADD  = 3'b010,
              DATA     = 3'b011,
              ACK_DATA = 3'b100;
    
    // if we do it in combinational block it will get stuck betwwn positive edge and negative edge 
    wire add_match = (shift_address[7:1] == my_address); 

    assign SDA = sda_drive_low ? 1'b0 : 1'bz;

    reg sda_prev;
    wire start_condition = SCL & sda_prev & ~SDA; // gives us the start condition
    wire stop_condition  = SCL & ~sda_prev & SDA; // gives us the stop conditon

    always @(SDA or SCL)begin
        sda_prev <= SDA;
    end

    always @(posedge SCL or posedge start_condition or
          posedge stop_condition or posedge reset) begin

        if(reset)begin

            count_address <= 0;
            count_data <= 0;

            shift_data <= 0;
            shift_address <= 0;

            sda_drive_low <= 1'b0;
            state <= IDLE;

        end

        else if (stop_condition) begin
            state <= IDLE;
        end

        else if (start_condition) begin
            state <= ADDRESS;
            count_address <= 0;
            count_data <= 0;
            data_valid <= 0;
        end

        else begin

            case(state)

                ADDRESS : begin

                    shift_address <= {shift_address[6:0],SDA};
                    if(count_address == 3'd7)
                        state <= ACK_ADD;
                    else 
                        count_address <= count_address + 1;
                end

                ACK_ADD : begin

                    address   <= shift_address[7:1];
                    rw  <= shift_address[0];
                    count_data <= 0;              
                    state   <= DATA;;
                end

                DATA : begin

                    shift_data <= {shift_data[6:0],SDA};
                    if(count_data == 3'd7)
                        state <= ACK_DATA;
                    else 
                        count_data <= count_data + 1;
                end

                ACK_DATA : begin

                    data <= shift_data;
                    data_valid <= 1'b1;

                    state <= IDLE;
                end

                default : ;
        
            endcase
        end

    end

//--------------------------------------------------------------------
 // below code was write for simulation but in hardware i could have been problem 
//-----------------------------------------------------------------
    // //start state goes to address
    // always @(posedge start_condition or posedge reset)begin
    //     if(reset)begin
    //         // handled above
    //     end

    //     else 
    //         state <= ADDRESS;
    // end

    // // stop state goes to ideal 
    // always @(posedge stop_condition or posedge reset)begin
    //     if(!reset)
    //         state <= IDEAL;
    // end

    always @(negedge SCL or posedge reset)begin

        if(reset)
            sda_drive_low <= 1'b0;
        
        else begin

            case(state)

                ACK_ADD:  sda_drive_low <= add_match; // make sda low id add match;
                ACK_DATA : sda_drive_low <= 1'b1;
                default:  sda_drive_low <= 1'b0;

            endcase
        end
    end

endmodule

