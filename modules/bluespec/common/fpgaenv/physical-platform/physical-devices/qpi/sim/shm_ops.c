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
// ------------------------------------------------------------------
// Shared memory access functions - C Module (no main() here)
// Author: Rahul R Sharma
//         Intel Corporation
//
// Revisions
// RRS         18 May 2011       Combined shared memory region
//                               - Entire ase_shm_create rewritten
//
// -------------------------------------------------------------------
#include "ase_common.h"

// Message queues opened by APP
mqd_t app2dpi_tx;           // app2dpi mesaage queue in TX mode
mqd_t dpi2app_rx;           // dpi2app mesaage queue in RX mode
mqd_t app2dpi_csr_wr_tx;    // CSR Write MQ in TX mode
mqd_t app2dpi_umsg_tx;       // UMSG MQ in TX mode

// CSR Map
uint32_t csr_map[0x900/4];

// -----------------------------------------------------------------
// csr_write : Write data to a location in CSR region (index = 0)
// -----------------------------------------------------------------
void csr_write(uint32_t csr_offset, uint32_t data)
{
  FUNC_CALL_ENTRY;

  char csr_wr_str[ASE_MQ_MSGSIZE];

  if ( csr_offset < 0x900 ) {
    csr_map[csr_offset/4] = data;
  }
  
  // ---------------------------------------------------
  // Form a csr_write message 
  //                     -----------------
  // CSR_write message:  | offset | data |
  //                     -----------------
  // ---------------------------------------------------
#ifdef ASE_MQ_ENABLE
  // Open message queue
  app2dpi_csr_wr_tx = mqueue_create(APP2DPI_CSR_WR_SMQ_PREFIX, O_WRONLY);		

  // Send message
  sprintf(csr_wr_str, "%u %u", csr_offset, data);
  mqueue_send(app2dpi_csr_wr_tx, csr_wr_str);

  // Close message queue
  mqueue_close(app2dpi_csr_wr_tx);
#endif

  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------------
// csr_read : CSR read operation
// -----------------------------------------------------------------
uint32_t csr_read(uint32_t csr_offset)
{
  FUNC_CALL_ENTRY;

  FUNC_CALL_EXIT;

  return csr_map[csr_offset/4];
}


// -----------------------------------------------------------------
// allocate_buffer: Shared memory allocation and vbase exchange
// Instantiate a buffer_t structure with given parameters
// Must be called by ASE_APP
// -----------------------------------------------------------------
void allocate_buffer(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

  char tmp_msg[ASE_MQ_MSGSIZE]  = { 0, };
  int static buffer_index_count = 0;

  printf("Attempting to open a shared memory... ");

  // Buffer is invalid until successfully allocated
  mem->valid = ASE_BUFFER_INVALID;

  // If memory size is not set, then exit !!
  if (mem->memsize <= 0)
    {
      printf("Memory requested must be larger than 0 bytes... exiting...\n");
      exit(1);
    }
  
  // Autogenerate a memname, by defualt the first region id=0 will be
  // called "/csr", subsequent regions will be called strcat("/buf", id)
  // Initially set all characters to NULL
  memset(mem->memname, '\0', sizeof(mem->memname));
  if(buffer_index_count == 0)
    {
      strcpy(mem->memname, "/csr.");
      strcat(mem->memname, get_timestamp() );
    }
  else
    {
      sprintf(mem->memname, "/buf%d.", buffer_index_count);
      strcat(mem->memname, get_timestamp() );
    }

  // Obtain a file descriptor for the shared memory region
  mem->fd_app = shm_open(mem->memname, O_CREAT|O_RDWR, S_IREAD|S_IWRITE);
  if(mem->fd_app < 0)
    {
      /* ase_error_report("shm_open", errno, ASE_OS_SHM_ERR); */
      perror("shm_open");
      exit(1);
    }

  // Mmap shared memory region
  mem->vbase = (uint64_t) mmap(NULL, mem->memsize, PROT_READ|PROT_WRITE, MAP_SHARED, mem->fd_app, 0);
  if(mem->vbase == (uint64_t) MAP_FAILED) 
    {
      perror("mmap");
      /* ase_error_report("mmap", errno, ASE_OS_MEMMAP_ERR); */
      exit(1);
    }
  
  // Extend memory to required size
  ftruncate(mem->fd_app, (off_t)mem->memsize); 

  // Autogenerate buffer index
  mem->index = buffer_index_count++;
  printf("SUCCESS\n");  

  // Set buffer as valid
  mem->valid = ASE_BUFFER_VALID;

  // Send an allocate command to DPI, metadata = ASE_MEM_ALLOC
  mem->metadata = HDR_MEM_ALLOC_REQ;
  mem->next = NULL;

  // If memtest is enabled
#ifdef ASE_MEMTEST_ENABLE
  shm_dbg_memtest(mem);
#endif

  // Message queue must be enabled when using DPI (else debug purposes only)
#ifdef ASE_MQ_ENABLE
  // vbase/pbase exchange mqueue
  app2dpi_tx = mqueue_create(APP2DPI_SMQ_PREFIX, O_WRONLY);
  dpi2app_rx = mqueue_create(DPI2APP_SMQ_PREFIX, O_RDONLY);

  // Form message and transmit to DPI
  ase_buffer_t_to_str(mem, tmp_msg);
  mqueue_send(app2dpi_tx, tmp_msg);
  
  // Receive message from DPI with pbase populated
  while(mqueue_recv(dpi2app_rx, tmp_msg)==0) { /* wait */ }
  ase_str_to_buffer_t(tmp_msg, mem);

  // Close mqueues
  mq_close(app2dpi_tx);
  mq_close(dpi2app_rx);
#endif
  
  // Print out the buffer  
#ifdef ASE_BUFFER_VIEW
  ase_buffer_info(mem);
#endif

  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------------------
// deallocate_buffer : Deallocate a memory region
// Destroy shared memory regions
// Called by ASE APP only
// -----------------------------------------------------------------------
void deallocate_buffer(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

  int ret;
  char tmp_msg[ASE_MQ_MSGSIZE] = { 0, };
  char *mq_name;
  mq_name = malloc (ASE_MQ_NAME_LEN);
  memset(mq_name, '\0', sizeof(mq_name));

  printf("Deallocating memory region %s ...", mem->memname);

  // Send buffer with metadata = HDR_MEM_DEALLOC_REQ
  mem->metadata = HDR_MEM_DEALLOC_REQ;

#ifdef ASE_MQ_ENABLE    
  // Open message queue
  strcpy(mq_name, APP2DPI_SMQ_PREFIX);
  strcat(mq_name, get_timestamp());
  app2dpi_tx = mq_open(mq_name, O_WRONLY);

  // Send a one way message to request a deallocate
  ase_buffer_t_to_str(mem, tmp_msg);
  mqueue_send(app2dpi_tx, tmp_msg);

  // Close message queue
  mq_close(app2dpi_tx); 
#endif

  // Unmap the memory accordingly
  ret = munmap((void*)mem->vbase, (size_t)mem->memsize);
  if(0 != ret) 
    {
      /* ase_error_report("munmap", errno, ASE_OS_MEMMAP_ERR); */
      perror("munmap");
      exit(1);
    }
    
  // Print if successful
  printf("SUCCESS\n");

  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------------------------
// shm_dbg_memtest : A memory read write test (DEBUG feature)
// To run the test ASE_MEMTEST_ENABLE must be enabled.
// - This test runs alongside a process dpi_dbg_memtest.
// - shm_dbg_memtest() is started before MEM_ALLOC_REQ message is sent to DPI
//   The simply starts writing 0xCAFEBABE to memory region
// - dpi_dbg_memtest() is started after the MEM_ALLOC_REPLY message is sent back
//   This reads all the data, verifies it is 0xCAFEBABE and writes 0x00000000 there
// PURPOSE: To make sure all the shared memory regions are initialised correctly
// ----------------------------------------------------------------------------
void shm_dbg_memtest(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

  uint32_t *memptr;
  uint32_t *low_addr, *high_addr;

  // Calculate APP low and high address
  low_addr = (uint32_t*)mem->vbase;
  high_addr = (uint32_t*)((uint64_t)mem->vbase + mem->memsize);

  // Start writer
  for(memptr = low_addr; memptr < high_addr; memptr++) {
      *memptr = 0xCAFEBABE;
  }

  FUNC_CALL_ENTRY;
}


// ----------------------------------------------------------------
// Send Unordered Msg (usmg) send_umsg(char* umsg)
// Fast simplex link to CCI for sending unordered messages to CAFU
// ----------------------------------------------------------------
// Added      : Tue Aug  2 15:19:45 PDT 2011
// Purpose    : CCI 1.8 message additions
// Parameters : "4 bit umsg id     " Message ID
//              "64 byte char array" message
// Action     : Form a message and send it down a message queue
// ----------------------------------------------------------------
void send_msg(uint32_t msg_id, char* umsg)
{
  FUNC_CALL_ENTRY;

  char umsg_str[ASE_MQ_MSGSIZE];

  // Sanity check on msg_id
  msg_id = msg_id && 0x0F;

  // Sanity check on message size (<=64, padded by '\0')
  // TBD

  // UMsg packet
  //  +------+-------------+
  //  |msg_id|    data     |
  //  +------+-------------+

#ifdef ASE_MQ_ENABLE
  // Open message queue
  app2dpi_umsg_tx = mqueue_create(APP2DPI_UMSG_SMQ_PREFIX, O_WRONLY);

  // Form  message and send
  sprintf(umsg_str, "%u %s", msg_id, umsg);
  mqueue_send(app2dpi_umsg_tx, umsg_str);

  // Close message queue
  mqueue_close(app2dpi_umsg_tx);
#endif  

  FUNC_CALL_EXIT;
}


