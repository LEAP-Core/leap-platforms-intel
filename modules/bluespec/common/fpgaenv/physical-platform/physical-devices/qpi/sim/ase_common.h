// Copyright (c) 2011-2014, Intel Corporation
//
// Redistribution  and  use  in source  and  binary  forms,  with  or  without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of  source code  must retain the  above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name  of Intel Corporation  nor the names of its contributors
//   may be used to  endorse or promote  products derived  from this  software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
// IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
// LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
// CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
// SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
// INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
// CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
// ---------------------------------------------------------------------
// ASE common (C header file)
// Author: Rahul R Sharma
//         Intel Corporation
// ---------------------------------------------------------------------

#include "ase_sim.h"

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/types.h>   
#include <sys/fcntl.h>
#include <sys/stat.h>
#include <time.h>       
#include <ctype.h>         
#include <mqueue.h>        // Message queue setup
#include <errno.h>         // Error management
#include <signal.h>        // Used to kill simulation             
#include <pthread.h>       // DPI uses a csr_write listener thread
#include <sys/resource.h>  // Used to get/set resource limit
#include <sys/time.h>      // Timestamp generation

// #define __FD_SETSIZE  65535

// ------------------------------------------------------------
// Return integers
// ------------------------------------------------------------
#define OK     0
#define NOT_OK 1
// #define PM

// Enable/Disable message queue and shared memory
// DO NOT DISABLE if using with ASE
#define ASE_MQ_ENABLE
#define ASE_SHM_ENABLE

// --------------------------------------------------------------------
// Triggers, safety catches and debug information used in the AFU
// simulator environment.
// --------------------------------------------------------------------
// ASE message view #define - Print messages as they go around
// #define ASE_MSG_VIEW

// Enable debug info from linked lists 
// #define ASE_LL_VIEW

// Print buffers as they are being updated
// #define ASE_BUFFER_VIEW

// Shim address print
#define ASE_PRINT_SHIM_ADDR

// ASE Cache line data in transaction
//#define ASE_CL_VIEW


// ------------------------------------------------------------
// SHM memory name length
// ------------------------------------------------------------
#define ASE_SHM_NAME_LEN   40

// --------------------------------------------------------------------
// Data structure used between APP and DPI for
// sharing information about
// APP side is implemented as discrete buffers (next = NULL)
// DPI side is implemented as linked list
// --------------------------------------------------------------------
struct buffer_t                   //  Descriptiion                    Computed by
{                                 // --------------------------------------------
  int fd_app;                     // File descriptor                 |   APP
  int fd_dpi;                     // File descriptor                 |   DPI
  int index;                      // Tracking id                     | INTERNAL
  int valid;                      // Valid buffer indicator          | INTERNAL
  int metadata;                   // MQ marshalling command          | INTERNAL
  char memname[ASE_SHM_NAME_LEN]; // Shared memory name              | INTERNAL
  uint32_t memsize;               // Memory size                     |   APP
  uint64_t vbase;                 // SW virtual address              |   APP
  uint64_t pbase;                 // DPI virtual address             |   DPI
  uint64_t fake_off_lo;           // Lower fake bound of mem region  |   DPI
  uint64_t fake_off_hi;           // Upper fake bound of mem region  |   DPI
  uint64_t fake_paddr;            // unique low FPGA_ADDR_WIDTH addr |   DPI
  uint64_t fake_paddr_hi;         // unique hi FPGA_ADDR_WIDTH addr  |   DPI
  struct buffer_t *next;
};

// Compute buffer_t size 
#define BUFSIZE     sizeof(struct buffer_t)


// ------------------------------------------------------------
// Function prototypes
// ------------------------------------------------------------
// Linked list functions
void ll_print_info(struct buffer_t *);
void ll_traverse_print();
void ll_append_buffer(struct buffer_t *);
void ll_remove_buffer(struct buffer_t *);
struct buffer_t* ll_search_buffer(int);

// DPI functions
void dpi_mqueue_setup();
void dpi_mqueue_teardown();
int dpi_recv_msg(struct buffer_t *);
void dpi_alloc_action(struct buffer_t *);
void dpi_dealloc_action(struct buffer_t *);
void dpi_destroy();
uint64_t* dpi_fakeaddr_to_vaddr(uint64_t);
void dpi_dbg_memtest(struct buffer_t *);
void dpi_perror_teardown();
void dpi_empty_buffer(struct buffer_t *);

// ASE operations
void ase_buffer_info(struct buffer_t *);
void ase_buffer_t_to_str(struct buffer_t *, char *);
void ase_str_to_buffer_t(char *, struct buffer_t *);
int ase_dump_to_file(struct buffer_t*, char*);

// Message queue operations
mqd_t mqueue_create(char*, int);
void mqueue_close(mqd_t);
void mqueue_destroy(char*);
void mqueue_send(mqd_t, char*);
int mqueue_recv(mqd_t, char*);

void shm_dbg_memtest(struct buffer_t *);

// Timestamp functions
void put_timestamp();
char* get_timestamp();

// Error report functions
void ase_error_report(char *, int , int );


#ifdef __cplusplus
extern "C" {
#endif // __cplusplus
// Shared memory alloc/dealloc operations
void allocate_buffer(struct buffer_t *);
void deallocate_buffer(struct buffer_t *);
void csr_write(uint32_t, uint32_t);
uint32_t csr_read(uint32_t);

  // test add
  void capcm_init(int);
  void capcm_deinit();
  void capcm_rdline_req(int, int);
  void capcm_wrline_req(int, int, char*);
#ifdef __cplusplus
}
#endif // __cplusplus



// ------------------------------------------------------------------
// ASE buffer valid/invalid indicator
// When a buffer is 'allocated' successfully, it will be valid, when
// it is deallocated, it will become invalid.
// ------------------------------------------------------------------
#define ASE_BUFFER_VALID        0xFFFF
#define ASE_BUFFER_INVALID      0x0


// -------------------------------------------------------------------
// ASE memory allocate/deallocate message headers (buffer_t metadata) 
// -------------------------------------------------------------------
#define HDR_MEM_ALLOC_REQ    0x7F
#define HDR_MEM_ALLOC_REPLY  0xFF
#define HDR_MEM_DEALLOC_REQ  0x0F

// Antifreeze control - Inject a clock cycle event every 'x' usec
#define ANTIFREEZE_TIMEOUT   10000 // 25000


// -------------------------------------------------------------------
// Enable function call entry/exit
// Apocalyptically noisy debug feature to watch function entry/exit
// -------------------------------------------------------------------
// #define ENABLE_ENTRY_EXIT_WATCH 
#ifdef  ENABLE_ENTRY_EXIT_WATCH
#define FUNC_CALL_ENTRY printf("--- ENTER: %s ---\n", __FUNCTION__);	
#define FUNC_CALL_EXIT  printf("--- EXIT : %s ---\n", __FUNCTION__);	
#else
#define FUNC_CALL_ENTRY
#define FUNC_CALL_EXIT 
#endif 

  
// ------------------------------------------------------------
// ASE message queue 
// CSR Write message queue attributes
// ------------------------------------------------------------
#define APP2DPI_SMQ_PREFIX          "/app2dpi_smq."
#define DPI2APP_SMQ_PREFIX          "/dpi2app_smq."
#define APP2DPI_CSR_WR_SMQ_PREFIX   "/app2dpi_csr_wr_smq."
#define APP2DPI_UMSG_SMQ_PREFIX     "/app2dpi_umsg_smq."
#define ASE_MQ_MAXMSG     4
#define ASE_MQ_MSGSIZE    8192
#define ASE_MQ_NAME_LEN   64


// ------------------------------------------------------------
// Virtual to Pseudo-physical memory shim
// ------------------------------------------------------------
#define FPGA_ADDR_WIDTH       38
#define PHYS_ADDR_PREFIX_MASK (uint64_t)(-1) << FPGA_ADDR_WIDTH
#define CL_ALIGN_SHIFT        6

// -------------------------------------------------------------
// Width of a cache line in bytes
// -------------------------------------------------------------
#define CL_BYTE_WIDTH        64

// -------------------------------------------------------------
// Request/Response options
// -------------------------------------------------------------
// TX0 channel
#define ASE_TX0_RDLINE       0x4
// TX1 channel
#define ASE_TX1_WRTHRU       0x1
#define ASE_TX1_WRLINE       0x2
#define ASE_TX1_WRFENCE      0x5   // CCI 1.8
#define ASE_TX1_INTRVALID    0x8   // CCI 1.8
// RX0 channel
#define ASE_RX0_CSR_WRITE    0x0
#define ASE_RX0_WR_RESP      0x1
#define ASE_RX0_RD_RESP      0x4
#define ASE_RX0_INTR_CMPLT   0x8   // CCI 1.8
#define ASE_RX0_UMSG         0xf   // CCI 1.8
// RX1 channel
#define ASE_RX1_WR_RESP      0x1
#define ASE_RX1_INTR_CMPLT   0x8   // CCI 1.8

// ----------------------------------------------------------------
// Write responses can arrive on any random channel, this option
// enables responses on random channel (CH0, CH1)
// ----------------------------------------------------------------
#define ASE_RANDOMISE_WRRESP_CHANNEL

// ------------------------------------------------------------------
// DANGEROUS/BUGGY statements - uncomment prudently (OPEN ISSUES)
// These statements have screwed data structures during testing
// WARNING: Uncomment only if you want to debug these statements.
// ------------------------------------------------------------------
// free(void*) : Free a memory block, "*** glibc detected ***"
//#define ENABLE_FREE_STATEMENT

// -----------------------------------------------------------------
// Listing global variables hereVariables
// -----------------------------------------------------------------
#ifndef _ASE_COMMON_H_
#define _ASE_COMMON_H_
// Head and tail pointers of DPI side Linked list
extern struct buffer_t *head;      // Head pointer
extern struct buffer_t *end;       // Tail pointer
// CSR fake physical base address
extern uint64_t csr_fake_pin;      // Setting up a pinned fake_paddr (contiguous)
// DPI side CSR base, offsets updated on CSR writes
extern uint64_t dpi_csr_base;      
// A null string 
extern char null_str[CL_BYTE_WIDTH];
// Transaction count
extern unsigned long int ase_cci_transact_count;
// ASE log file descriptor
extern FILE *ase_cci_log_fd;
// Timestamp reference time
extern struct timeval start;
extern long int ref_anchor_time;
extern uint32_t shim_called;
// Fake lower bound for offset
extern uint64_t fake_off_low_bound;
// QPI-CA variables
#ifdef SIM_SIDE
int capcm_fd;
char capcm_memname[ASE_SHM_NAME_LEN];
uint32_t capcm_memsize;
uint64_t capcm_vbase;
#endif

#endif

// ---------------------------------------------------------------------
// Enable memory test function
// ---------------------------------------------------------------------
// Basic Memory Read/Write test feature (runs on allocate_buffer)
// Leaving this setting ON automatically scrubs memory (sets 0s)
// Read shm_dbg_memtest() and dpi_dbg_memtest()
#define ASE_MEMTEST_ENABLE

// ---------------------------------------------------------------------
// Virtual memory safety catch
// ---------------------------------------------------------------------
// Checks for the following conditions in memory shim and exits on them
// - If generated address is not cache aligned (not modulo 0x40)
// - If generated address is not within monitored memory region
// Disable this ONLY if you want to segfault intentionally 
// NOTE: Simulator will close down if safety catch sees illegal
// transactions
// ---------------------------------------------------------------------
#define ASE_VADDR_SAFETY_CATCH
#define SHIMERR_OORANGE         1
#define SHIMERR_NO_REGION       2
#define SHIMERR_NOT_THIS_BUFFER 3
#define SHIMERR_INVALID_BUFFER  4

// ---------------------------------------------------------------------
// CCI transaction logger 
// Enable transaction logger and set up name as required
// ---------------------------------------------------------------------
#define ASE_CCI_TRANSACTION_LOGGER
#ifdef ASE_CCI_TRANSACTION_LOGGER
#define CCI_LOGNAME "transactions.tsv"
#endif

// ---------------------------------------------------------------------
// Timestamp|IPC file
// ---------------------------------------------------------------------
#define TSTAMP_PATH ".ase_timestamp"
#define TSTAMP_FILENAME ".ase_timestamp"


// ---------------------------------------------------------------------
// Final closure of IPC in case of catastrophic failure
// ---------------------------------------------------------------------
#ifdef SIM_SIDE
#define IPC_LOCAL_FILENAME ".ase_ipc_local"
#define IPC_GLOBAL_FILENAME "~/.ase_ipc_global"

FILE *local_ipc_fp;
FILE *global_ipc_fp;
#endif

// ---------------------------------------------------------------------
// QPI-CA private memory
// ---------------------------------------------------------------------
#define CAPCM_NUM_CACHELINES 64
#define CAPCM_BASENAME "/ase-capcm."


// ---------------------------------------------------------------------
// Console colors
// ---------------------------------------------------------------------
// ERROR codes are in RED color
#define BEGIN_RED_FONTCOLOR   printf("\033[1;31m");
#define END_RED_FONTCOLOR     printf("\033[1;m");

// INFO or INSTRUCTIONS are in GREEN color
#define BEGIN_GREEN_FONTCOLOR printf("\033[32;1m");
#define END_GREEN_FONTCOLOR   printf("\033[0m");

// ---------------------------------------------------------------------
// ASE Error codes
// ---------------------------------------------------------------------
#define ASE_USR_CAPCM_NOINIT           0x1    // CAPCM not initialized
#define ASE_OS_MQUEUE_ERR              0x2    // MQ open error
#define ASE_OS_SHM_ERR                 0x3    // SHM open error
#define ASE_OS_FOPEN_ERR               0x4    // Normal fopen failure
#define ASE_OS_MEMMAP_ERR              0x5    // Memory map/unmap errors
#define ASE_OS_MQTXRX_ERR              0x6    // MQ send receive error
#define ASE_IPCKILL_CATERR             0xA    // Catastropic error when cleaning
                                              // IPCs, manual intervention required
#define ASE_UNDEF_ERROR                0xFF   // Undefined error, pls report
