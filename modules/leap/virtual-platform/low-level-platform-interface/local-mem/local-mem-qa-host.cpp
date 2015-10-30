//
// Copyright (c) 2015, Intel Corporation
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

#include "awb/rrr/service_ids.h"
#include "awb/provides/local_mem.h"
#include "awb/provides/qa_device.h"
#include "awb/provides/qa_driver_host_channels.h"

// ===== service instantiation =====
LOCAL_MEM_QA_SERVER_CLASS LOCAL_MEM_QA_SERVER_CLASS::instance;

// constructor
LOCAL_MEM_QA_SERVER_CLASS::LOCAL_MEM_QA_SERVER_CLASS() :
    // instantiate stubs
    serverStub(new LOCAL_MEM_QA_SERVER_STUB_CLASS(this))
{
}

// destructor
LOCAL_MEM_QA_SERVER_CLASS::~LOCAL_MEM_QA_SERVER_CLASS()
{
    // kill stubs
    delete serverStub;
}

// init
void
LOCAL_MEM_QA_SERVER_CLASS::Init(
    PLATFORMS_MODULE p)
{
    // set parent pointer
    parent = p;
}

void
LOCAL_MEM_QA_SERVER_CLASS::Uninit()
{
}

//
// Memory allocator
//
uint64_t
LOCAL_MEM_QA_SERVER_CLASS::Alloc(uint64_t size)
{
    AFU afu = AFU_CLASS::GetInstance();

    // The incoming "size" is the index of the last word in the buffer.
    // Convert to bytes.
    uint64_t size_bytes = (size + 1) * CCI_DATA_WIDTH / 8;
    void* buf = afu->CreateSharedBufferInVM(size_bytes);

    assert(buf != NULL);

    // Hardware expects a line index
    return uint64_t(buf) / (CCI_DATA_WIDTH / 8);
}
