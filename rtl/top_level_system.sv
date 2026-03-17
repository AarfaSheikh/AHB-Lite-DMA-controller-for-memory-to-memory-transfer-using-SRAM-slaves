// Integrates DMA + SRAM + wiring for the top level system

module top_level_system #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 16,
    parameter MEM_SIZE = 1024
) (
    input wire clk,
    input wire rst_n,
    // DMA interface
    input wire dma_req,
    input wire [ADDR_WIDTH-1:0] dma_addr,
    input wire [DATA_WIDTH-1:0] dma_data_in,
    output wire [DATA_WIDTH-1:0] dma_data_out,
    output wire dma_ack
);

    // Internal signals
    wire [DATA_WIDTH-1:0] sram_data_out;
    wire sram_we;

    // Instantiate SRAM
    sram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEM_SIZE(MEM_SIZE)
    ) u_sram (
        .clk(clk),
        .we(sram_we),
        .addr(dma_addr),
        .data_in(dma_data_in),
        .data_out(sram_data_out)
    );

    // Simple DMA controller logic
    reg dma_active;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_active <= 0;
            dma_ack <= 0;
            sram_we <= 0;
        end else begin
            if (dma_req && !dma_active) begin
                dma_active <= 1;
                sram_we <= 1; // Write to SRAM
                dma_ack <= 1; // Acknowledge DMA request
            end else if (dma_active) begin
                dma_active <= 0;
                sram_we <= 0; // Stop writing to SRAM
                dma_ack <= 0; // Clear acknowledgment
            end else begin
                sram_we <= 0; // Ensure SRAM is not being written to
                dma_ack <= 0; // Ensure acknowledgment is cleared
            end
        end
    end

    // Output data from SRAM to DMA data out when not writing
    assign dma_data_out = (sram_we) ? sram_data_out : {DATA_WIDTH{1'bz}};

endmodule