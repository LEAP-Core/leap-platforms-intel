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
// DPI specific operations (C module)
// Author: Rahul R Sharma
//         Intel Corporation
//
// Purpose: Keeping cci_to_mem_translator.c clutter free and modular
// test and debug. Includes message queue management by DPI.
// NOTE: These functions must be called by DPI side ONLY.
// ---------------------------------------------------------------------

#include "ase_common.h"

// Message queues opened by DPI
mqd_t app2dpi_rx;           // app2dpi mesaage queue in RX mode
mqd_t dpi2app_tx;           // dpi2app mesaage queue in TX mode
mqd_t app2dpi_csr_wr_rx;    // CSR Write listener MQ in RX mode
mqd_t app2dpi_umsg_rx;      // UMsg listener MQ in RX mode

// '1' indicates that teardown is in progress
int self_destruct_in_progress = 0;

// FPGA offset aggregator
uint64_t fpga_membase_so_far = 0;

// ---------------------------------------------------------------------
// dpi_mqueue_setup() : Set up DPI message queues
// Set up app2dpi_rx, dpi2app_tx and app2dpi_csr_wr_rx message queues
// ---------------------------------------------------------------------
void dpi_mqueue_setup()
{
  FUNC_CALL_ENTRY;

  mq_unlink(APP2DPI_SMQ_PREFIX);
  mq_unlink(DPI2APP_SMQ_PREFIX);
  mq_unlink(APP2DPI_CSR_WR_SMQ_PREFIX);
  mq_unlink(APP2DPI_UMSG_SMQ_PREFIX);

  // Depending on the calling function, activate the required queues
  app2dpi_rx        = mqueue_create(APP2DPI_SMQ_PREFIX,        O_CREAT|O_RDONLY);
  dpi2app_tx        = mqueue_create(DPI2APP_SMQ_PREFIX,        O_CREAT|O_WRONLY);
  app2dpi_csr_wr_rx = mqueue_create(APP2DPI_CSR_WR_SMQ_PREFIX, O_CREAT|O_RDONLY);
  app2dpi_umsg_rx   = mqueue_create(APP2DPI_UMSG_SMQ_PREFIX,   O_CREAT|O_RDONLY);

  FUNC_CALL_EXIT;
}


// ---------------------------------------------------------------------
// dpi_mqueue_teardown(): Teardown DPI message queues
// Close and unlink DPI message queues
// ---------------------------------------------------------------------
void dpi_mqueue_teardown()
{
  FUNC_CALL_ENTRY;

  // Close message queues
  mqueue_close(app2dpi_rx);       
  mqueue_close(dpi2app_tx);       
  mqueue_close(app2dpi_csr_wr_rx);
  mqueue_close(app2dpi_umsg_rx);

  // Unlink message queues
  mqueue_destroy(APP2DPI_SMQ_PREFIX);       
  mqueue_destroy(DPI2APP_SMQ_PREFIX);       
  mqueue_destroy(APP2DPI_CSR_WR_SMQ_PREFIX);
  mqueue_destroy(APP2DPI_UMSG_SMQ_PREFIX);

  FUNC_CALL_EXIT;
}


// ---------------------------------------------------------------
// DPI Self destruct - Called if: error() occurs 
// Deallocate & Unlink all shared memories and message queues
// ---------------------------------------------------------------
void dpi_perror_teardown()
{
  FUNC_CALL_ENTRY;

  // close the log file first, if exists
#ifdef ASE_CCI_TRANSACTION_LOGGER 
  printf("SIM-C : Terminating log file !!\n");
  fclose(ase_cci_log_fd);
#endif

  //printf("PERROR: Goodbye, Cruel World\n");
  self_destruct_in_progress++;

  if (!self_destruct_in_progress)
    {      
      // Deallocate entire linked list
      dpi_destroy();
      
      // Unlink all opened message queues
      dpi_mqueue_teardown();
    }

  FUNC_CALL_EXIT;
}


// ------------------------------------------------------------------
// DPI recv message - Set up DPI to receive an 'allocate' request msg
// Receive a string and return a buffer_t structure with memsize,
// memname and index populated. 
// NOTE: This function must be called by DPI
// ------------------------------------------------------------------
int dpi_recv_msg(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

 // Temporary buffer
  char tmp_msg[ASE_MQ_MSGSIZE];

  // Receive a message on mqueue
  if(mqueue_recv(app2dpi_rx, tmp_msg)==1)
  {
          // Convert the string to buffer_t
          ase_str_to_buffer_t(tmp_msg, mem);
          FUNC_CALL_EXIT;
          return 1;
  }
  else
  {
          FUNC_CALL_EXIT;
          return 0;
  }
}


// -------------------------------------------------------------------
// dpi_send_msg : Send a dpi reply 
// Convert a buffer_t to string and transmit string as a message
// -------------------------------------------------------------------
void dpi_send_msg(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

  // Temporary buffer
  char tmp_msg[ASE_MQ_MSGSIZE];

  // Convert buffer to string
  ase_buffer_t_to_str(mem, tmp_msg);

  // Send message out
  mqueue_send(dpi2app_tx, tmp_msg);

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------------
// DPI ALLOC buffer action - Allocate buffer action inside DPI
// Receive buffer_t pointer with memsize, memname and index populated
// Calculate fd, pbase and fake_paddr
// --------------------------------------------------------------------
void dpi_alloc_action(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;

  struct buffer_t *new_buf;

  printf("SIM-C : Adding a new buffer \"%s\"...\n", mem->memname);

  // Obtain a file descriptor
  mem->fd_dpi = shm_open(mem->memname, O_RDWR, S_IREAD|S_IWRITE);
  if(mem->fd_dpi < 0)
    {
      /* perror("shm_open"); */
      ase_error_report("shm_open", errno, ASE_OS_SHM_ERR);
      dpi_perror_teardown();
      exit(1);
    }

  // Add to IPC list
#ifdef SIM_SIDE
  add_to_ipc_list ("SHM", mem->memname);
#endif

  // Mmap to pbase, find one with unique low 38 bit
  mem->pbase = (uint64_t)mmap(NULL, mem->memsize, PROT_READ|PROT_WRITE, MAP_SHARED, mem->fd_dpi, 0);
  if(mem->pbase == (uint64_t)NULL)
    {
      ase_error_report("mmap", errno, ASE_OS_MEMMAP_ERR);
      /* perror("mmap"); */
      dpi_perror_teardown();
      exit(1);
    }
  ftruncate(mem->fd_dpi, (off_t)mem->memsize);

  // CALCULATE A FAKE PHYSICAL ADDRESS
  // Use the random number to generate a CSR pin 
  // Generate a fake_paddr based on this and an offset using memsize(s)
  if(mem->index == 0)
    {
      // Generate a pin address 38 bits wide and is 2MB aligned
      csr_fake_pin = abs((rand() << 21) & 0x0000001FFFFFFFFF);
      printf("SIM-C : CSR pinned fake_paddr = %p\n",(uint32_t*)csr_fake_pin);
      
      // Record DPI side CSR region virtual address
      dpi_csr_base = mem->pbase;
    }

  // Record fake address
  mem->fake_paddr = csr_fake_pin + fpga_membase_so_far;
  mem->fake_paddr_hi = mem->fake_paddr + mem->memsize;

  // Generate a fake offset
  mem->fake_off_lo = fake_off_low_bound;
  mem->fake_off_hi = fpga_membase_so_far + mem->memsize;

  // Calculate next low bound
  fake_off_low_bound = fake_off_low_bound + mem->memsize;

  // Received buffer is valid
  mem->valid = ASE_BUFFER_VALID;

  // Aggregate all memory offsets so far
  fpga_membase_so_far+= mem->memsize;

  // Create a buffer and store the information
  new_buf = malloc(BUFSIZE);
  memcpy(new_buf, mem, BUFSIZE);

  // Append to linked list
  ll_append_buffer(new_buf);

  // Reply to MEM_ALLOC_REQ message with MEM_ALLOC_REPLY
  // Set metadata to reply mode
  mem->metadata = HDR_MEM_ALLOC_REPLY;
  
  // Convert buffer_t to string
  dpi_send_msg(mem);

   // If memtest is enabled
#ifdef ASE_MEMTEST_ENABLE
  dpi_dbg_memtest(mem);
#endif

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------------
// DPI dealloc buffer action - Deallocate buffer action inside DPI
// Receive index and invalidates buffer
// --------------------------------------------------------------------
void dpi_dealloc_action(struct buffer_t *buf)
{
  FUNC_CALL_ENTRY;

  // Traversal pointer
  struct buffer_t *dealloc_ptr;

  // Search buffer and Invalidate
  dealloc_ptr = ll_search_buffer(buf->index);

  //  If deallocate returns a NULL, dont get hosed
  if(dealloc_ptr != NULL)
    {
      printf("SIM-C : Command to invalidate \"%s\" ...\n", dealloc_ptr->memname);
      dealloc_ptr->valid = ASE_BUFFER_INVALID;
    }
  else
    {
      printf("SIM-C : NULL deallocation request received ... ignoring.\n");
    }

  FUNC_CALL_EXIT;
}

// --------------------------------------------------------------------
// dpi_empty_buffer: create an empty buffer_t object
// Create a buffer with all parameters set to 0
// --------------------------------------------------------------------
void dpi_empty_buffer(struct buffer_t *buf)
{
  buf->fd_app = 0;
  buf->fd_dpi = 0;
  buf->index = 0;
  buf->valid = ASE_BUFFER_INVALID;
  buf->metadata = 0;
  strcpy(buf->memname, "");
  buf->memsize = 0;
  buf->vbase = (uint64_t)NULL;
  buf->pbase = (uint64_t)NULL;
  buf->fake_paddr = (uint64_t)NULL;
  buf->next = NULL;
}


// --------------------------------------------------------------------
// dpi_destroy : Destroy everything, called before exiting
// OPERATION:
// Traverse trough linked list
// - Remove each shared memory region
// - Remove each buffer_t 
// --------------------------------------------------------------------
void dpi_destroy()
{
  FUNC_CALL_ENTRY;

  struct buffer_t *ptr;
  int ret;

  char rm_shm_path[50];

  // Traverse through linked list
  ptr = head;
  while(ptr != NULL)
    {
      // Set rm_shm_path to NULLs
      memset(rm_shm_path, '\0', sizeof(rm_shm_path));

      // Unmap Shared memory
      ret = munmap((void*)ptr->pbase, (size_t)ptr->memsize);
      if (ret == -1)
	ase_error_report("munmap", errno, ASE_OS_MEMMAP_ERR);
      /* perror("munmap"); */

      // Unlink related shared memory region
      if(shm_unlink(ptr->memname) != 0)
	ase_error_report("shm_unlink", errno, ASE_OS_SHM_ERR);
	/* perror("shm_unlink"); */
      
      // Delete the SHM region
      strcat(rm_shm_path, "rm -f /dev/shm");
      strcat(rm_shm_path, ptr->memname);
      system( rm_shm_path );
      
      // Find and destroy node
      ll_remove_buffer(ptr);
      
      // Traverse to next node
      ptr = ptr->next;
    }
  
  FUNC_CALL_EXIT;
}


// ------------------------------------------------------------------------------
// dpi_dbg_memtest : A memory read write test (DEBUG feature)
// To run the test ASE_MEMTEST_ENABLE must be enabled.
// - This test runs alongside a process shm_dbg_memtest.
// - shm_dbg_memtest() is started before MEM_ALLOC_REQ message is sent to DPI
//   The simply starts writing 0xCAFEBABE to memory region
// - dpi_dbg_memtest() is started after the MEM_ALLOC_REPLY message is sent back
//   This reads all the data, verifies it is 0xCAFEBABE and writes 0x00000000 there
// PURPOSE: To make sure all the shared memory regions are initialised correctly
// -------------------------------------------------------------------------------
void dpi_dbg_memtest(struct buffer_t *mem)
{
  uint32_t *memptr;
  uint32_t *low_addr, *high_addr;

  // Memory test errors counter
  int memtest_errors = 0;

  // Calculate DPI low and high address
  low_addr = (uint32_t*)mem->pbase;
  high_addr = (uint32_t*)((uint64_t)mem->pbase + mem->memsize);

  // Start checker
  for(memptr = low_addr; memptr < high_addr; memptr++)
    {
      if(*memptr != 0xCAFEBABE)
	memtest_errors++;
      *memptr = 0x0;
    }

  // Print result
  if(memtest_errors == 0)
    {
      printf("SIM-C : MEMTEST -> Passed !!\n");
    }
  else
    {
      printf("SIM-C : MEMTEST -> Failed with %d errors !!\n", memtest_errors);
    }
}


// ---------------------------------------------------------------------
// Alternate memory shim
// ---------------------------------------------------------------------
uint64_t* dpi_fakeaddr_to_vaddr(uint64_t req_paddr)
{
  FUNC_CALL_ENTRY;
  
  // DPI pbase address
  uint64_t *dpi_pbase;
  
  // This is the real offset to perform read/write
  uint64_t real_offset, calc_pbase;
  
  // Traversal ptr
  struct buffer_t *trav_ptr;
  
  // Search which buffer offset_from_pin lies in
  trav_ptr = head;
  while(trav_ptr != NULL)
    {
      if((req_paddr >= trav_ptr->fake_paddr) && (req_paddr < trav_ptr->fake_paddr_hi))
	{
	  real_offset = req_paddr - trav_ptr->fake_paddr;
	  calc_pbase = trav_ptr->pbase;
	  dpi_pbase = (uint64_t*)(calc_pbase + real_offset);
	  return dpi_pbase;
	}
      else
	{
	  trav_ptr = trav_ptr->next;
	}
    }

  if(trav_ptr == NULL)
    {
      BEGIN_RED_FONTCOLOR;
      printf("@ERROR: ASE has detected a memory operation to an unallocated memory region.\n");
      printf("@ERROR: Simulation cannot continue, please check the code.\n");
      printf("@ERROR: Failure @ phys_addr = %lu | offset = %lu \n", req_paddr, real_offset);
      END_RED_FONTCOLOR;
      dpi_perror_teardown();
      final_ipc_cleanup();
      exit(1);
    }

  FUNC_CALL_EXIT;
}


