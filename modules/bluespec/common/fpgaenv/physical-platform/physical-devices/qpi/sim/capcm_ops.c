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
// Private memory access functions - C Module (no main() here)
// Author: Rahul R Sharma <rahul.r.sharma@intel.com>
//         Intel Corporation
//
// Revisions
// RRS         3rd Mar 2014      - Private memory subsystem, not connected to
//                                 linked list, private buffer only
//
// -------------------------------------------------------------------


#include "ase_common.h"

// -------------------------------------------------------------------
// capcm_init : Initialize a private memory buffer, not accessible
//              to software application
// CA-PCM is implemented as a region in /dev/shm
// This will also allow dumping to file if needed
// -------------------------------------------------------------------
void capcm_init(int capcm_num_cl)
{
  FUNC_CALL_ENTRY;
  
  // Create unique name (BASENAME + timestamp)
  memset(capcm_memname, '\0', 64);
  strcpy(capcm_memname, CAPCM_BASENAME);
  strcat(capcm_memname, get_timestamp() );

  // Initialize CAPCM byte size
  capcm_memsize = capcm_num_cl * CL_BYTE_WIDTH;

  // CAPCM Open & map
  capcm_fd = shm_open(capcm_memname, O_CREAT|O_RDWR, S_IREAD|S_IWRITE);
  if(capcm_fd < 0) 
    {
      perror("shm_open");
      exit(1);
    }

  // Add to IPC list
#ifdef SIM_SIDE
  add_to_ipc_list ("SHM", capcm_memname);
#endif

  // Mmap vbase to virtual space
  capcm_vbase = (uint64_t) mmap(NULL, capcm_memsize, PROT_READ|PROT_WRITE, MAP_SHARED, capcm_fd, 0);
  if(capcm_vbase == (uint64_t) MAP_FAILED) {
      perror("mmap");
      exit(1);
  }

  // Extend memory to required size
  ftruncate(capcm_fd, (off_t)capcm_memsize); 

  // Print info
  printf("CAPCM : QPI-FPGA CA Private memory READY, size = %d bytes\n", capcm_memsize);

  FUNC_CALL_EXIT;
}


// -------------------------------------------------------------------
// capcm_deinit : Deinitialize/civilized shutdown of CAPCM
//                /dev/shm closure as in shm_ops.c
// -------------------------------------------------------------------
void capcm_deinit()
{
  FUNC_CALL_ENTRY;

  int ret;
  char rm_shm_path[50];
  memset(rm_shm_path, '\0', sizeof(rm_shm_path));
  strcat(rm_shm_path, "rm -f /dev/shm");
  strcat(rm_shm_path, capcm_memname);

  ret = munmap((void*)capcm_vbase, (size_t)capcm_memsize);
  if(0 != ret) {
    perror("munmap");
    exit(1);
  }

  /* RRS: **FIXME** */
  // Unlink CAPCM
  /* if (shm_unlink(capcm_memname) != 0) */
  /*   perror("shm_unlink"); */

  // Remove shm related 
  /* system( rm_shm_path ); */
  
  // Print info
  printf("CAPCM : QPI-FPGA CA Private memory removed\n");

  FUNC_CALL_EXIT;
}


// -------------------------------------------------------------------
// capcm_rdline : CA-PCM read a line in private cached memory
// ------------------------------------------------------------------
void capcm_rdline_req(int cl_rd_addr, int mdata)
{
  FUNC_CALL_ENTRY;
  
  // Temporary variables
  uint64_t* rd_target_vaddr = (uint64_t*) NULL;
  unsigned char read_cl_data[CL_BYTE_WIDTH];
  uint32_t cl_iter;

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("CAPCM_RD_Line", mdata, 0, cl_rd_addr, 0, NULL);
#endif

  // Read address
  rd_target_vaddr = (uint64_t *)((uint64_t)capcm_vbase + cl_rd_addr);

  // Copy data from memory
  memcpy(read_cl_data, rd_target_vaddr, CL_BYTE_WIDTH );

  // Print info, either detail or succint
#ifdef ASE_CL_VIEW
  printf("SIM-C : CL view -> RDLINE vaddr = %p\n", rd_target_vaddr);
  printf("SIM-C : CL data -> ");
  for(cl_iter = 0; cl_iter < CL_BYTE_WIDTH; cl_iter++)
    printf("%02x", (unsigned char)read_cl_data[cl_iter]);
  printf("\n"); 
#else
   printf("SIM-C : READ  -> CL addr = %x, meta = %d\n", cl_rd_addr, mdata);
#endif

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
   ase_cci_logger("CAPCM_RD_Resp", mdata, 0, cl_rd_addr, (uint64_t)rd_target_vaddr, (unsigned char*)&read_cl_data);
#endif
   
   /* // Response  */
   /* capcm_rdline_resp(ASE_RX0_RD_RESP, mdata, read_cl_data); */

  // Send data back as a response
  cci_ase2cafu_rdResp_ch0(ASE_RX0_RD_RESP, mdata, read_cl_data);

   FUNC_CALL_EXIT;
}



// -------------------------------------------------------------------
// capcm_wrline : CA-PCM write a line in private cached memory
// -------------------------------------------------------------------
void capcm_wrline_req(int cl_wr_addr, int mdata, char* wr_data)
{
  FUNC_CALL_ENTRY;

  // Temporary variables
  uint64_t* wr_target_vaddr = (uint64_t*)NULL;
  char write_cl_data[CL_BYTE_WIDTH];
  uint32_t cl_iter;

  // Log event, if OK to do so
#ifdef ASE_CCI_TRANSACTION_LOGGER
  ase_cci_logger("CAPCM_WR_Line", mdata, 1, cl_wr_addr, 0, wr_data);
#endif

  // Copy incoming data to known size string (solving memcpy hose-up)
  memcpy((unsigned char*) write_cl_data, (unsigned char*) wr_data, CL_BYTE_WIDTH);

  wr_target_vaddr = (uint64_t *)((uint64_t)capcm_vbase + cl_wr_addr);

  // Copy data to memory
  memcpy(wr_target_vaddr, write_cl_data, CL_BYTE_WIDTH);

  // Send response back on some random channel if enabled
  int chanRand = rand()%10;
  if(chanRand < 1)
    //if(0)
    {
      // Log data if OK to do so
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("CAPCM_WR_Resp", mdata, 0, cl_wr_addr, wr_target_vaddr, NULL);
      #endif
      cci_ase2cafu_wrResp_ch0(ASE_RX0_WR_RESP, mdata, (unsigned char*)null_str);
    }
  else
    {
      // Log data if OK to do so
      #ifdef ASE_CCI_TRANSACTION_LOGGER
      ase_cci_logger("CAPCM_WR_Resp", mdata, 1, cl_wr_addr, (uint64_t)wr_target_vaddr, NULL);
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
}


