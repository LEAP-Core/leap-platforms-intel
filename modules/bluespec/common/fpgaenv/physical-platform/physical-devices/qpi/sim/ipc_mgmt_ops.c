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
 * Module Info: IPC management functions
 * Language   : C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 */ 


#include "ase_common.h"

// -----------------------------------------------------------------------
// create_ipc_listfile : Creates a log of IPC structures opened by
//                       this ASE session. This will be looked up so a
//                       civilized cleaning can be done
// -----------------------------------------------------------------------
void create_ipc_listfile()
{
  FUNC_CALL_ENTRY;

  local_ipc_fp = fopen(IPC_LOCAL_FILENAME, "w");
  if (local_ipc_fp == NULL) 
    {
      ase_error_report("fopen", errno, ASE_OS_FOPEN_ERR);
      printf("Local IPC file cannot be opened\n");
      start_simkill_countdown(); // RRS: exit(1);
    }
  else
    {
      printf("SIM-C : IPC Watchdog file %s opened\n", IPC_LOCAL_FILENAME);
    }
  
  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------------------
// add_to_ipc_list : Add record to IPC list
// -----------------------------------------------------------------------
void add_to_ipc_list(char *ipc_type, char *ipc_name)
{
  FUNC_CALL_ENTRY;
  int ret;

  // Add name to local IPC list
  ret = fprintf(local_ipc_fp, "%s\t%s\n", ipc_type, ipc_name);

  if (ret < 0)
    {
      BEGIN_RED_FONTCOLOR;
      printf("add_to_ipc_list: Failed to update IPC management file, cleanup may be incomplete\n");
      printf("                 Simulation will continue\n");
      END_RED_FONTCOLOR;
    }

  FUNC_CALL_EXIT;
}

// -----------------------------------------------------------------------
// final_ipc_cleanup : A second level check to see all the blocks are
//                     removed
// -----------------------------------------------------------------------
void final_ipc_cleanup()
{
  FUNC_CALL_ENTRY;
  char ipc_type[4];
  char ipc_name[40];

  // Close global/local files
  fclose(local_ipc_fp);

  // Reopen local IPC listfile
  local_ipc_fp = fopen(IPC_LOCAL_FILENAME, "r");
  if (local_ipc_fp == NULL) 
    {
      ase_error_report("fopen", errno, ASE_IPCKILL_CATERR);
      start_simkill_countdown(); // RRS: exit(1);
    }
  
  // Parse through list
  //  while(!feof(local_ipc_fp))
  while(1)
    {
      fscanf(local_ipc_fp, "%s\t%s", ipc_type, ipc_name);
      if (feof(local_ipc_fp))
	break;

      if (strcmp (ipc_type, "MQ") == 0)
	{
	  printf("        Removing MQ  %s ... ", ipc_name);
	  if ( mq_unlink(ipc_name) == -1 )
	    {
	      BEGIN_YELLOW_FONTCOLOR;
	      printf("Removed already !!\n");
	      END_YELLOW_FONTCOLOR;
	    }
	  else
	    {
	      BEGIN_YELLOW_FONTCOLOR;
	      printf("DONE\n");
	      END_YELLOW_FONTCOLOR;
	    }
	}	 
      else if (strcmp (ipc_type, "SHM") == 0)
	{
	  printf("        Removing SHM %s ... ", ipc_name);
	  if ( shm_unlink(ipc_name) == -1 )
	    {
	      BEGIN_YELLOW_FONTCOLOR;	    
	      printf("Already removed !!\n");
	      END_YELLOW_FONTCOLOR;
	    }
	  else
	    {
	      BEGIN_YELLOW_FONTCOLOR;	    
	      printf("DONE\n");
	      END_YELLOW_FONTCOLOR;
	    }
	}	 	
    }
  
  
  // Close both files
  fclose(local_ipc_fp);

  FUNC_CALL_EXIT;
}

