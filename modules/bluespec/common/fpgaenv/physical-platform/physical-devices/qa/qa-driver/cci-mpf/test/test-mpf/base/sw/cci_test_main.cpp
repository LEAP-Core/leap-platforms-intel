// Copyright(c) 2007-2016, Intel Corporation
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

#include "cci_test.h"
#include <math.h>
#include <boost/format.hpp>

#ifndef VCMAP_ENABLE_DEFAULT
  #define VCMAP_ENABLE_DEFAULT true
#endif

int main(int argc, char *argv[])
{
    po::options_description desc("Usage");
    desc.add_options()
        ("help", "Print this message")
        ("target", po::value<string>()->default_value("fpga"), "RTL target (\"fpga\" or \"ase\")")
        ("vcmap-all", po::value<bool>()->default_value(false), "VC MAP: Map all requests, ignoring vc_sel")
        ("vcmap-enable", po::value<bool>()->default_value(VCMAP_ENABLE_DEFAULT), "VC MAP: Enable channel mapping")
        ("vcmap-dynamic", po::value<bool>()->default_value(true), "VC MAP: Use dynamic channel mapping (overridden by --vcmap-fixed)")
        ("vcmap-fixed", po::value<int>()->default_value(-1), "VC MAP: Use fixed mapping with VL0 getting <n>/64 of traffic")
        ;

    testConfigOptions(desc);

    po::variables_map vm;
    po::store(po::parse_command_line(argc, argv, desc), vm);
    po::notify(vm);    

    if (vm.count("help")) {
        cout << desc << "\n";
        return 1;
    }

    string tgt = vm["target"].as<string>();
    bool use_fpga = (tgt.compare("fpga") == 0);
    if (! use_fpga && tgt.compare("ase"))
    {
        cerr << "Illegal --target" << endl << endl;
        cerr << desc << endl;
        exit(1);
    }

    AAL_SVC_WRAPPER svc(use_fpga);

    if (!svc.isOK())
    {
        ERR("Runtime Failed to Start");
        exit(1);
    }

    btInt result = svc.initialize(testAFUID());

    //
    // Configure VC MAP shim
    //
    bool vcmap_all = vm["vcmap-all"].as<bool>();
    bool vcmap_enable = vm["vcmap-enable"].as<bool>();
    bool vcmap_dynamic = vm["vcmap-dynamic"].as<bool>();
    int32_t vcmap_fixed_vl0_ratio = int32_t(vm["vcmap-fixed"].as<int>());
    // If a fixed ratio is set ignore "dynamic" and enable VC mapping
    if (vcmap_fixed_vl0_ratio >= 0)
    {
        assert(vcmap_fixed_vl0_ratio <= 64);
        vcmap_enable = true;
        vcmap_dynamic = false;
    }

    if (svc.m_pVCMAPService)
    {
        cout << "# Configuring VC MAP shim..." << endl;
        svc.m_pVCMAPService->vcmapSetMapAll(vcmap_all);
        svc.m_pVCMAPService->vcmapSetMode(vcmap_enable, vcmap_dynamic);
        if (vcmap_fixed_vl0_ratio >= 0)
        {
            svc.m_pVCMAPService->vcmapSetFixedMapping(true, vcmap_fixed_vl0_ratio);
        }
    }

    CCI_TEST* t = allocTest(vm, svc);
    if (result == 0)
    {
        result = t->test();
    }

    if (0 == result)
    {
        cout << endl << "# ======= SUCCESS =======" << endl;
    } else
    {
        cerr << endl << "!!!!!!! FAILURE (code " << result << ") !!!!!!!" << endl;
    }

    uint64_t cycles = t->testNumCyclesExecuted();
    if (cycles != 0)
    {
        cout << "#" << endl
             << "# Test cycles executed: " << cycles << endl;
    }

    uint64_t rd_hits = t->readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_RD_HITS);
    uint64_t wr_hits = t->readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_WR_HITS);

    uint64_t vl0_rd_lines = t->readCommonCSR(CCI_TEST::CSR_COMMON_VL0_RD_LINES);
    uint64_t vl0_wr_lines = t->readCommonCSR(CCI_TEST::CSR_COMMON_VL0_WR_LINES);
    uint64_t vh0_lines = t->readCommonCSR(CCI_TEST::CSR_COMMON_VH0_LINES);
    uint64_t vh1_lines = t->readCommonCSR(CCI_TEST::CSR_COMMON_VH1_LINES);

    cout << "#" << endl
         << "# Statistics:" << endl
         << "#   Cache read hits:    " << rd_hits;
    if (rd_hits)
    {
        cout << " (" << round((1000.0 * rd_hits) / vl0_rd_lines) << " per 1000)";
    }
    cout << endl
         << "#   Cache write hits:   " << wr_hits;
    if (wr_hits)
    {
        cout << " (" << round((1000.0 * wr_hits) / vl0_wr_lines) << " per 1000)";
    }
    cout << endl
         << "#   VL0 line ops:       " << vl0_rd_lines + vl0_wr_lines
         << " (" << vl0_rd_lines << " read / " << vl0_wr_lines << " write)" << endl
         << "#   VH0 line ops:       " << vh0_lines << endl
         << "#   VH1 line ops:       " << vh1_lines << endl
         << "#" << endl;

    uint64_t fiu_state = t->readCommonCSR(CCI_TEST::CSR_COMMON_FIU_STATE);
    if (fiu_state & 3)
    {
        if (fiu_state & 1)
        {
            cout << "# FIU C0 Tx is almost full!" << endl;
        }
        if (fiu_state & 2)
        {
            cout << "# FIU C1 Tx is almost full!" << endl;
        }
        cout << "#" << endl;
    }

    t_cci_mpf_vtp_stats vtp_stats;
    svc.m_pVTPService->vtpGetStats(&vtp_stats);
    cout << "#   VTP failed:         " << vtp_stats.numFailedTranslations << endl;
    if (vtp_stats.numFailedTranslations)
    {
        cout << "#   VTP failed addr:    0x" << hex << uint64_t(vtp_stats.ptWalkLastVAddr) << dec << endl;
    }
    cout << "#   VTP PT walk cycles: " << vtp_stats.numPTWalkBusyCycles << endl
         << "#   VTP 4KB hit / miss: " << vtp_stats.numTLBHits4KB << " / "
                                       << vtp_stats.numTLBMisses4KB << endl
         << "#   VTP 2MB hit / miss: " << vtp_stats.numTLBHits2MB << " / "
                                       << vtp_stats.numTLBMisses2MB << endl;

    if (svc.m_pVCMAPService)
    {
        if (! vcmap_enable)
        {
            cout << "#" << endl
                 << "#   VC MAP disabled" << endl;
        }
        else
        {
            t_cci_mpf_vc_map_stats vcmap_stats;
            svc.m_pVCMAPService->vcmapGetStats(&vcmap_stats);
            cout << "#" << endl
                 << "#   VC MAP map chngs:   " << vcmap_stats.numMappingChanges << endl
                 << "#   VC MAP history:     0x" << hex
                 << svc.m_pVCMAPService->vcmapGetMappingHistory() << dec << endl;
        }
    }

    if (svc.m_pWROService)
    {
        t_cci_mpf_wro_stats wro_stats;
        svc.m_pWROService->wroGetStats(&wro_stats);

        cout << endl;
        cout << "#   WRO conflict cycles RR:   " << wro_stats.numConflictCyclesRR;
        if (cycles != 0)
        {
            cout << "  (" << boost::format("%.1f") % (double(wro_stats.numConflictCyclesRR) * 100.0 / cycles) << "% of cycles)";
        }

        cout << endl << "#   WRO conflict cycles RW:   " << wro_stats.numConflictCyclesRW;
        if (cycles != 0)
        {
            cout << "  (" << boost::format("%.1f") % (double(wro_stats.numConflictCyclesRW) * 100.0 / cycles) << "% of cycles)";
        }

        cout << endl << "#   WRO conflict cycles WR:   " << wro_stats.numConflictCyclesWR;
        if (cycles != 0)
        {
            cout << "  (" << boost::format("%.1f") % (double(wro_stats.numConflictCyclesWR) * 100.0 / cycles) << "% of cycles)";
        }

        cout << endl << "#   WRO conflict cycles WW:   " << wro_stats.numConflictCyclesWW;
        if (cycles != 0)
        {
            cout << "  (" << boost::format("%.1f") % (double(wro_stats.numConflictCyclesWW) * 100.0 / cycles) << "% of cycles)";
        }

        cout << endl;
    }

    if (svc.m_pPWRITEService)
    {
        t_cci_mpf_pwrite_stats pwrite_stats;
        svc.m_pPWRITEService->pwriteGetStats(&pwrite_stats);

        cout << "#" << endl
             << "#   PWRITE partial writes:    " << pwrite_stats.numPartialWrites
             << endl;
    }

    svc.terminate();

    return result;
}
