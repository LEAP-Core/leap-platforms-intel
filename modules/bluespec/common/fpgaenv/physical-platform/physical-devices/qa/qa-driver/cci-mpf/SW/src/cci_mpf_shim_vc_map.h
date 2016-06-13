// Copyright(c) 2016, Intel Corporation
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
//****************************************************************************
/// @file cci_mpf_shim_vc_map.h
/// @brief Definitions for VC MAP Service.
/// @ingroup VCMAPService
/// @verbatim
/// Virtual channel mapping service.
///
/// Note: this is not an AAL service, but a component of the MPF service (which
/// is).
///
/// AUTHOR:  Michael Adler, Intel Corporation
///
/// HISTORY:
/// WHEN:          WHO:     WHAT:
/// 06/03/2016     MA       Initial version@endverbatim
//****************************************************************************
#ifndef __CCI_MPF_SHIM_VCMAP_H__
#define __CCI_MPF_SHIM_VCMAP_H__

#include "IMPF.h"              // Public MPF service interface
#include "MPFService.h"


BEGIN_NAMESPACE(AAL)

/// @addtogroup VCMAPService
/// @{

class MPFVCMAP : public CAASBase, public IMPFVCMAP
{
public:

   /// VCMAP constructor
   MPFVCMAP( IALIMMIO   *pMMIOService,
             btCSROffset vcmapDFHOffset );

   // Set the mapping mode:
   //  - enable_mapping turns on eVC_VA to physical channel mapping
   //  - enable_dynamic_mapping turns on automatic tuning of the channel
   //    ratios based on traffic. (Ignored when enable_mapping is false.)
   //  - sampling_window_radix determines the sizes of sampling windows for
   //    dynamic mapping and, consequently, controls the frequency at
   //    which dynamic changes may occur.  Dynamic changes are expensive
   //    since a write fence must be emitted to synchronize traffic.
   //    Passing 0 picks the default value.
   //  - map_all_requests:  When false, only incoming eVC_VA requests are
   //    mapped.  When true, all incoming requests are remapped.
   btBool vcmapSetMode( btBool enable_mapping,
                        btBool enable_dynamic_mapping,
                        btUnsigned32bitInt sampling_window_radix = 0,
                        btBool map_all_requests = false );

   // Disable mapping
   btBool vcmapDisable( void );

   // Set fixed mapping where VL0 gets r 64ths of the traffic.
   //  - map_all_requests:  When false, only incoming eVC_VA requests are
   //    mapped.  When true, all incoming requests are remapped.
   btBool vcmapSetFixedMapping( btUnsigned32bitInt r,
                                btBool map_all_requests = false );

   btBool isOK( void ) { return m_isOK; }     // < status after initialization

   // Return all statistics counters
   btBool vcmapGetStats( t_cci_mpf_vc_map_stats *stats );

   // Return a statistics counter
   btUnsigned64bitInt vcmapGetStatCounter( t_cci_mpf_vc_map_csr_offsets stat );

protected:
   IALIMMIO              *m_pALIMMIO;
   btCSROffset            m_dfhOffset;

   btBool                 m_isOK;

};

/// @}

END_NAMESPACE(AAL)

#endif // __CCI_MPF_SHIM_VCMAP_H__
