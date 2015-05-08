// Copyright (c) 2014-2015, Intel Corporation
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
// **************************************************************************
/* 
 * Module Info: ASE common (C header file)
 * Language   : C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 */


/*
 * Prevent recursive declarations
 */
#ifndef _ASE_COMMON_H_
#define _ASE_COMMON_H_

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
#include <math.h>
// #include <stdbool.h>       // Boolean datatype

#ifdef SIM_SIDE 
#include "svdpi.h"
#endif

// Debug switch
// #define ASE_DEBUG

/*
 * Return integers
 */
#define OK     0
#define NOT_OK -1

// Enable/Disable message queue and shared memory
// DO NOT DISABLE if using with ASE
/* #define ASE_MQ_ENABLE */
/* #define ASE_SHM_ENABLE */

/*
 * Triggers, safety catches and debug information used in the AFU
 * simulator environment.
 */
// ASE message view #define - Print messages as they go around
// #define ASE_MSG_VIEW

// Enable debug info from linked lists 
// #define ASE_LL_VIEW

// Print buffers as they are being alloc/dealloc
// *FIXME*: Connect to ase.cfg
// #define ASE_BUFFER_VIEW


// ------------------------------------------------------------
// SHM memory name length
// ------------------------------------------------------------
#define ASE_SHM_NAME_LEN   40

// ------------------------------------------------------------------------------
// Data structure used between APP and DPI for
// sharing information about
// APP side is implemented as discrete buffers (next = NULL)
// DPI side is implemented as linked list
// ------------------------------------------------------------------------------
struct buffer_t                   //  Descriptiion                    Computed by
{                                 // --------------------------------------------
  int fd_app;                     // File descriptor                 |   APP
  int fd_ase;                     // File descriptor                 |   SIM
  int index;                      // Tracking id                     | INTERNAL
  int valid;                      // Valid buffer indicator          | INTERNAL
  int metadata;                   // MQ marshalling command          | INTERNAL
  char memname[ASE_SHM_NAME_LEN]; // Shared memory name              | INTERNAL
  uint32_t memsize;               // Memory size                     |   APP
  uint64_t vbase;                 // SW virtual address              |   APP
  uint64_t pbase;                 // SIM virtual address             |   SIM
  uint64_t fake_paddr;            // unique low FPGA_ADDR_WIDTH addr |   SIM
  uint64_t fake_paddr_hi;         // unique hi FPGA_ADDR_WIDTH addr  |   SIM
  int is_privmem;                 // Flag memory as a private memory |   SIM
  int is_dsm;                     // Flag memory as DSM              |   TBD
  struct buffer_t *next;
};

// Compute buffer_t size 
#define BUFSIZE     sizeof(struct buffer_t)

// Size of page
#define ASE_PAGESIZE   0x1000        // 4096 bytes
#define CCI_CHUNK_SIZE 2*1024*1024   // CCI 2 MB physical chunks 


/*
 * Common Function prototypes
 */
// Linked list functions
void ll_print_info(struct buffer_t *);
void ll_traverse_print();
void ll_append_buffer(struct buffer_t *);
void ll_remove_buffer(struct buffer_t *);
struct buffer_t* ll_search_buffer(int);
uint32_t check_if_physaddr_used(uint64_t);

// DPI functions
void ase_mqueue_setup();
void ase_mqueue_teardown();
int ase_recv_msg(struct buffer_t *);
void ase_alloc_action(struct buffer_t *);
void ase_dealloc_action(struct buffer_t *);
void ase_destroy();
uint64_t* ase_fakeaddr_to_vaddr(uint64_t);
void ase_dbg_memtest(struct buffer_t *);
void ase_perror_teardown();
void ase_empty_buffer(struct buffer_t *);
uint64_t get_range_checked_physaddr(uint32_t);

// ASE operations
void ase_buffer_info(struct buffer_t *);
void ase_buffer_oneline(struct buffer_t *);
void ase_buffer_t_to_str(struct buffer_t *, char *);
void ase_str_to_buffer_t(char *, struct buffer_t *);
int ase_dump_to_file(struct buffer_t*, char*);
uint64_t ase_rand64();

// Message queue operations
mqd_t mqueue_create(char*, int);
void mqueue_close(mqd_t);
void mqueue_destroy(char*);
void mqueue_send(mqd_t, char*);
int mqueue_recv(mqd_t, char*);

// Debug interface
void shm_dbg_memtest(struct buffer_t *);

// Timestamp functions
void put_timestamp();
char* get_timestamp(int);
char* generate_tstamp_path(char*);

// Error report functions
void ase_error_report(char *, int , int );

// IPC management functions
void final_ipc_cleanup();
void add_to_ipc_list(char *, char *);
void create_ipc_listfile();

/*
 * These functions are called by C++ AALSDK Applications
 */
#ifdef __cplusplus
extern "C" {
#endif // __cplusplus
  // Shared memory alloc/dealloc operations
  void allocate_buffer(struct buffer_t *);
  void deallocate_buffer(struct buffer_t *);
  void csr_write(uint32_t, uint32_t);
  uint32_t csr_read(uint32_t);
  // Remote starter
  void ase_remote_start_simulator();
  // SPL bridge functions *FIXME*
  void setup_spl_cxt_pte(struct buffer_t *, struct buffer_t *);
  void spl_driver_dsm_setup(struct buffer_t *);
  void spl_driver_reset(struct buffer_t *);
  void spl_driver_afu_setup(struct buffer_t *);
  // void spl_driver_start(struct buffer_t *, struct buffer_t *);
  void spl_driver_start(uint64_t *);
  void spl_driver_stop();
  // UMSG subsystem
  void init_umsg_system(struct buffer_t *, struct buffer_t *);
  void set_umsg_mode(uint32_t);
  void send_umsg(struct buffer_t *, uint32_t, char*);
  void deinit_umsg_system(struct buffer_t *);
#ifdef __cplusplus
}
#endif // __cplusplus



/*
 * ASE buffer valid/invalid indicator
 * When a buffer is 'allocated' successfully, it will be valid, when
 * it is deallocated, it will become invalid.
 */
#define ASE_BUFFER_VALID        0xFFFF
#define ASE_BUFFER_INVALID      0x0

/*
 * CSR memory map size
 */
#define CSR_MAP_SIZE            64*1024

/*
 * ASE message headers
 */
// Buffer allocate/deallocate messages
#define HDR_MEM_ALLOC_REQ    0x7F
#define HDR_MEM_ALLOC_REPLY  0xFF
#define HDR_MEM_DEALLOC_REQ  0x0F

// Remote Start Stop messages
#define HDR_ASE_READY_STAT   0xFACEFEED
#define HDR_ASE_KILL_CTRL    0xC00CB00C


/*
 * Enable function call entry/exit
 * Apocalyptically noisy debug feature to watch function entry/exit
 */
// #define ENABLE_ENTRY_EXIT_WATCH
#ifdef  ENABLE_ENTRY_EXIT_WATCH
#define FUNC_CALL_ENTRY printf("--- ENTER: %s ---\n", __FUNCTION__);
#define FUNC_CALL_EXIT  printf("--- EXIT : %s ---\n", __FUNCTION__);
#else
#define FUNC_CALL_ENTRY
#define FUNC_CALL_EXIT
#endif



/*
 * ASE message queue 
 */
// Buffer exchange messages
#define APP2DPI_SMQ_PREFIX          "/app2ase_bufping_smq."
#define DPI2APP_SMQ_PREFIX          "/ase2app_bufpong_smq."
// CSR write messages
#define APP2DPI_CSR_WR_SMQ_PREFIX   "/app2ase_csr_wr_smq."
// UMSG control messages
#define APP2DPI_UMSG_SMQ_PREFIX     "/app2ase_umsg_smq."
/* // ASE control and status queue (used by unified flow) */
/* #define APP2ASE_CTRL_SMQ_PREFIX     "/app2ase_ctrl_smq." */
/* #define ASE2APP_STAT_SMQ_PREFIX     "/app2ase_stat_smq." */


#define ASE_MQ_MAXMSG     4
#define ASE_MQ_MSGSIZE    8192
#define ASE_MQ_NAME_LEN   64

// ASE filepath length
#define ASE_FILEPATH_LEN  256

// Message Queue establishment status
#define MQ_NOT_ESTABLISHED 0x0
#define MQ_ESTABLISHED     0xCAFE

// UMAS establishment status
#define UMAS_NOT_ESTABLISHED 0x0
#define UMAS_ESTABLISHED     0xBEEF

/*
 * Virtual to Pseudo-physical memory shim
 */
#define FPGA_ADDR_WIDTH       38
#define PHYS_ADDR_PREFIX_MASK (uint64_t)(-1) << FPGA_ADDR_WIDTH
#define CL_ALIGN_SHIFT        6

// Width of a cache line in bytes
#define CL_BYTE_WIDTH        64

#define SIZEOF_1GB_BYTES     (uint64_t)pow(1024, 4)

// ----------------------------------------------------------------
// Write responses can arrive on any random channel, this option
// enables responses on random channel (CH0, CH1)
// ----------------------------------------------------------------
// #define ASE_RANDOMISE_WRRESP_CHANNEL

// ------------------------------------------------------------------
// DANGEROUS/BUGGY statements - uncomment prudently (OPEN ISSUES)
// These statements have screwed data structures during testing
// WARNING: Uncomment only if you want to debug these statements.
// ------------------------------------------------------------------
// free(void*) : Free a memory block, "*** glibc detected ***"
//#define ENABLE_FREE_STATEMENT


/*
 * Memory translation 
 */
// Head and tail pointers of DPI side Linked list
extern struct buffer_t *head;      // Head pointer
extern struct buffer_t *end;       // Tail pointer
// CSR fake physical base address
extern uint64_t csr_fake_pin;      // Setting up a pinned fake_paddr (contiguous)
// DPI side CSR base, offsets updated on CSR writes
extern uint32_t *ase_csr_base;      
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

// ---------------------------------------------------------------------
// Enable memory test function
// ---------------------------------------------------------------------
// Basic Memory Read/Write test feature (runs on allocate_buffer)
// Leaving this setting ON automatically scrubs memory (sets 0s)
// Read shm_dbg_memtest() and ase_dbg_memtest()
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


/*
 * Timestamp IPC file
 */
#define TSTAMP_FILENAME ".ase_timestamp"

// Unified SWCallsASE switch
// #define UNIFIED_FLOW

/*
 * Console colors
 */
// ERROR codes are in RED color
#define BEGIN_RED_FONTCOLOR    printf("\033[1;31m");
#define END_RED_FONTCOLOR      printf("\033[0m");

// INFO or INSTRUCTIONS are in GREEN color
#define BEGIN_GREEN_FONTCOLOR  printf("\033[32;1m");
#define END_GREEN_FONTCOLOR    printf("\033[0m");

// WARNING codes in YELLOW color
#define BEGIN_YELLOW_FONTCOLOR printf("\033[0;33m");
#define END_YELLOW_FONTCOLOR   printf("\033[0m");


/*
 * ASE Error codes
 */
#define ASE_USR_CAPCM_NOINIT           0x1    // CAPCM not initialized
#define ASE_OS_MQUEUE_ERR              0x2    // MQ open error
#define ASE_OS_SHM_ERR                 0x3    // SHM open error
#define ASE_OS_FOPEN_ERR               0x4    // Normal fopen failure
#define ASE_OS_MEMMAP_ERR              0x5    // Memory map/unmap errors
#define ASE_OS_MQTXRX_ERR              0x6    // MQ send receive error
#define ASE_OS_MALLOC_ERR              0x7    // Malloc error
#define ASE_OS_STRING_ERR              0x8    // String operations error
#define ASE_IPCKILL_CATERR             0xA    // Catastropic error when cleaning
                                              // IPCs, manual intervention required
#define ASE_UNDEF_ERROR                0xFF   // Undefined error, pls report


/*
 * Unordered Message (UMSG) Address space
 */

// UMSG specific CSRs
#define ASE_UMSGBASE_CSROFF            0x3F4  // UMSG base address
#define ASE_UMSGMODE_CSROFF            0x3F8  // UMSG mode
#define ASE_CIRBSTAT_CSROFF            0x278  // CIRBSTAT

/*
 * SPL constants
 */
#define SPL_DSM_BASEL_OFF 0x1000 //0x910
#define SPL_DSM_BASEH_OFF 0x1004 //0x914
#define SPL_CXT_BASEL_OFF 0x1008 //0x918 // SPL Context Physical address
#define SPL_CXT_BASEH_OFF 0x100c //0x91c 
#define SPL_CH_CTRL_OFF   0x1010 //0x920


/*
 * AFU constants
 */
#define AFU_DSM_BASEL_OFF 0x8A00
#define AFU_DSM_BASEH_OFF 0x8A04
#define AFU_CXT_BASEL_OFF 0x8A08
#define AFU_CXT_BASEH_OFF 0x8A0c

//                                Byte Offset  Attribute  Width  Comments
#define      DSM_AFU_ID            0            // RO      32b    non-zero value to uniquely identify the AFU
#define      DSM_STATUS            0x40         // RO      512b   test status and error info


/* *********************************************************************
 *
 * SIMULATION-ONLY (SIM_SIDE) declarations
 * - This is available only in simulation side 
 * - This compiled in when SIM_SIDE is set to 1
 *
 * *********************************************************************/
#ifdef SIM_SIDE

/*
 * ASE config structure
 * This will reflect ase.cfg
 */
struct ase_cfg_t
{
  int enable_timeout;
  int enable_capcm;
  int memmap_sad_setting;
  int enable_umsg;
  int num_umsg_log2;
  int enable_intr;
  int enable_ccirules;
  int enable_bufferinfo;      // Buffer information
  int enable_asedbgdump;      // To be used only for USER error reporting (THIS WILL dump a lot of gibberish)
  int enable_cl_view;         // Transaction printing control
};
struct ase_cfg_t *cfg;

// ASE config file
#define ASE_CONFIG_FILE "ase.cfg"


/* 
 * Data-exchange functions and structures
 */
// CCI transaction packet
typedef struct {
  long long meta;
  long long qword[8];
  int       cfgvalid;
  int       wrvalid;
  int       rdvalid;
  int       intrvalid;
  int       umsgvalid; 	       
} cci_pkt;


/*
 * Function prototypes
 */
// DPI-C export(C to SV) calls
extern void simkill();
extern void csr_write_init();
extern void umsg_init();
extern void ase_config_dex(struct ase_cfg_t *);

// DPI-C import(SV to C) calls
void ase_init();
void ase_ready();
int csr_write_listener();
int buffer_replicator();
void ase_config_parse(char*);

// Simulation control function
void start_simkill_countdown();
void run_clocks(int num_clocks);

// CSR Write 
void csr_write_dex(cci_pkt *csr);
void csr_write_completed();
// Read system memory line
void rd_memline_dex(cci_pkt *pkt, int *cl_addr, int *mdata );
// Write system memory line
void wr_memline_dex(cci_pkt *pkt, int *cl_addr, int *mdata, char *wr_data );

// CAPCM functions
extern void capcm_init();
/* void rd_capcmline_dex(cci_pkt *pkt, int *cl_addr, int *mdata ); */
/* void wr_capcmline_dex(cci_pkt *pkt, int *cl_addr, int *mdata, char *wr_data ); */

// UMSG functions
void ase_umsg_init();
int umsg_listener();
void ase_umsg_init();


/*
 * Request/Response options
 */ 
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


/*
 * ASE Ready session control files, for wrapping with autorun script
 */
FILE *ase_ready_fd;
#define ASE_READY_FILENAME ".ase_ready"



/*
 * QPI-CA private memory implementation
 *
 * Caching agent private memory is enabled in hw/platform.vh. This
 * block is enabled only in the simulator, application has no need to
 * see this.  The buffer is implemented in /dev/shm for performance
 * reasons. Linux swap space is used to make memory management very
 * efficient.
 *
 * CAPCM_BASENAME : Memory basename is concatenated with index and a
 * timestamp
 * CAPCM_CHUNKSIZE : Large CA private memories are chained together in
 * default 1 GB chunks.
 */
#define CAPCM_BASENAME "/capcm"
#define CAPCM_CHUNKSIZE (1024*1024*1024UL)
uint64_t capcm_num_buffers;

// CAPCM buffer chain info (each buffer holds 1 GB)
/* struct capcm_bufchain_t */
/* { */
/*   int index;                      // Index of array */
/*   int fd;                         // File descriptor */
/*   char memname[ASE_SHM_NAME_LEN]; // SHM name */
/*   uint64_t byte_offset_lo;        // Byte address low */
/*   uint64_t byte_offset_hi;        // Byte address high */
/*   uint64_t *vmem_lo;              // Virtual memory low address */
/*   uint64_t *vmem_hi;              // Virtual memory high address */
/* }; */
// struct capcm_bufchain_t *capcm_buf;
struct buffer_t *capcm_buf;


/*
 * IPC cleanup on catastrophic errors
 */
#define IPC_LOCAL_FILENAME ".ase_ipc_local"
FILE *local_ipc_fp;

/*
 * Physical Memory ranges for PrivMem & SysMem
 */
// System Memory
uint64_t sysmem_size;
uint64_t sysmem_phys_lo;
uint64_t sysmem_phys_hi;

// CAPCM
uint64_t capcm_size;
uint64_t capcm_phys_lo;
uint64_t capcm_phys_hi;

// ASE PID
int ase_pid;

#endif
#endif
