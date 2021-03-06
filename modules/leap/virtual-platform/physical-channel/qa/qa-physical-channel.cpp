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
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <iostream>
#include "tbb/concurrent_queue.h"

#include "awb/provides/physical_channel.h"


using namespace std;

// ============================================
//               Physical Channel              
// ============================================

// constructor
QA_PHYSICAL_CHANNEL_CLASS::QA_PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE     p
    ) :
    PHYSICAL_CHANNEL_CLASS(p),
    writeQ(),
    uninitialized(),
    qaDevice((PLATFORMS_MODULE) (PHYSICAL_CHANNEL) this)
    
{
    incomingMessage = NULL;
    umfFactory = new UMF_FACTORY_CLASS(); //Use a default umf factory, but allow an external device to set it later...

    uninitialized = 0;

    // Start up write thread
    void ** writerArgs = NULL;
    writerArgs = (void**) malloc(2*sizeof(void*));
    writerArgs[0] = &qaDevice;
    writerArgs[1] = this;
    if (pthread_create(&writerThread,
               NULL,
               WriterThread,
               writerArgs))
    {
        perror("pthread_create, outToFPGA0Thread:");
        exit(1);
    }
}

// destructor
QA_PHYSICAL_CHANNEL_CLASS::~QA_PHYSICAL_CHANNEL_CLASS()
{
    Uninit();
}

void QA_PHYSICAL_CHANNEL_CLASS::Uninit()
{
    if (!uninitialized.fetch_and_store(1))
    {
        // Tear down writer thread
        writeQ.push(NULL); 
        pthread_join(writerThread, NULL);
    }
}

// blocking read.  A return value of tells us that the underlying
// infrastructure is in the process of begin torn down. 
UMF_MESSAGE
QA_PHYSICAL_CHANNEL_CLASS::Read()
{
    // blocking loop
    while (true)
    {
        // check if message is ready
        if (incomingMessage && !incomingMessage->CanAppend())
        {
            // message is ready!
            UMF_MESSAGE msg = incomingMessage;
            incomingMessage = NULL;
            return msg;
        }

        // block-read data from pipe
        readPipe();
    }

    // shouldn't be here
    return NULL;
}

// non-blocking read
UMF_MESSAGE
QA_PHYSICAL_CHANNEL_CLASS::TryRead()
{

    // if there's fresh data on the pipe, update
    if (qaDevice.Probe())
    {
        readPipe();
    }

    // now see if we have a complete message
    if (incomingMessage && !incomingMessage->CanAppend())
    {
        UMF_MESSAGE msg = incomingMessage;
        incomingMessage = NULL;
        return msg;
    }

    // message not yet ready
    return NULL;
}

// write
void
QA_PHYSICAL_CHANNEL_CLASS::Write(
    UMF_MESSAGE message)
{
    writeQ.push(message);
}

// read un-processed data on the pipe
void
QA_PHYSICAL_CHANNEL_CLASS::readPipe()
{
    // determine if we are starting a new message
    if (incomingMessage == NULL)
    {
        // new message: read header
        UMF_CHUNK header;
        qaDevice.Read(&header, sizeof(header));

        // If header is 0 then it was just filler on the channel.
        if (header != 0)
        {
            // create a new message
            incomingMessage = umfFactory->createUMFMessage();
            incomingMessage->DecodeHeader(header);
        }
    }
    else if (incomingMessage->CanAppend())
    {
        size_t n_bytes = incomingMessage->BytesUnwritten();

        // Read in the message.  Once the header has been received the
        // rest of the data is guaranteed to follow.
        void* dst = incomingMessage->AppendGetRawPtr();
        qaDevice.Read(dst, n_bytes);
        incomingMessage->AppendUpdateRawPtr(n_bytes);
    }
}


void *
QA_PHYSICAL_CHANNEL_CLASS::WriterThread(void *argv)
{
    void ** args = (void**) argv;
    QA_PHYSICAL_CHANNEL physicalChannel = (QA_PHYSICAL_CHANNEL) args[1];

    tbb::concurrent_bounded_queue<UMF_MESSAGE> *incomingQ = &(physicalChannel->writeQ);
    QA_DEVICE_WRAPPER qaDevice = (QA_DEVICE_WRAPPER) args[0];

    while (1)
    {
        UMF_MESSAGE message;
        incomingQ->pop(message);

        // Check to see if we're being torn down -- this is
        // done by passing a special message through the writeQ

        if (message == NULL)
        {
            if (!physicalChannel->uninitialized)
            {
                cerr << "QA_PHYSICAL_CHANNEL got an unexpected NULL value" << endl;
            }

            pthread_exit(0);
        }

        // The FPGA side detects NULLs inserted for alignment by looking at the
        // length field.  Having a length of 0 would break the protocol.
        ASSERTX(message->GetLength() != 0);

        // construct header
        UMF_CHUNK header = 0;
        message->EncodeHeader((unsigned char *)&header);

        qaDevice->Write(&header, sizeof(header));

        size_t n_bytes = message->ExtractBytesLeft();
        // Round up to multiple of UMF_CHUNK size
        n_bytes = (n_bytes + sizeof(UMF_CHUNK) - 1) & ~(sizeof(UMF_CHUNK) - 1);

        qaDevice->Write(message->ExtractGetRawPtr(), n_bytes);
        message->ExtractUpdateRawPtr(n_bytes);

        // de-allocate message
        delete message;

        // Flush output channel if there isn't another message ready.
        if (incomingQ->empty())
        {
            qaDevice->Flush();
        }
    }
}
