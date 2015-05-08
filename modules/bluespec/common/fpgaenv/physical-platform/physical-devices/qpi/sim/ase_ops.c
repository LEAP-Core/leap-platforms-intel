/// Copyright (c) 2014-2015, Intel Corporation
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
 * Module Info: ASE operations functions
 * Language   : C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 */

#include "ase_common.h"

struct buffer_t *head;
struct buffer_t *end;

uint64_t csr_fake_pin;

char null_str[CL_BYTE_WIDTH];

unsigned long int ase_cci_transact_count;

FILE *ase_cci_log_fd;

struct timeval start;
long int ref_anchor_time;
uint32_t shim_called;

uint64_t fake_off_low_bound;

// -----------------------------------------------------------
// ase_dump_to_file : Dumps a shared memory region into a file
// Dump contents of shared memory to a file
// -----------------------------------------------------------
int ase_dump_to_file(struct buffer_t *mem, char *dump_file)
{
  FILE *fileptr;
  uint32_t *memptr;

  // Open file
  fileptr = fopen(dump_file,"wb");
  if(fileptr == NULL)
    {
#ifdef SIM_SIDE
      ase_error_report ("fopen", errno, ASE_OS_FOPEN_ERR);
#else
      perror("fopen");
#endif
      return NOT_OK;
    }

  // Start dumping
  for(memptr=(uint32_t*)mem->vbase; memptr < (uint32_t*)(mem->vbase + mem->memsize); (uint32_t*)memptr++)
    fprintf(fileptr,"%08x : 0x%08x\n", (uint32_t)((uint64_t)memptr-(uint64_t)mem->vbase), *memptr);

  // Close file
  fclose(fileptr);
  return OK;
}


// -------------------------------------------------------------
// ase_buffer_info : Print out information about the buffer
// -------------------------------------------------------------
void ase_buffer_info(struct buffer_t *mem)
{
  FUNC_CALL_ENTRY;  
  
  BEGIN_YELLOW_FONTCOLOR;
  printf("Shared BUFFER parameters...\n");
  printf("\tfd_app      = %d \n",    mem->fd_app);
  printf("\tfd_ase      = %d \n",    mem->fd_ase);
  printf("\tindex       = %d \n",    mem->index);
  printf("\tvalid       = %x \n",    mem->valid);
  printf("\tAPPVirtBase = %p \n",    (uint32_t*)mem->vbase); 
  printf("\tSIMVirtBase = %p \n",    (uint32_t*)mem->pbase); 
  printf("\tBufferSize  = %x \n",    mem->memsize);  
  printf("\tBufferName  = \"%s\"\n", mem->memname);  
  printf("\tPhysAddr LO = %p\n", (uint32_t*)mem->fake_paddr); 
  printf("\tPhysAddr HI = %p\n", (uint32_t*)mem->fake_paddr_hi);
  printf("\tIsDSM       = %d\n", mem->is_dsm); 
  printf("\tIsPrivMem   = %d\n", mem->is_privmem); 
  BEGIN_YELLOW_FONTCOLOR;

  FUNC_CALL_EXIT;
}


/* 
 * ase_buffer_oneline : Print one line info about buffer
 */
void ase_buffer_oneline(struct buffer_t *mem)
{
  BEGIN_YELLOW_FONTCOLOR;

  printf("%d  ", mem->index);
  if (mem->valid == ASE_BUFFER_VALID) 
    printf("ADDED   ");
  else
    printf("REMOVED ");
  printf("%5s \t", mem->memname);
  printf("%p  ", (uint32_t*)mem->vbase);
  printf("%p  ", (uint32_t*)mem->pbase);
  printf("%p  ", (uint32_t*)mem->fake_paddr);
  printf("%x  ", mem->memsize);
  printf("%d  ", mem->is_dsm);
  printf("%d  ", mem->is_privmem);
  printf("\n");

  END_YELLOW_FONTCOLOR;
}


// -------------------------------------------------------------------
// buffer_t_to_str : buffer_t to string conversion
// Converts buffer_t to string 
// -------------------------------------------------------------------
void ase_buffer_t_to_str(struct buffer_t *buf, char *str)
{
  FUNC_CALL_ENTRY;

  // Initialise string to nulls
  memset(str, '\0', ASE_MQ_MSGSIZE);// strlen(str));

  if(buf->metadata == HDR_MEM_ALLOC_REQ)
    {
      // Form an allocate message request
      sprintf(str, "%d %d %s %d %ld %d %ld", buf->metadata, buf->fd_app, buf->memname, buf->valid, (long int)buf->memsize, buf->index, (long int)buf->vbase);
    }
  else if (buf->metadata == HDR_MEM_ALLOC_REPLY)
    {
      // Form an allocate message reply
      sprintf(str, "%d %d %ld %ld %ld", buf->metadata, buf->fd_ase, buf->pbase, buf->fake_paddr, buf->fake_paddr_hi);
    }
  else if (buf->metadata == HDR_MEM_DEALLOC_REQ)
    {
      // Form a deallocate request
      sprintf(str, "%d %d %s", buf->metadata, buf->index, buf->memname);
    }

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------
// ase_str_to_buffer_t : string to buffer_t conversion
// All fields are space separated, use strtok to decode
// --------------------------------------------------------------
void ase_str_to_buffer_t(char *str, struct buffer_t *buf)
{
  FUNC_CALL_ENTRY;

  char *pch;
  
  pch = strtok(str, " ");
  buf->metadata = atoi(pch);
  if(buf->metadata == HDR_MEM_ALLOC_REQ)
    {
      // Tokenize remaining fields of ALLOC_MSG
      pch = strtok(NULL, " ");
      buf->fd_app = atoi(pch);     // APP-side file descriptor
      pch = strtok(NULL, " ");
      strcpy(buf->memname, pch);   // Memory name
      pch = strtok(NULL, " ");
      buf->valid = atoi(pch);      // Indicates buffer is valid
      pch = strtok(NULL, " ");
      buf->memsize = atoi(pch);    // Memory size
      pch = strtok(NULL, " ");
      buf->index = atoi(pch);      // Buffer ID
      pch = strtok(NULL, " ");
      buf->vbase = atol(pch);      // APP-side virtual base
    }
  else if(buf->metadata == HDR_MEM_ALLOC_REPLY)
    {
      // Tokenize remaining 2 field of ALLOC_REPLY
      pch = strtok(NULL, " "); 
      buf->fd_ase = atoi(pch);     // DPI-side file descriptor
      pch = strtok(NULL, " "); 
      buf->pbase = atol(pch);      // DPI sude virtual address
      pch = strtok(NULL, " ");  
      buf->fake_paddr = atol(pch); // Fake physical address
      pch = strtok(NULL, " ");  
      buf->fake_paddr_hi = atol(pch); // Fake high point in offsets
    }
  else if(buf->metadata == HDR_MEM_DEALLOC_REQ)
    {
      pch = strtok(NULL, " ");
      buf->index = atoi(pch);      // Index
      pch = strtok(NULL, " ");
      strcpy(buf->memname, pch);   // Memory name
    }

  FUNC_CALL_EXIT;
}


// ---------------------------------------------------------------------
// ase_cci_logger : If enabled, this fumps all transactions as a
// tab-separated list into a log file. This file should show up as
// column-separated in Excel/OpenOffice/LibreOffice.
// NOTE: The timestamp is to be used as an indication of event
// arrival, and not for measure time betwen transactions. This is NOT
// a CYCLE ACCURATE SIMULATOR.
// ---------------------------------------------------------------------
/* void ase_cci_logger(char* transact_name, int mdata, int channel, uint32_t cl_addr, uint64_t vaddr, unsigned char* cl_data) */
/* { */
/*   // Time structure values */
/*   struct timeval event; */
/*   long int event_time; */
/*   int iter; */
/*   //unsigned char cline[CL_BYTE_WIDTH]; */

/*   // Print log number, followed by TAB */
/*   fprintf(ase_cci_log_fd, "%12ld\t", ase_cci_transact_count); */

/*   // Print timestamp differential, then a TAB */
/*   gettimeofday(&event, NULL); */
/*   event_time = event.tv_sec*1000000 + event.tv_usec; */
/*   fprintf(ase_cci_log_fd, "%9ld\t", (long int)(event_time - ref_anchor_time)); */

/*   // Print channel number, then a TAB */
/*   fprintf(ase_cci_log_fd, "%7d\t", channel); */

/*   // Print transaction name */
/*   fprintf(ase_cci_log_fd, "%11s\t", transact_name); */
  
/*   // Print address if appropriate */
/*   if(cl_addr != 0) */
/*     fprintf(ase_cci_log_fd, "%10x", cl_addr); */
/*   fprintf(ase_cci_log_fd, "\t"); */

/*   // Print Vaddr */
/*   fprintf(ase_cci_log_fd, "%013lx\t", vaddr); */

/*   // Print metadata, then TAB */
/*   fprintf(ase_cci_log_fd, "%05x\t", mdata); */

/*   // Print exchanged data, then TAB */
/*   //  fprintf(ase_cci_log_fd, "%128x\t", cl_data); */
/*   //  memcpy(cline, cl_data, CL_BYTE_WIDTH); */
/*   int data_size = 64-1; */
/*   if (strcmp(transact_name,"CSR_Write")==0) { */
/*     data_size = 4-1; */
/*   } */
  
/*   if (cl_data != NULL) { */
/*     for(iter = data_size; iter >= 0; iter--) { */
/*       fprintf(ase_cci_log_fd, "%02x", (unsigned char)cl_data[iter]);  */
/*     } */
/*   } */
/*   fprintf(ase_cci_log_fd, "\t");  */

/*   // Print next line */
/*   fprintf(ase_cci_log_fd, "\n"); */

/*   // Increment event counter */
/*   ase_cci_transact_count++; */
/* } */


/*
 * Generate 64-bit random number
 */
uint64_t ase_rand64()
{
  uint64_t random;
  random = rand();
  random = (random << 32) | rand();
  return random;
}
