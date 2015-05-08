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
 * Module Info: Linked List memory buffer controls
 * Language   : C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 */

#include "ase_common.h"

// --------------------------------------------------------------------
// ll_print_info: Print linked list node info
// Thu Oct  2 15:50:06 PDT 2014 : Modified for cleanliness
// --------------------------------------------------------------------
void ll_print_info(struct buffer_t *print_ptr)
{
  FUNC_CALL_ENTRY;

  printf("%d  ", print_ptr->index);
  if (print_ptr->valid == ASE_BUFFER_VALID) 
    printf("ADDED   ");
  else
    printf("REMOVED ");
  printf("%5s \t", print_ptr->memname);
  printf("%p  ", (uint32_t*)print_ptr->vbase);
  printf("%p  ", (uint32_t*)print_ptr->pbase);
  printf("%p  ", (uint32_t*)print_ptr->fake_paddr);
  printf("%x  ", print_ptr->memsize);
  printf("%d  ", print_ptr->is_dsm);
  printf("%d  ", print_ptr->is_privmem);
  printf("\n");

  FUNC_CALL_EXIT;
}


// ---------------------------------------------------------------
// ll_traverse_print: Traverse and print linked list data
// ---------------------------------------------------------------
void ll_traverse_print()
{
  FUNC_CALL_ENTRY;
  struct buffer_t *traverse_ptr;

  printf("Starting linked list traversal from 'head'..\n");
  traverse_ptr = head;
  while (traverse_ptr != NULL)
    {
      ll_print_info(traverse_ptr);
      traverse_ptr = traverse_ptr->next;
    }

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------------
// ll_append_buffer :  Append a buffer to linked list
// A buffer must be allocated before this function is called
// --------------------------------------------------------------------
void ll_append_buffer(struct buffer_t *new)
{
  FUNC_CALL_ENTRY;

  // If there are no nodes in the list, set the new buffer as head
  if (head == NULL)
    {
      head = new;
      end = new;
    }
  // Link the new new node to the end of the list
  end->next = new;
  // Set the next field as NULL
  new->next = NULL;
  // Adjust end to point to last node
  end = new;

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------------
// ll_remove_buffer : Remove a buffer (relink remaining)
// Use ll_search_buffer() to pin-point the deletion target first.
// --------------------------------------------------------------------
void ll_remove_buffer(struct buffer_t *ptr)
{
  FUNC_CALL_ENTRY;

  struct buffer_t *temp, *prev;
  // node to be deleted
  temp = ptr;
  // Reset linked list traversal
  prev = head;
  // If first node is to be deleted
  if(temp == prev)
    {
      // Move head to next node
      head = head->next;
      // If there is only one node in the linked list
      if(end == temp)
	end = end->next;

      // Causes error here - hemce on #ifdef
#ifdef ENABLE_FREE_STATEMENT
      free((void*)temp);
#endif

    }
  else // If not the first node
    {
      // Traverse until node is found
      while(prev->next != temp)
	{
	  prev = prev->next;
	}
      // Link previous node to next node
      prev->next = temp->next;
      // If this is the end node, reset the end pointer
      if(end == temp)
	end = prev;

      // Causes error here - hemce on #ifdef
#ifdef ENABLE_FREE_STATEMENT
      free((void*)temp);
#endif
    }

  FUNC_CALL_EXIT;
}


// --------------------------------------------------------------------
// search_buffer_ll : Search buffer by ID
// Pass the head of the linked list along when calling
// --------------------------------------------------------------------
struct buffer_t* ll_search_buffer(int search_index)
{
  FUNC_CALL_ENTRY;

  struct buffer_t* search_ptr;

  // Start searching from the head
  search_ptr = head;

  // Traverse linked list starting from head
  while(search_ptr->index != search_index)
    {
      search_ptr = search_ptr->next;
      if(search_ptr == NULL)
	break;
    }

  // When found, return pointer to buffer
  return search_ptr;

  FUNC_CALL_EXIT;
}


/*
 * Check if physical address is used
 * RETURN 0 if not found, 1 if found
 */
uint32_t check_if_physaddr_used(uint64_t paddr)
{
  struct buffer_t *search_ptr;
  int flag = 0;

  search_ptr = head;
  while(search_ptr != NULL)
    {
      if ( (paddr >= search_ptr->fake_paddr) && (paddr < search_ptr->fake_paddr_hi) )
	{
	  flag = 1;
	  break;
	}
      else
	{
	  search_ptr = search_ptr->next;
	}
    }
  return flag;
}

