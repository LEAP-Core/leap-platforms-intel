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
// -----------------------------------------------------------------------
// CCI to memory translator (DPI-C side)
// Author: Rahul R Sharma
//         Intel Corporation
//
// -----------------------------------------------------------------------
// This is a set of functions that form the DPI-C side interface,
// These functions are used to translate Cache line transactions to memory
// WARNING: ***This file must not be edited*** 
//
// -----------------------------------------------------------------------

#include "ase_common.h"
//#include "svdpi.h"

/* #define THIS_IS_DPI */

// ---------------------------------------------------------------
// DPI-C export(C to SV) calls
// ---------------------------------------------------------------
extern void simkill();
extern void cci_ase2cafu_csr_ch0(int, int, char*);
extern void cci_ase2cafu_rdResp_ch0(int, int, char*);
extern void cci_ase2cafu_wrResp_ch0(int, int, char*);
extern void cci_ase2cafu_ch1(int, int);


// ---------------------------------------------------------------
// DPI-C import(SV to C) calls
// ---------------------------------------------------------------
int ase_init();
int csr_write_listener();
int buffer_replicator();
int cci_rdline_req(int, int);
int cci_wrline_req(int, int, char*);
void cci_intr_int(int);

// Sim-kill function
void start_simkill_countdown();

// ---------------------------------------------------------------
// Message queues descriptors
// ---------------------------------------------------------------
mqd_t app2dpi_rx;           // app2dpi mesaage queue in RX mode
mqd_t dpi2app_tx;           // dpi2app mesaage queue in TX mode
mqd_t app2dpi_csr_wr_rx;    // CSR Write listener MQ in RX mode
mqd_t app2dpi_umsg_rx;      // UMsg receiver pipe 


// -----------------------------------------------------------------------
// CSR write listener THREAD
// -----------------------------------------------------------------------
int csr_write_listener()
{
  FUNC_CALL_ENTRY;

  // Message string
  char csr_wr_str[ASE_MQ_MSGSIZE];
  char *pch;
  char dpi_msg_data[CL_BYTE_WIDTH];
  
  // csr_offset and csr_data
  uint32_t csr_offset;
  uint32_t csr_data;
  
  // Cleanse receptacle string
  memset(dpi_msg_data, '\0', sizeof(dpi_msg_data));

      // Receive csr_write packet
      if(mqueue_recv(app2dpi_csr_wr_rx, (char*)csr_wr_str)==1)
      {
              // Tokenize message to get CSR offset and data
              pch = strtok(csr_wr_str, " ");
              csr_offset = atoi(pch);
              pch = strtok(NULL, " ");
              csr_data = atoi(pch);
    
              // Write CSR data to CSR pinned region
              // TBD      
        
              // Check if offset (28th July 2011):
              // If offset lies in QLP, print a message
              // Else, write CSR data via CH0 to CAFU (or SPL + AFU)
              if(csr_offset < 0x900)
        	{
        	  printf("SIM-C : CSR offset %04x is in QLP\n", csr_offset);
        	}
              else
        	{
        	  // Write to CH0
        	  cci_ase2cafu_csr_ch0(ASE_RX0_CSR_WRITE, csr_offset, (unsigned char*)&csr_data);
        	}          
              // Log event, if OK to do so
        #ifdef ASE_CCI_TRANSACTION_LOGGER
              ase_cci_logger("CSR_Write", NULL, 0, csr_offset, csr_offset, (unsigned char*)&csr_data);
        #endif
       }

  FUNC_CALL_EXIT;
  return 0;
}


// ----------------------------------------------------------------------
// Unordered message (Umsg) listener 
// Added : Tue Aug  2 15:32:23 PDT 2011
// Action: Opens message queue and listens for incoming UMsg requests
//         Writes such messages to DPI-SV side
// ----------------------------------------------------------------------
void* dpi_umsg_listnener()
{
  FUNC_CALL_ENTRY;

  // Message string
  char umsg_str[ASE_MQ_MSGSIZE];
  char *pch;

  // Umsg parameters
  uint32_t dpi_umsg_id;
  char dpi_umsg_data[CL_BYTE_WIDTH];

  // Keep checking message queue
  while(1)
    {
      // Cleanse receptacle string
      memset(dpi_umsg_data, '\0', sizeof(dpi_umsg_data));

      // Receive umsg packet
      mqueue_recv(app2dpi_umsg_rx, (char*)umsg_str);

      // Tokenize umsg_id and umsg_data
      pch = strtok(umsg_str, " ");
      dpi_umsg_id = atoi(pch);
      pch = strtok(NULL, " ");
      strcpy(dpi_umsg_data, pch);

      // Write to CH0
      cci_ase2cafu_rdResp_ch0(ASE_RX0_UMSG, dpi_umsg_id, (unsigned char*)&dpi_umsg_data);
    }

  // Log event, if OK
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("UMsg", dpi_umsg_data, 0, NULL, NULL, (unsigned char*)&dpi_umsg_data);
#endif

  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------------------
// vbase/pbase exchange THREAD
// when an allocate request is received, the buffer is copied into a
// linked list. The reply consists of the pbase, fakeaddr and fd_dpi.
// When a deallocate message is received, the buffer is invalidated.
// -----------------------------------------------------------------------
int buffer_replicator()
{
  FUNC_CALL_ENTRY;

  // DPI buffer
  struct buffer_t dpi_buffer;

      // Prepare an empty buffer
      dpi_empty_buffer(&dpi_buffer);
      // Receive a DPI message and get information from replicated buffer
      if (dpi_recv_msg(&dpi_buffer)==1)
      {
        #ifdef ASE_BUFFER_VIEW
              ase_buffer_info(&dpi_buffer);
        #endif
              // LLOC request received
              if(dpi_buffer.metadata == HDR_MEM_ALLOC_REQ)
        	{
        	  dpi_alloc_action(&dpi_buffer);
        	}
              // if DEALLOC request is received 
              else if(dpi_buffer.metadata == HDR_MEM_DEALLOC_REQ)
        	{
        	  dpi_dealloc_action(&dpi_buffer);
        	}
       }
        #ifdef ASE_LL_VIEW
              ll_traverse_print();
        #endif

  FUNC_CALL_EXIT;
  return 0;
}


// -----------------------------------------------------------------
// DPI Read Line Request service routine
// - Convert CL address to vaddr
// - Mem-copy data and send back
// -----------------------------------------------------------------
int cci_rdline_req(int cl_rd_addr, int mdata)
{
  FUNC_CALL_ENTRY;
  
  // Temporaty variables  
  uint64_t fake_rd_addr = 0;
  uint64_t* rd_target_vaddr = (uint64_t*) NULL;
  unsigned char read_cl_data[CL_BYTE_WIDTH], flip_read_data[CL_BYTE_WIDTH];
  uint32_t cl_iter;

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("RD_Line", mdata, 0, cl_rd_addr, 0, NULL);
#endif

  // Fake CL address to fake address conversion
  fake_rd_addr = (uint64_t)cl_rd_addr << 6;

  // Calculate "honest to God" DPI address using Shim
  rd_target_vaddr = dpi_fakeaddr_to_vaddr((uint64_t)fake_rd_addr);

  // Copy data from memory
  memcpy(read_cl_data, rd_target_vaddr, CL_BYTE_WIDTH);

  // Print info, either detail or succint
#ifdef ASE_CL_VIEW
  printf("SIM-C : CL view -> RDLINE vaddr = %p, paddr = %x\n", rd_target_vaddr, fake_rd_addr);
  printf("SIM-C : CL data -> ");
  for(cl_iter = 0; cl_iter < CL_BYTE_WIDTH; cl_iter++)
    printf("%02x", (unsigned char)read_cl_data[cl_iter]);
  printf("\n"); 
#else
   printf("SIM-C : READ  -> CL addr = %x, meta = %d\n", cl_rd_addr, mdata);
#endif

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
   ase_cci_logger("RD_Resp", mdata, 0, cl_rd_addr, (uint64_t)rd_target_vaddr, (unsigned char*)&read_cl_data);
#endif

  // Send data back as a response
  cci_ase2cafu_rdResp_ch0(ASE_RX0_RD_RESP, mdata, read_cl_data);


  FUNC_CALL_EXIT;
  return 0;
}


// -----------------------------------------------------------------
// DPI interrupt request management
// -----------------------------------------------------------------
int dpi_intr_req(int intr_id)
{
  FUNC_CALL_ENTRY;
  
  // Log event
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("Intr_Request", intr_id, 1, 0, null_str);
#endif

  // Mqueue send out 
  // TBD

  printf("SIM-C : Interrupt with ID = %d requested \n", intr_id);

  // Send interrupt response
   if(rand()%2 == 0)
     {
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("Intr_Resp", intr_id, 0, 0, (unsigned char*) null_str);
      #endif
      cci_ase2cafu_rdResp_ch0(ASE_RX0_INTR_CMPLT, intr_id, (unsigned char*) null_str);
    }
  else
    {
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("Intr_Resp", intr_id, 1, 0, (unsigned char*) null_str);
      #endif
      cci_ase2cafu_ch1(ASE_RX0_INTR_CMPLT, intr_id);
    }

  FUNC_CALL_EXIT;
  return 0;
}


// -----------------------------------------------------------------
// DPI Write Line Request service routine
// - Convert CL address to vaddr
// - Mem-copy received data to memory
// -----------------------------------------------------------------
int cci_wrline_req(int cl_wr_addr, int mdata,  char *wr_data)
{
  FUNC_CALL_ENTRY;

  // Temporary variables
  uint64_t fake_wr_addr = 0;
  uint64_t* wr_target_vaddr = (uint64_t*)NULL;
  char write_cl_data[CL_BYTE_WIDTH];
  uint32_t cl_iter;

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("WR_Line", mdata, 1, cl_wr_addr, 0, wr_data);
#endif

  // Copy incoming data to known size string (solving memcpy hose-up)
  memcpy((unsigned char*) write_cl_data, (unsigned char*) wr_data, CL_BYTE_WIDTH);

  // Calculate fake write address
  fake_wr_addr = (uint64_t)cl_wr_addr << 6;

  // Calculate "honest to God" DPI address using Shim
  wr_target_vaddr = dpi_fakeaddr_to_vaddr((uint64_t)fake_wr_addr);

  // Copy data to memory
  memcpy(wr_target_vaddr, write_cl_data, CL_BYTE_WIDTH);
  //  for(cl_iter = 0; cl_iter < CL_BYTE_WIDTH; cl_iter++)
  //    wr_target_vaddr[cl_iter] = wr_data[cl_iter];

  // Send response back on some random channel if enabled
  int chanRand = rand()%10;
  //int chanRand = 1;
  if(chanRand < 1)
    //if(0)
    {
      // Log data if OK to do so
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("WR_Resp", mdata, 0, cl_wr_addr, wr_target_vaddr, NULL);
      #endif
      cci_ase2cafu_wrResp_ch0(ASE_RX0_WR_RESP, mdata, (unsigned char*)null_str);
    }
  else
    {
      // Log data if OK to do so
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("WR_Resp", mdata, 1, cl_wr_addr, (uint64_t)wr_target_vaddr, NULL);
      #endif
      cci_ase2cafu_ch1(ASE_RX1_WR_RESP, mdata);
    }


  // Print info
#ifdef ASE_CL_VIEW
  printf("SIM-C : CL view -> WrLine vaddr = %p, paddr = %x\n", wr_target_vaddr, fake_wr_addr);
  printf("SIM-C : CL data -> ");
  for(cl_iter = 0; cl_iter < CL_BYTE_WIDTH; cl_iter++)
    printf("%02x", (unsigned char)write_cl_data[cl_iter]);
  printf("\n"); 
#else
  printf("SIM-C : WRITE -> CL addr = %x, meta = %d, Chan = %d\n", cl_wr_addr, mdata, chanRand);
#endif

  FUNC_CALL_EXIT;
  return 0;
}


// -----------------------------------------------------------------------
// DPI Initialize routine
// - Setup message queues
// - Start buffer replicator, csr_write listener thread
// -----------------------------------------------------------------------
int ase_init()
{
  FUNC_CALL_ENTRY;

  // RRS: Wed Oct 16 17:35:23 PDT 2013
  // RRS: Environment variable instructions
  char *tstamp_env;
  tstamp_env = malloc(80);

  // Generate timstamp
  put_timestamp();

  // Print timestamp
  printf("SIM-C : Timestamp => %s\n", get_timestamp() );

  // Define a null string
  memset(null_str, 64, '\0');
  shim_called = 0;
  fake_off_low_bound = 0;

  // Create IPC cleanup setup
#ifdef SIM_SIDE
  create_ipc_listfile();
#endif

  // ------------------------------------------------------------
  // If transaction logger is enabled
  // ------------------------------------------------------------
#ifdef ASE_CCI_TRANSACTION_LOGGER
  // Reset transaction logger 
  ase_cci_transact_count = 0;
  
  // Generate reference time stamps to be used in CCI logger
  gettimeofday(&start, NULL);
  ref_anchor_time = start.tv_sec*1000000 + start.tv_usec;

  // Open the log file for writing
  ase_cci_log_fd = fopen(CCI_LOGNAME, "wb");

  // Write headings into log file
  fprintf(ase_cci_log_fd, "Transact No.\t");
  fprintf(ase_cci_log_fd, "Timestamp\t");
  fprintf(ase_cci_log_fd, "Channel\t");
  fprintf(ase_cci_log_fd, "Trans. Name\t");
  fprintf(ase_cci_log_fd, "CL_address\t");
  fprintf(ase_cci_log_fd, "Virt. address\t");
  fprintf(ase_cci_log_fd, "Mdata\t");
  fprintf(ase_cci_log_fd, "Data\t");
  fprintf(ase_cci_log_fd, "\n");
#endif

  // Set up message queues
  printf("SIM-C : Set up DPI message queues...\n");
  dpi_mqueue_setup();

  // Random number for csr_pinned_addr
  srand(time(NULL));

  // Enable kill-switch timer
  BEGIN_GREEN_FONTCOLOR;
  printf("SIM-C : Ready for simulation...\n");
  // Write the following two lines in RED
  printf("SIM-C : ** INSTRUCTIONS : BEFORE running the software application => **\n"); 
  tstamp_env = getenv("PWD");
  printf("SIM-C : Set environment variable ASE_WORKDIR to '%s'\n", tstamp_env);
  END_GREEN_FONTCOLOR;

  // Register SIGINT and listen to it
  signal(SIGINT, start_simkill_countdown);  
  printf("SIM-C : Press CTRL-C to close simulator...\n");

  FUNC_CALL_EXIT;
  return 0;
}


// -----------------------------------------------------------------------
// DPI simulation timeout counter
// - When CTRL-C is pressed, start teardown sequence
// - TEARDOWN SEQUENCE:
//   > Close and unlink message queues
//   > Close and unlink shared memories
//   > Destroy linked list
//   > Kill threads
//   > Send $finish to VCS
// -----------------------------------------------------------------------
void start_simkill_countdown()
{
  FUNC_CALL_ENTRY;

  // Close and unlink message queue
  printf("SIM-C : Closing message queue and unlinking...\n");
  dpi_mqueue_teardown();

  // Destroy all open shared memory regions
  printf("SIM-C : Unlinking Shared memory regions.... \n");
  dpi_destroy();

  // Cloe log file, if appropriate
#ifdef ASE_CCI_TRANSACTION_LOGGER
  fclose(ase_cci_log_fd);
#endif

  // *FIXME* Remove the ASE timestamp file
  if (unlink(TSTAMP_FILENAME) == -1)
    {
      printf("SIM-C : %s could not be deleted, please delete manually... \n", TSTAMP_FILENAME);
    }

  // Final clean of IPC
#ifdef SIM_SIDE
  final_ipc_cleanup();
#endif

  // Send a simulation kill command
  printf("SIM-C : Sending kill command...\n");
  simkill();

  FUNC_CALL_EXIT;
}


