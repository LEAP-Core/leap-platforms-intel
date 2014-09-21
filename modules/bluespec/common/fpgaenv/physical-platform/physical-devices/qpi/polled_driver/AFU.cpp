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

  // write physical address of DSM to AFU CSR
  write_csr_64(CSR_AFU_DSM_BASE, dsm_buffer->physical_address);

  printf("Waiting for DSM update...\n");

  // poll AFU_ID until it is non-zero
  while (read_dsm(0) == 0) {}

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


void
AFU::reset_afu() {
  cci_csr_t csr;

  // Assert CAFU Reset
  csr = 0;
  pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
  csr |= 0x01000000;
  pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
  
  // De-assert CAFU Reset
  csr = 0;
  pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
  csr &= ~0x01000000;
  pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
}
