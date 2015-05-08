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
 * Module Info: Message queue functions
 * Language   : System{Verilog} | C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 */

#include "ase_common.h"

// Message queue attribute (optional use)
struct mq_attr attr;

// ----------------------------------------------------------------
// mqueue_create: Create a simplex mesaage queue by passing a name
// ----------------------------------------------------------------
mqd_t mqueue_create(char* mq_name_prefix, int perm_flag)
{
  FUNC_CALL_ENTRY;
  mqd_t mq;

  char *mq_name;
  mq_name = malloc (ASE_MQ_NAME_LEN);

  // Form a unique message queue name
  memset(mq_name, '\0', ASE_MQ_NAME_LEN); // sizeof(mq_name));
  strcpy(mq_name, mq_name_prefix);
  strcat(mq_name, get_timestamp(0));

  // Open a queue with default parameters
  mq = mq_open(mq_name, perm_flag, 0666, NULL);
  if(mq == -1)
    {
      ase_error_report("mq_open", errno, ASE_OS_MQUEUE_ERR);
      /* perror("mq_open"); */
#ifdef SIM_SIDE
      ase_perror_teardown();
      start_simkill_countdown();
#else
      exit(1); // APP-side exit
#endif
    }

  // Get the attributes of MQ
  if(mq_getattr(mq, &attr) == -1)
    {
      ase_error_report("mq_getattr", errno, ASE_OS_MQUEUE_ERR);
      /* perror("mq_getattr"); */
#ifdef SIM_SIDE
      ase_perror_teardown();
      start_simkill_countdown();
#else
      exit(1); // APP-side exit
#endif
    }

  // Update IPC list
#ifdef SIM_SIDE
  add_to_ipc_list("MQ", mq_name);
#endif

  //  printf("Created MQ: %s\n", mq_name);
  FUNC_CALL_EXIT;
  return mq;
}


// ---------------------------------------------------------------------
// mqueue_open : Added to accomodate timestamps when deallocate_buffer
// is called
// ----------------------------------------------------------------------
// TBD

// -------------------------------------------------------
// mqueue_close(mqd_t): close MQ by descriptor
// -------------------------------------------------------
void mqueue_close(mqd_t mq)
{
  FUNC_CALL_ENTRY;
  if(mq_close(mq) == -1)
    {
      ase_error_report("mq_close", errno, ASE_OS_MQUEUE_ERR);
#ifdef SIM_SIDE
      ase_perror_teardown();
      start_simkill_countdown();
#else
      exit(1); // APP-side exit
#endif
      /* perror("mq_close"); */
    }
  FUNC_CALL_EXIT;
}


// -----------------------------------------------------------
// mqueue_destroy(): Unlink message queue, must be called from API
// -----------------------------------------------------------
void mqueue_destroy(char* mq_name_prefix)
{
  FUNC_CALL_ENTRY;
  char *mq_name;
  mq_name = malloc (ASE_MQ_NAME_LEN);

  // Form a unique message queue name
  memset(mq_name, '\0', ASE_MQ_NAME_LEN); // sizeof(mq_name));
  strcpy(mq_name, mq_name_prefix);
  strcat(mq_name, get_timestamp(0));

  if(mq_unlink(mq_name) == -1)
    {
      ase_error_report("mq_unlink", errno, ASE_OS_MQUEUE_ERR);
      /* perror("mq_unlink"); */
#ifdef SIM_SIDE
      ase_perror_teardown();
      start_simkill_countdown();
#else
      exit(1);  // APP-side exit
#endif
    }
  FUNC_CALL_EXIT;
}


// ------------------------------------------------------------
// mqueue_send(): Easy send function
// - Typecast any message as a character array and ram it in.
// ------------------------------------------------------------
void mqueue_send(mqd_t mq, char* str)
{
  FUNC_CALL_ENTRY;

  // Print message if enabled
  //#ifdef ASE_MSG_VIEW
#ifdef SIM_SIDE
  if (cfg->enable_asedbgdump)
    {
      BEGIN_YELLOW_FONTCOLOR;
      printf("ASE_msg sent  : %s\n", str);
      END_YELLOW_FONTCOLOR;
    }
#endif
  //#endif

  // Send message
  if(mq_send(mq, str, ASE_MQ_MSGSIZE, 0) == -1)
    {
      ase_error_report("mq_send", errno, ASE_OS_MQTXRX_ERR);
      /* perror("mq_send"); */
#ifdef SIM_SIDE
      ase_perror_teardown();
      start_simkill_countdown();
#else
      exit(1); // APP-side exit
#endif
    }

  FUNC_CALL_EXIT;
}


// ------------------------------------------------------------------
// mqueue_recv(): Easy receive function
// - Typecast message back to a required type
// ------------------------------------------------------------------

int mqueue_recv(mqd_t mq, char* str)
{
  FUNC_CALL_ENTRY;

   struct mq_attr stat_attr;

   if(mq_getattr(mq, &stat_attr) == -1)
   {
        /* perror("mq_getattr"); */
     ase_error_report("mq_getattr", errno, ASE_OS_MQUEUE_ERR);
#ifdef SIM_SIDE
     ase_perror_teardown();
     start_simkill_countdown();
#else
     exit(1); // APP-side exit
#endif
   }


//  printf("M Q current msgs= %d",stat_attr.mq_curmsgs);
  if(stat_attr.mq_curmsgs>0)
  {
          // Message receive
          if(mq_receive(mq, str, ASE_MQ_MSGSIZE, 0) == -1)
            {
	      ase_error_report("mq_receive", errno, ASE_OS_MQTXRX_ERR);
              /* perror("mq_receive"); */
        #ifdef SIM_SIDE
              ase_perror_teardown();
	      start_simkill_countdown();
        #else
              exit(1);  // APP-side exit
        #endif
            }

          // Print message if enabled
	  //#ifdef ASE_MSG_VIEW
        #ifdef SIM_SIDE
	  if (cfg->enable_asedbgdump)
	    {
	      BEGIN_YELLOW_FONTCOLOR;
	      printf("ASE_msg recvd : %s\n", str);
	      END_YELLOW_FONTCOLOR;
	    }
        #endif
	  //#endif
        FUNC_CALL_EXIT;
        return 1;
   }
   else
   {
        FUNC_CALL_EXIT;
        return 0;
   }
}
