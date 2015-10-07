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

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <iostream>
#include <atomic>

#include "awb/provides/qa_driver.h"

// AAL defines ASSERT, which will be redefined by LEAP
#undef ASSERT

#include "awb/provides/qa_driver_host_channels.h"
#include "awb/provides/physical_platform_defs.h"
#include "awb/provides/qa_device.h"


using namespace std;

// ID of the accelerator.  For now we use a constant.  This should change
// to at least application-specific if not compilation-specific.
static const char* QA_AFU_ID = "12345678-0D82-4272-9AEF-FE5F84570612";


// ============================================
//           QA Physical Device
// ============================================

// ============================================
//           Class static functions
// These functions are necessary to ensure that the
// class constructor is non-blocking.
// ============================================

// ============================================
//           Class member functions
// ============================================

// constructor: set up hardware partition
QA_DEVICE_WRAPPER_CLASS::QA_DEVICE_WRAPPER_CLASS(
    PLATFORMS_MODULE p) :
        PLATFORMS_MODULE_CLASS(p),
        afu(QA_AFU_ID),
        channelDev(p, afu),
        bytesLeftInPacket(0),
        nextReadHeader(0)
{
    deviceSwitch = new COMMAND_SWITCH_DICTIONARY_CLASS("DEVICE_DICTIONARY");

    //
    // Check required properties
    //

    // UMF_CHUNK size is a power of 2
    assert((sizeof(UMF_CHUNK) & (sizeof(UMF_CHUNK) - 1)) == 0);
    // An array of UMF_CHUNKS completely fills a cache line
    assert((UMF_CHUNKS_PER_CL * sizeof(UMF_CHUNK)) == CL(1));
}


// destructor
QA_DEVICE_WRAPPER_CLASS::~QA_DEVICE_WRAPPER_CLASS()
{
    // cleanup
    Cleanup();
}


void
QA_DEVICE_WRAPPER_CLASS::Init()
{
    if (testSwitch.Value() != 0)
    {
        channelDev.EnableTests();
    }
}


void
QA_DEVICE_WRAPPER_CLASS::Uninit()
{
}


void
QA_DEVICE_WRAPPER_CLASS::Cleanup()
{
}


void QA_DEVICE_WRAPPER_CLASS::RegisterLogicalDeviceName(string name)
{
}
