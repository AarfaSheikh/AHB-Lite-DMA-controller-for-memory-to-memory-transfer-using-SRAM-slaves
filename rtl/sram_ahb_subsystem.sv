// Contains SRAM + AHB slave logic

/* Features: 
    * single-cycle SRAM
    * 32-bit data
    * no wait states (HREADY = 1)
    * HRESP = ERROR for invalid size / range / alignment
    * word-aligned access
*/

module sram_ahb_subsystem #(
    parameter logic [dma_defs_pkg::ADDR_W-1:0] SRAM_BASE = dma_defs_pkg::SRAM0_BASE
    )(
    input logic HCLK,
    input logic HRESETn,

    input logic [dma_defs_pkg::ADDR_W-1:0] HADDR,
    input logic [dma_defs_pkg::DATA_W-1:0] HWDATA,
    input logic HWRITE,
    input logic [1:0] HTRANS,
    input logic [2:0] HSIZE,

    output logic [dma_defs_pkg::DATA_W-1:0] HRDATA,
    output logic HREADY,
    output logic HRESP
);

import dma_defs_pkg::*;

    // Internal signals
    logic [DATA_W-1:0] sram [0:SRAM_WORDS-1];
    logic [SRAM_ADDR_W-1:0] word_addr; // address decoding for SRAM

    logic valid_size; // Check for valid transfer size (word-only)
    logic valid_addr; // Check for valid address range (within SRAM)
    logic valid_align; // Check for word-alignment
    logic valid_transfer; // Overall transfer validity
    logic access_error; // Indicates an access error (invalid size, address, or alignment)

    assign valid_transfer = (HTRANS == HTRANS_NONSEQ) || (HTRANS == HTRANS_SEQ);

    assign valid_size = (HSIZE == HSIZE_WORD);
    assign valid_addr = addr_in_range(HADDR, SRAM_BASE, SRAM_SIZE); // check if address is within SRAM range
    assign valid_align = is_word_aligned(HADDR);

    assign access_error = valid_transfer && (!valid_size || !valid_addr || !valid_align);

    assign word_addr = addr_to_word_index(HADDR, SRAM_BASE); // shift by 2 because word aligned (4 bytes)
    
    assign HREADY = 1'b1;  // always ready
    assign HRESP = access_error ? HRESP_ERROR : HRESP_OKAY; // if there's an access error, respond with ERROR; otherwise, respond with OKAY

    // AHB-Lite read/write slave logic
    always_ff @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            HRDATA <= '0;
        end
        else begin
            if (valid_transfer && !access_error) begin
                if (HWRITE) begin
                    sram[word_addr] <= HWDATA; // Write to SRAM
                end else begin
                    HRDATA <= sram[word_addr]; // Read from SRAM
                end
            end
        end
    end

endmodule