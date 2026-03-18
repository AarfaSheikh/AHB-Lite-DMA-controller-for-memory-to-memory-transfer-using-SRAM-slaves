// DMA Definitions

package dma_defs;

    // ============================================================
    // Global project parameters
    // ============================================================
    parameter int DATA_W = 32;                    // Data width (32 bits)
    parameter int ADDR_W = 32;                    // Address width (32 bits)

    parameter int STRB_W = DATA_W / 8;            // Number of bytes per word (4 for 32-bit data)

    // SRAM depth organization
    parameter int SRAM_WORDS = 4096;              // 4096 words of 32 bits each
    parameter int SRAM_BYTES = SRAM_WORDS * 4;    // 4096 * 4 bytes (32 bits) = 16384 bytes = 16 KB <= Total SRAM (memory) size
    parameter int SRAM_ADDR_W = 12;               // 4096 = 2^12; so to address 4096 entries we need 12 address bits <= bits to index 4096 words
    /* 000000000000 → word 0
    ...
    111111111111 → word 4095 */

    // ============================================================
    // System memory map
    // ============================================================
    parameter logic [ADDR_W-1:0] DMA_REG_BASE = 32'h0000_0000; // Base address for DMA control registers (base address = starting address of a block in the system address space)

    parameter logic [ADDR_W-1:0] SRAM0_BASE   = 32'h1000_0000; // where SRAM0 is mapped in the system address space 
    parameter logic [ADDR_W-1:0] SRAM1_BASE   = 32'h2000_0000; // where SRAM1 is mapped in the system address space

    parameter logic [ADDR_W-1:0] DMA_REG_SIZE = 32'h0000_0100; // 256 B - this registers 256 bytes of address space for the DMA control registers (enough for 64 32-bit registers). But we are currently using only 8 32-bit DMA registers
    parameter logic [ADDR_W-1:0] SRAM_SIZE    = 32'h0000_4000; // 16 KB = 16384 decimal

    // ============================================================
    // DMA Register Offsets
    // ============================================================
    parameter logic [7:0] DMA_CTRL_OFFSET        = 8'h00;
    parameter logic [7:0] DMA_STATUS_OFFSET      = 8'h04;
    parameter logic [7:0] DMA_SRC_ADDR_OFFSET    = 8'h08;
    parameter logic [7:0] DMA_DST_ADDR_OFFSET    = 8'h0C;
    parameter logic [7:0] DMA_LEN_OFFSET         = 8'h10;

    parameter logic [7:0] DMA_PERF_CYCLES_OFFSET = 8'h14;
    parameter logic [7:0] DMA_PERF_BEATS_OFFSET  = 8'h18;
    parameter logic [7:0] DMA_PERF_STALLS_OFFSET = 8'h1C;

    // ============================================================
    // DMA_CTRL bit fields
    // ============================================================
    parameter int CTRL_START_BIT      = 0;  // write-1 to start DMA transfer, auto-clears when transfer is done
    parameter int CTRL_IRQ_EN_BIT     = 1;  // write-1 to enable interrupt when DMA transfer is done, ignored if CTRL_START_BIT is not set
    parameter int CTRL_ABORT_BIT      = 2;  // write-1 to abort an ongoing DMA transfer, auto-clears when transfer is aborted
    parameter int CTRL_MODE_BIT       = 3;  // 0=single-beat, 1=burst
    parameter int CTRL_BURST_LEN_LSB  = 4;  // if CTRL_MODE_BIT=1 (burst mode), this is the LSB of the burst length (number of beats per burst). If CTRL_MODE_BIT=0 (single-beat mode), this bit is ignored
    parameter int CTRL_BURST_LEN_MSB  = 7;

    // ============================================================
    // DMA_STATUS bit fields
    // ============================================================
    parameter int STATUS_BUSY_BIT      = 0;
    parameter int STATUS_DONE_BIT      = 1;
    parameter int STATUS_ERROR_BIT     = 2;
    parameter int STATUS_ERRCODE_LSB   = 4;
    parameter int STATUS_ERRCODE_MSB   = 7;

    // ============================================================
    // DMA operating modes
    // ============================================================
    typedef enum logic {
        DMA_MODE_SINGLE = 1'b0,
        DMA_MODE_BURST  = 1'b1
    } dma_mode_t;

    // ============================================================
    // Burst length encoding
    // can store these values in CTRL[7:4]
    // ============================================================
    typedef enum logic [3:0] {
        BURST_LEN_1  = 4'd1,
        BURST_LEN_4  = 4'd4,
        BURST_LEN_8  = 4'd8,
        BURST_LEN_16 = 4'd16
    } dma_burst_len_t;

    // ============================================================
    // DMA error codes
    // ============================================================
    typedef enum logic [3:0] {
        DMA_ERR_NONE         = 4'd0,
        DMA_ERR_ZERO_LEN     = 4'd1,
        DMA_ERR_SRC_ALIGN    = 4'd2,
        DMA_ERR_DST_ALIGN    = 4'd3,
        DMA_ERR_SLV_RESP     = 4'd4,
        DMA_ERR_ABORT        = 4'd5,
        DMA_ERR_OUT_OF_RANGE = 4'd6
    } dma_error_t;

    // // FSM States
    // typedef enum logic [2:0] {
    //     IDLE,
    //     READ_SRC,
    //     WRITE_DST,
    //     UPDATE_ADDRS,
    //     DONE
    // } dma_state_t;

    // ============================================================
    // DMA FSM states
    // ============================================================
    typedef enum logic [3:0] {
        DMA_IDLE,
        DMA_SETUP,
        DMA_READ_ADDR,
        DMA_READ_WAIT,
        DMA_WRITE_ADDR,
        DMA_WRITE_WAIT,
        DMA_UPDATE,
        DMA_DONE,
        DMA_ERROR
    } dma_state_t;

     // ============================================================
    // AHB-Lite transfer type encodings
    // ============================================================
    parameter logic [1:0] HTRANS_IDLE   = 2'b00;
    parameter logic [1:0] HTRANS_BUSY   = 2'b01;
    parameter logic [1:0] HTRANS_NONSEQ = 2'b10;
    parameter logic [1:0] HTRANS_SEQ    = 2'b11;

    // ============================================================
    // AHB-Lite response encodings
    // ============================================================
    parameter logic HRESP_OKAY  = 1'b0;
    parameter logic HRESP_ERROR = 1'b1;

    // ============================================================
    // AHB-Lite transfer size encoding
    // For v1, keep word-only transfers
    // ============================================================
    parameter logic [2:0] HSIZE_BYTE = 3'b000;
    parameter logic [2:0] HSIZE_HALF = 3'b001;
    parameter logic [2:0] HSIZE_WORD = 3'b010;

    // ============================================================
    // Helper function: check if address is word aligned
    // ============================================================
    function automatic logic is_word_aligned(input logic [ADDR_W-1:0] addr);
        return (addr[1:0] == 2'b00); // so valid word addresses must be multiples of 4 & the bottom 2 bits of the address must be 00 for it to be word aligned (multiples of 4 have last 2 bits as 00)
    endfunction

    // ============================================================
    // Helper function: convert byte address to SRAM word index
    // Assumes word-aligned access
    // ============================================================
    function automatic logic [SRAM_ADDR_W-1:0] addr_to_word_index(
        input logic [ADDR_W-1:0] addr,
        input logic [ADDR_W-1:0] base
    );
        addr_to_word_index = (addr - base) >> 2; // addr - base → get offset from SRAM start; >> 2 → divide by 4 (since each word = 4 bytes)
    // Tells how many "4-byte words" from the SRAM base is this address
    endfunction

    // ============================================================
    // Helper function: address range check
    // ============================================================
    function automatic logic addr_in_range(
        input logic [ADDR_W-1:0] addr,
        input logic [ADDR_W-1:0] base,
        input logic [ADDR_W-1:0] size
    );
        return ((addr >= base) && (addr < (base + size)));
    endfunction

endpackage : dma_defs