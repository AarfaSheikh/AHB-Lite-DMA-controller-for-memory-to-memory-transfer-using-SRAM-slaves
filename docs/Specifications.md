bus: AHB-Lite
operation: memory-to-memory DMA

memories: 2 SRAM slaves

data width: 32-bit
address width: 32-bit

SRAM depth: 4096 words each
SRAM read latency: 1 cycle

DMA modes: single + burst
burst lengths: 1, 4, 8, 16

alignment rule: word-aligned only
completion: done bit + interrupt
error cases: zero length, bad alignment, slave error

========================
========================

**AHB-Lite Master signals**
*Address / Control signals (Master → Slave)*
**Signal**	**Meaning**
HADDR	address
HTRANS	transfer type
HWRITE	read/write
HSIZE	transfer size
HBURST	burst type
HPROT	protection bits
HWDATA	write data

**AHB-Lite Slave response signals**
*Data / response (Slave → Master)*
**Signal**	**Meaning**
HRDATA	read data
HREADY	transfer complete / stall
HRESP	OKAY or ERROR

*Shared bus/Global signals*
**Signal**	**Meaning**
HCLK	clock
HRESETn	reset
HSEL	slave select

====

**Read vs Write in AHB**

*Write*
Master → HADDR
Master → HWRITE = 1
Master → HWDATA
Slave  → HREADY

*Read*
Master → HADDR
Master → HWRITE = 0
Slave  → HRDATA
Slave  → HREADY

====

