// DMA Definitions

package dma_defs;

    // ============================================================
    // Global project parameters
    // ============================================================
    parameter int DATA_W = 32;
    parameter int ADDR_W = 32;
    
    parameter int STRB_W = DATA_W / 8;

    // SRAM organization
    parameter int SRAM_WORDS = 4096;              // 4096 x 32-bit words
    parameter int SRAM_BYTES = SRAM_WORDS * 4;    // 16 KB
    parameter int SRAM_ADDR_W = 12;               // word index width for 4096 words


    // FSM States
    typedef enum logic [2:0] {
        IDLE,
        READ_SRC,
        WRITE_DST,
        UPDATE_ADDRS,
        DONE
    } dma_state_t;