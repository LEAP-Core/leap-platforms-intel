#include <iostream>
#include <string>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#include "AFU.h"

AFU::AFU(const uint32_t* expected_afu_id, CCIDeviceImplementation imp, uint32_t dsm_size_bytes) {
  prev_time_ns = gettime_in_ns();

  // create the CCI device factory and device
  pCCIDevFactory = GetCCIDeviceFactory(imp);
  pCCIDevice = pCCIDevFactory->CreateCCIDevice();

  // create buffer for DSM
  dsm_buffer = create_buffer(dsm_size_bytes);

  // reset AFU
  reset_afu();

  printf("Writing DSM base %llx ...\n", dsm_buffer->physical_address);

  // write physical address of DSM to AFU CSR
  write_csr_64(CSR_AFU_DSM_BASE, dsm_buffer->physical_address);

  printf("Waiting for DSM update...\n");

  // poll AFU_ID until it is non-zero

  while (read_dsm(0) == 0) {
    printf("Polling DSM...\n"); sleep(1);
  }

  // check AFU_ID against expected value
  for (int i = 0; i < 4; i++) {
    uint32_t afu_id = read_dsm(4*i);
    if (afu_id != expected_afu_id[i]) {
      printf("ERROR: AFU_ID[%d] = 0x%x, expected 0x%x\n", i, afu_id, expected_afu_id[i]);
      exit(1);
    }
  }

  cout << "Found expected AFU ID. AFU ready.\n";
}


AFU::~AFU() {
  // release all workspace buffers
  for (int i = 0; i < buffers.size(); i++) {
    pCCIDevice->FreeWorkspace(buffers[i]->workspace);
  }

  // release the CCI device factory and device
  pCCIDevFactory->DestroyCCIDevice(pCCIDevice);
  delete pCCIDevFactory;

  cout << "AFU released\n";
}


AFUBuffer* 
AFU::create_buffer(uint32_t size_bytes) {
  // create a buffer struct instance
  AFUBuffer* buffer = new AFUBuffer();

  // create buffer in memory and save info in struct
  buffer->workspace = pCCIDevice->AllocateWorkspace(size_bytes);
  buffer->virtual_address = buffer->workspace->GetUserVirtualAddress();
  buffer->physical_address = buffer->workspace->GetPhysicalAddress();
  buffer->num_bytes = buffer->workspace->GetSizeInBytes();

  // store buffer in vector, so it can be released later
  buffers.push_back(buffer);

  // set contents of buffer to 0
  memset((void *)buffer->virtual_address, 0, size_bytes);

  // return buffer struct
  return buffer;
}


AFUBuffer* 
AFU::create_buffer_aligned(uint32_t size_bytes) {
  // create a buffer struct instance
 
  // Check that the input is a power of two
  if(((size_bytes ^ (size_bytes - 1)) + 1) != 2 * size_bytes)
  {
      printf("Asked to align a non-power of two region, but this is not supported\n");
      exit(1);
  } 

  AFUBuffer* buffer = create_buffer(2 * size_bytes);

  printf(" Unaligned buffer: (virt) %p, (phy) %llx\n", buffer->virtual_address, buffer->physical_address);
  // Now, let's adjust the pointers to create alignment.
  // Note that we're aligning the PA to simplify the hardware. 
  btPhysAddr original_diff = ((uintptr_t)(buffer->virtual_address)) - buffer->physical_address;
  btPhysAddr aligned_addr = (btPhysAddr) (((buffer->physical_address + size_bytes)) & ~((btPhysAddr)size_bytes - 1)); 
  btPhysAddr byte_difference =   aligned_addr - buffer->physical_address;  
  buffer->physical_address = aligned_addr;

  // Align the virtual ptr based on the physical alignment.
  buffer->virtual_address = (uint8_t*) (((uintptr_t)(buffer->virtual_address) + byte_difference)); 

  printf(" Aligned buffer: (virt) %p, (phy) %llx\n", buffer->virtual_address, buffer->physical_address);

  btPhysAddr new_diff = ((uintptr_t)(buffer->virtual_address)) - buffer->physical_address;

  if (original_diff != new_diff)
  {
      printf("Original: %llx != new %llx\n", original_diff, new_diff);
  }

  // return buffer struct
  return buffer;
}


void
AFU::reset_afu() {
  bt32bitCSR csr;

  const uint32_t CIPUCTL_RESET_BIT = 0x01000000;

  // Assert CAFU Reset
  csr = 0;
  pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
  csr |= CIPUCTL_RESET_BIT;
  pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
  
  // De-assert CAFU Reset
  csr = 0;
  pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
  csr &= ~CIPUCTL_RESET_BIT;
  pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
}
