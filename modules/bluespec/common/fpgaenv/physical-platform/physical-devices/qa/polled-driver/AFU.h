#ifndef AFU_H
#define AFU_H

#include <time.h>
#include <vector>
#include <aalsdk/ccilib/CCILib.h>
#include <aalsdk/aalclp/aalclp.h>
#include "AFU_csr.h"

#define CSR_CIPUCTL 0x280

USING_NAMESPACE(std)
USING_NAMESPACE(CCILib)

struct AFUBuffer
{
    ICCIWorkspace    *workspace;
    volatile uint8_t *virtual_address;
    btPhysAddr        physical_address;
    uint64_t          num_bytes;
};


class AFU {

public:

  // CCI_AAL     = AAL AFU implementation.
  // CCI_ASE     = AFU Simulation Environment implementation.
  // CCI_DIRECT  = Direct CCI driver implementation.

  AFU(const uint32_t *expected_afu_id, CCIDeviceImplementation imp=CCI_ASE, uint32_t dsm_size_bytes=4096);

  ~AFU();

  AFUBuffer* create_buffer(uint32_t size_bytes);
  AFUBuffer* create_buffer_aligned(uint32_t size_bytes);

  inline volatile void *dsm_address(uint32_t offset) {
    return (void *)(dsm_buffer->virtual_address + offset);
  }

  inline volatile uint32_t read_dsm(uint32_t offset) {
    return *(volatile uint32_t *)(dsm_buffer->virtual_address + offset);
  }

  inline volatile uint64_t read_dsm_64(uint64_t offset) {
    return *(volatile uint64_t *)(dsm_buffer->virtual_address + offset);
  }

  inline bool write_csr(btCSROffset offset, bt32bitCSR value) {
    return pCCIDevice->SetCSR(offset, value);
  }

  inline bool write_csr_64(btCSROffset offset, bt64bitCSR value) {
    bool result = pCCIDevice->SetCSR(offset + 4, value >> 32);
    result |= pCCIDevice->SetCSR(offset, value & 0xffffffff);
    return result;
  }

  inline long time_diff_ns() {
    long now_ns = gettime_in_ns();
    long time_diff = now_ns - prev_time_ns;
    prev_time_ns = now_ns;
    return time_diff;
  }

  inline long gettime_in_ns() {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return now.tv_sec * 1e9 + now.tv_nsec;
  }

  void reset_afu();

private:
  ICCIDeviceFactory *pCCIDevFactory;
  ICCIDevice *pCCIDevice;
  std::vector<AFUBuffer *> buffers;
  AFUBuffer *dsm_buffer;
  long prev_time_ns;
};

#endif
