// DMA (Direct Memory Access) Engine Logic (FSM + AHB master interface logic) 
/*******************************************************************************
Read data from Source SRAM
        ↓
Hold data in register
        ↓
Write data to Destination SRAM
        ↓
Update addresses and counters
        ↓
Repeat until length = 0
********************************************************************************
*/

module dma_controller #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter MEM_SIZE = 1024
) (
    input wire clk,
    input wire rst_n,
    // DMA control signals
    input wire dma_start,
    input wire [ADDR_WIDTH-1:0] src_addr,
    input wire [ADDR_WIDTH-1:0] dst_addr,
    input wire [15:0] length, // Number of words to transfer
    output reg dma_done,
    
    // AHB master interface
    output reg [ADDR_WIDTH-1:0] ahb_addr,
    output reg [DATA_WIDTH-1:0] ahb_data_out,
    input wire [DATA_WIDTH-1:0] ahb_data_in,
    output reg ahb_write_en,
    output reg ahb_sel,
    input wire ahb_ready
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        READ_SRC,
        WRITE_DST,
        UPDATE_ADDRS,
        DONE
    } state_t;

    state_t current_state, next_state;

    // Internal registers
    reg [ADDR_WIDTH-1:0] current_src_addr;
    reg [ADDR_WIDTH-1:0] current_dst_addr;
    reg [15:0] remaining_length;
    reg [DATA_WIDTH-1:0] data_buffer;

    // FSM sequential logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            dma_done <= 0;
            ahb_write_en <= 0;
            ahb_sel <= 0;
        end else begin
            current_state <= next_state;
        end
    end

    // FSM combinational logic
    always @(*) begin
        // Default values for outputs and next state
        next_state = current_state;
        case (current_state)
                IDLE: begin
                        if (dma_start) begin
                        next_state = READ_SRC;
                        current_src_addr = src_addr;
                        current_dst_addr = dst_addr;
                        remaining_length = length;
                        dma_done = 0;
                        end
                end
                
                READ_SRC: begin
                        if (ahb_ready) begin
                        data_buffer = ahb_data_in; // Capture data from source SRAM
                        next_state = WRITE_DST;
                        end else begin
                        ahb_addr = current_src_addr; // Set AHB address to source
                        ahb_write_en = 0; // Read operation
                        ahb_sel = 1; // Select AHB slave
                        end    
                end 
                WRITE_DST: begin
                        if (ahb_ready) begin
                        next_state = UPDATE_ADDRS;
                        end else begin
                        ahb_addr = current_dst_addr; // Set AHB address to destination
                        ahb_data_out = data_buffer; // Set data to write to destination SRAM
                        ahb_write_en = 1; // Write operation
                        ahb_sel = 1; // Select AHB slave
                        end
                end
                UPDATE_ADDRS: begin
                        current_src_addr = current_src_addr + (DATA_WIDTH/8); // Increment source address
                        current_dst_addr = current_dst_addr + (DATA_WIDTH/8); // Increment destination address
                        remaining_length = remaining_length - 1; // Decrement remaining length
                        if (remaining_length == 0) begin
                        next_state = DONE;
                        end else begin
                        next_state = READ_SRC; // Repeat for next word
                        end
                end
                
                DONE: begin
                    dma_done = 1; // Indicate DMA transfer is complete
                    ahb_write_en = 0; // Ensure no write operation is active
                    ahb_sel = 0; // Deselect AHB slave
                end             
                default: begin
                    next_state = IDLE;
                end
        endcase
    end
        
endmodule