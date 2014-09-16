//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

#ifndef __QPI_SOFTWARE_DRIVER__
#define __QPI_SOFTWARE_DRIVER__

#include "platforms-module.h"
#include "command-switches.h"
#include "asim/provides/umf.h"
#include "tbb/atomic.h"
#include <aalsdk/ccilib/CCILib.h>
#include <aalsdk/aalclp/aalclp.h>

// Local includes
#include "AFU.h"


#define STDIN             0
#define STDOUT            1
#define DESC_HOST_2_FPGA  100
#define DESC_FPGA_2_HOST  101
#define BLOCK_SIZE        UMF_CHUNK_BYTES 
#define SELECT_TIMEOUT    1000

// BUFFER SIZE and some macros for calculating it. These came from
// gspowley's smithwaterman code. 

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL                                                                                                                                                                       
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL                                                                                                                                                                  
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB                                                                                                                                                                       

#define CACHELINE_ALIGNED_ADDR(p)  ((p) >> LOG2_CL)
#define AFU_BUFFER_SIZE           CL(128)
#define DSM_SIZE                  MB(4)


#define AFU_BUFFER_SIZE           CL(128)

// DSM byte offset:                          0           4           8           c                                                                                                                        
const uint32_t EXPECTED_AFU_ID[] = {0xaced0000, 0xaced0001, 0xaced0002, 0xaced0003};

// ==============================================
//          QPI Physical Device, software driver
// ==============================================
typedef class QPI_DEVICE_CLASS* QPI_DEVICE;
class QPI_DEVICE_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    // switches for acquiring device uniquifier
    COMMAND_SWITCH_DICTIONARY deviceSwitch;

    // Handles to AFU context.
    CCIDeviceImplementation cci_imp; 
    AFU afu;

    // process/pipe state (physical channel)
    int                       inpipe[2], outpipe[2];
    int                       childpid;
    class tbb::atomic<bool>   childAlive;
    std::string               ioFile; 
    std::string               *logicalName; 
    pthread_t                 ReaderThreads[1];
    pthread_t                 WriterThreads[1];

    int ParentRead() const { return inpipe[0]; };
    int ParentWrite() const { return outpipe[1]; };
    int ChildRead() const { return outpipe[0]; };
    int ChildWrite() const { return inpipe[1]; };

    class tbb::atomic<UINT64> initReadComplete;
    class tbb::atomic<UINT64> initWriteComplete;

  public:
    QPI_DEVICE_CLASS(PLATFORMS_MODULE);
    ~QPI_DEVICE_CLASS();

    static void * openReadThread(void *argv);
    static void * openWriteThread(void *argv);

    void Init();
    void Cleanup();                    // cleanup
    void Uninit();                     // uninit
    bool Probe();                      // probe for data
    void Read(unsigned char*, int);    // blocking read
    void Write(unsigned char*, int);   // write
    void RegisterLogicalDeviceName(string name);
};

#endif
