// Copyright (c) 2013-2014, Intel Corporation
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
#include "ase_common.h"


// -----------------------------------------------------------------------
// Timestamp based isolation
// -----------------------------------------------------------------------
#if defined(__i386__)
static __inline__ unsigned long long rdtsc(void)
{
  unsigned long long int x;
  __asm__ volatile (".byte 0x0f, 0x31" : "=A" (x));
  return x;
}
#elif defined(__x86_64__)
static __inline__ unsigned long long rdtsc(void)
{
  unsigned hi, lo;
  __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
  return ( (unsigned long long)lo)|( ((unsigned long long)hi)<<32 );
}
#else
#error "Host Architecture unidentified, timestamp wont work"
#endif


// -----------------------------------------------------------------------
// Write timestamp
// -----------------------------------------------------------------------
void put_timestamp()
{
  FILE *fp;
  unsigned long long tstamp_long;
  char tstamp_str[20];
  memset(tstamp_str, '\0', sizeof(tstamp_str));

  tstamp_long = rdtsc();

  fp = fopen(TSTAMP_PATH, "wb");
  if (fp == NULL) 
    {
#ifdef SIM_SIDE
      ase_error_report("fopen", errno, ASE_OS_FOPEN_ERR);
#else
      perror("fopen");
#endif
      exit(1);
    }
  fprintf(fp, "%lld", tstamp_long);

  fclose(fp);
}


// -----------------------------------------------------------------------
// Read timestamp 
// -----------------------------------------------------------------------
char* get_timestamp()
{
  FILE *fp;

  unsigned long long readback;

  char *tstamp_str;
  tstamp_str = malloc(20);

  // File stat attribute
  struct stat *filestat;
  
  char *tstamp_filepath;
  char *pot_pwd_filepath;
  char *pot_asewd_filepath;
  tstamp_filepath = malloc(256);
  pot_pwd_filepath = malloc(256);
  pot_asewd_filepath = malloc(256);
  memset(pot_pwd_filepath, '\0', sizeof(pot_pwd_filepath));
  memset(pot_asewd_filepath, '\0', sizeof(pot_asewd_filepath));
  FILE *fp_pwd;
  FILE *fp_asewd;

  // Create filepaths
  snprintf(pot_pwd_filepath, 256 , "%s/%s", getenv("PWD"), TSTAMP_FILENAME);
  fp_pwd = fopen(pot_pwd_filepath, "r");

  printf("SIM SIDE is: %d\n", SIM_SIDE);
  if (getenv("ASE_WORKDIR") != NULL)
    {
      snprintf(pot_asewd_filepath, 256, "%s/%s", getenv("ASE_WORKDIR"), TSTAMP_FILENAME);
      fp_asewd = fopen(pot_asewd_filepath, "r");
    }

  // *FIXME*
  // Find the timestamp file
  // - Check $PWD for file, if found bug out
  // - Check $ASE_WORKDIR for file, if found bug out
  // - If not found, ERROR out
  // Record filename
  if ( fp_pwd != NULL ) 
    {
      strcpy(tstamp_filepath, pot_pwd_filepath);
    }
  else if ( getenv("ASE_WORKDIR") != NULL ) 
    {
      // *FIXME* Check if file exists
      if (fp_asewd != NULL)
	{
	  strcpy(tstamp_filepath, pot_asewd_filepath); 
	}
      else
	{
	  printf("ASE timestamp file cannot be opened at %s ... EXITING !!\n", getenv("ASE_WORKDIR"));
	  exit(1);
	}
    }
  else
    {
      printf("ASE_WORKDIR environment variable has not been set up. EXITING !!\n");
      exit(1);
    }
  

  // fp = fopen(TSTAMP_PATH, "r");
  fp = fopen(tstamp_filepath, "r");
  if (fp == NULL) 
    {
#ifdef SIM_SIDE
      ase_error_report("fopen", errno, ASE_OS_FOPEN_ERR);
#else
      perror("fopen");
#endif
      exit(1);
    }
  
  fread(&readback, sizeof(unsigned long long), 1, fp);
  fclose(fp);
  
  sprintf(tstamp_str, "%lld", readback);

  return tstamp_str;
}

