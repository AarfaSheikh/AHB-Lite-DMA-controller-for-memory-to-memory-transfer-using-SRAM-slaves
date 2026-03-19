---

## **Architecture Overview**

The system consists of:

- DMA Controller (AHB-Lite Master)
- 2x SRAM blocks (AHB-Lite Slaves)
- Address decoder + response mux (in top level)

---

### Data Flow

SRAM0 (source) → DMA → SRAM1 (destination)

---

### Transfer Flow

1. CPU configures DMA registers (src, dst, length, mode)
2. DMA becomes AHB master
3. Performs:
   - Read from source SRAM
   - Store in internal register
   - Write to destination SRAM
4. Repeats until transfer complete
5. Sets DONE + optional interrupt

---

## **Specifications**

bus: AHB-Lite

operation: memory-to-memory DMA

memories: 2 SRAM slaves

data width: 32-bit (1 word)

address width: 32-bit

SRAM depth: 4096 words each

SRAM read latency: 1 cycle

DMA modes: single + burst

burst lengths: 4, 8, 16 (single handled separately)

length unit: number of 32-bit words

alignment rule: word-aligned only

completion: done bit + interrupt

error cases: zero length, bad alignment, slave error

---

## *System-level behaviour*

CPU-controlled DMA model:

***CPU → config registers → DMA executes → CPU polls/interrupt***

Registers include:

Source address

Destination address

Transfer length

Control (start, mode, interrupt enable)

Status (done, busy, error)

---

I designed a minimal memory-mapped DMA interface with source, destination, length, control, and status registers. This aligns with common SoC DMA designs while keeping the implementation simple and synthesizable.

*CPU → writes registers → DMA runs → CPU checks status*

---

## **DMA FSM States**

| State | Description |
|------|------------|
| IDLE | Wait for start signal |
| SETUP | Validate inputs (alignment, range, length) |
| READ_ADDR | Issue read address |
| READ_WAIT | Wait for HRDATA |
| WRITE_ADDR | Issue write address |
| WRITE_WAIT | Wait for write completion |
| UPDATE | Update addresses and counters |
| DONE | Transfer complete |
| ERROR | Error detected |

### Loop Behavior

READ → WRITE → UPDATE → repeat until remaining words == 0

---

## **Error Handling**

DMA enters ERROR state and sets error code for:

- Zero-length transfer
- Unaligned source/destination address
- Address out of SRAM range
- Slave response error (HRESP = ERROR)
- Abort request

Error is latched and reported via:
- dma_error
- dma_error_code

---

## **Design Assumptions**

- Only word-aligned (32-bit) transfers supported
- No byte/halfword access
- No wait states (HREADY always 1 in SRAM)
- No arbitration (single master system)
- No FIFO / buffering (single data register)
- Length is specified in number of 32-bit words

---

## **Performance Characteristics**

- 1 read + 1 write per word
- No pipelining → ~2 cycles per transfer (ideal)
- No stalls in SRAM → peak throughput achieved
- Burst mode improves bus efficiency (SEQ transfers)

---

## **How to Run**

### Using Questa / ModelSim

```bash
vlog dma_defs_pkg.sv
vlog dma_controller.sv
vlog sram_ahb_subsystem.sv
vlog top_level_system.sv
vlog tb_top_level_system.sv

vsim tb_top_level_system
run -all

### Expected Output: 

"DMA DONE!" message

SRAM1 contents match SRAM0

No errors reported

---

## **Design Rationale**

- Minimal but realistic DMA architecture
- AHB-Lite chosen for industry relevance
- Separate SRAM blocks to mimic real memory system
- Explicit FSM for clarity and debug visibility
- Error handling included for robustness

---

# *Appendix*


## **AHB-Lite Master signals**  

### *Address / Control signals (Master → Slave)*

|**Signal**|	**Meaning** |
|-------|-------------------|
| HADDR |	address         |
|HTRANS	| transfer type     |
|HWRITE	| read/write        |
|HSIZE	| transfer size     |
|HBURST	| burst type        |
|HPROT	| protection bits   |
|HWDATA	| write data        |

## **AHB-Lite Slave response signals**

### *Data / response (Slave → Master)*

|**Signal**| **Meaning**            |
|-------|---------------------------|
|HRDATA	|read data                  |
|HREADY |transfer complete / stall  |
|HRESP	|OKAY or ERROR              |

## **Shared bus/Global signals**

|**Signal**|	**Meaning** |
|-------|-------------------|
|HCLK   |	clock           |
|HRESETn|	reset           |
|HSEL	| slave select      |

---

## **Read vs Write in AHB**

### *Write*

Master → HADDR

Master → HWRITE = 1

Master → HWDATA

Slave  → HREADY

### *Read*

Master → HADDR

Master → HWRITE = 0

Slave  → HRDATA

Slave  → HREADY

---

### HSIZE in AHB

|**Value**	| **Transfer size** |
|-------|---------------|
|000	| byte          |
|001	| halfword (16b)|
|010	| word (32b)    |

*For this project we use:*
*HSIZE = 3'b010   // 32-bit*

---

### HTRANS 

|**Value**	|**Meaning**	| **When used**|
|-------|---------------|------|
|00	|IDLE	| No transfer happening |
|01	|BUSY	| Master temporarily pauses a burst |
|10	|NONSEQ	| First transfer of a transaction |
|11	|SEQ	| Following transfers in a burst |

*First transfer → NONSEQ*

*Next transfers → SEQ SEQ SEQ ... (based on burst length)*


*For example: burst length = 8*

*NONSEQ → SEQ → SEQ → SEQ → SEQ → SEQ → SEQ → SEQ*

---

