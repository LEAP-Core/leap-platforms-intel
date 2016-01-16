import os
import re
import sys
import string
import SCons.Script
import model
import synthesis_library

class PostSynthesize():

    def __init__(self, moduleList):
        altera_apm_name = moduleList.compileDirectory + '/' + moduleList.apmName
        qsf_src_dir = moduleList.env['DEFS']['ROOT_DIR_HW_MODEL']

        # If the compilation directory doesn't exist, create it.
        if(not os.path.exists(moduleList.compileDirectory)):
            os.mkdir(moduleList.compileDirectory)

        rel_qsf_src_dir = model.rel_if_not_abspath(qsf_src_dir, moduleList.compileDirectory)

        # pick up awb parameters.
        paramTclFile = moduleList.topModule.moduleDependency['PARAM_TCL'][0]

        ## QA build expects to find sys_cfg_pkg.svh in the build directory
        if (os.path.exists(qsf_src_dir + '/sys_cfg_pkg.svh') and
            not os.path.exists(moduleList.compileDirectory + '/sys_cfg_pkg.svh')):
            os.symlink(rel_qsf_src_dir + '/sys_cfg_pkg.svh',
                       moduleList.compileDirectory + '/sys_cfg_pkg.svh')

        ## Quartus looks for the MIF files in the build directory
        mif_root = os.environ['AAL_QA_HW'] + '/RTL/bdx_fpga/design/fiu/ptmgr/'
        mif_src_files = ['PMBUS_SourceTree/ptmgr_pmbus_mach_xact_XACT_ROM.mif',
                         'TEMPERATURE_SourceTree/ptmgr_temp_cmp_ROM.mif',
                         'TEMPERATURE_SourceTree/ptmgr_temp_cnv_ROM.mif' ]
        for mif_src in mif_src_files:
            mif_path = mif_root + mif_src
            mif_leaf = os.path.basename(mif_path)
            # Does the MIF file exist in the release tree?
            if (not os.path.exists(mif_path)):
                print "ALTERA_FULL_POST_SYNTH: Failed to find " + mif_path
                sys.exit(1)
            # Make a link in build directory
            if (not os.path.exists(moduleList.compileDirectory + '/' + mif_leaf)):
                os.symlink(mif_path, moduleList.compileDirectory + '/' + mif_leaf)

        altera_qsf = altera_apm_name + '.tcl'
        altera_qpf = altera_apm_name + '.qpf'

        prjFile = open(altera_qsf, 'w')

        prjFile.write('package require ::quartus::project\n')
        prjFile.write('package require ::quartus::flow\n')
        prjFile.write('package require ::quartus::incremental_compilation\n')

        # Check for the existence of a project here, so that we can
        # make use of incremental compilation.
        prjFile.write('set created_project [project_exists ' + moduleList.apmName +']\n')
        prjFile.write('if $created_project {\n')
        prjFile.write('    project_open ' + moduleList.apmName +' \n')
        prjFile.write('} else  {\n')
        prjFile.write('    project_new ' + moduleList.apmName +'\n')
        prjFile.write('}\n\n')

        ##
        ## Define which version of CCI is in use for SystemVerilog packages
        ## imported from outside LEAP.
        ##
        if (moduleList.getAWBParamSafe('qa_platform_libs', 'CCI_S_IFC')):
            prjFile.write('set_global_assignment -name VERILOG_MACRO "USE_PLATFORM_CCIS=1"\n')
        if (moduleList.getAWBParamSafe('qa_platform_libs', 'CCI_P_IFC')):
            prjFile.write('set_global_assignment -name VERILOG_MACRO "USE_PLATFORM_CCIP=1"\n')
        prjFile.write('set_global_assignment -name VERILOG_MACRO "CCIP_IF_V0_1=1"\n')

        prjFile.write('source ' + rel_qsf_src_dir + '/bdx_arria10.qsf\n')

        # Include file path
        inc_dirs = ['hw/include']
        for inc in inc_dirs:
            inc = model.rel_if_not_abspath(inc, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name SEARCH_PATH ' + inc + '\n');

        # Include SDC (Tcl) files. These must be included in a specific order to honor dependencies among them.
        sdcs = map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_TCL_HEADERS')) + map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_SDCS')) + map(model.modify_path_hw, moduleList.getAllDependenciesWithPaths('GIVEN_SDC_ALGEBRAS'))

        for tcl_header in [paramTclFile] + sdcs:
            prjFile.write('set_global_assignment -name SDC_FILE ' + model.rel_if_not_abspath(tcl_header, moduleList.compileDirectory)+ '\n')

        # Add in all the verilog here.
        [globalVerilogs, globalVHDs] = synthesis_library.globalRTLs(moduleList, moduleList.moduleList)

        # gather verilog for LI Modules.
        for module in [ mod for mod in moduleList.synthBoundaries()] + [moduleList.topModule]:
            globalVerilogs += [model.get_temp_path(moduleList,module) + module.wrapperName() + '.v']

        for v in globalVerilogs:
            t = 'VERILOG'
            if ((v[-2:] == 'sv') or (v[-2:] == 'vh')):
                t = 'SYSTEMVERILOG'
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name ' + t + '_FILE ' + v + '\n');

        for v in globalVHDs:
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name VHDL_FILE ' + v + '\n');

        # add the verilogs of the files generated by quartus system builder
        for v in model.Utils.clean_split(moduleList.env['DEFS']['GIVEN_ALTERAVS'], sep = ' ') :
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name VERILOG_FILE ' + v + '\n');

        fullCompilePath = os.path.abspath(moduleList.compileDirectory)

        prjFile.write('execute_module  -tool map -args "--verilog_macro=\\"QUARTUS_COMPILATION=1\\" --lib_path ' + fullCompilePath + ' " \n')
        prjFile.write('execute_module  -tool cdb -args "--merge"  \n')
        prjFile.write('execute_module  -tool fit \n')
        prjFile.write('execute_module  -tool sta \n')
        prjFile.write('execute_module  -tool sta -args "--do_report_timing"\n')
        prjFile.write('execute_module  -tool asm  \n')

        prjFile.write('project_close \n')
        prjFile.close()

        altera_sof = moduleList.env.Command(altera_apm_name + '.sof',
                                            globalVerilogs + globalVHDs + [altera_apm_name + '.tcl'] + [paramTclFile] + sdcs,
                                            ['cd ' + moduleList.compileDirectory + '; quartus_sh -t ' + moduleList.apmName + '.tcl' ])

        moduleList.topModule.moduleDependency['BIT'] = [altera_sof]

        # generate the download program
        newDownloadFile = open('config/' + moduleList.apmName + '.download.temp', 'w')
        newDownloadFile.write('#!/bin/sh\n')
        newDownloadFile.write('nios2-configure-sof ' + altera_apm_name + '.sof\n')
        newDownloadFile.close()

        altera_download = moduleList.env.Command(
            'config/' + moduleList.apmName + '.download',
            'config/' + moduleList.apmName + '.download.temp',
            ['cp $SOURCE $TARGET',
             'chmod 755 $TARGET'])

        altera_loader = moduleList.env.Command(
            moduleList.apmName + '_hw.errinfo',
            moduleList.swExe + moduleList.topModule.moduleDependency['BIT'] + altera_download,
            ['@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
             SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
             SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
             '@echo "++++++++++++ Post-Place & Route ++++++++"',
             synthesis_library.leap_physical_summary(altera_apm_name + '.sta.rpt', moduleList.apmName + '_hw.errinfo', 'Timing Analyzer was successful', 'Timing requirements not met')])

        moduleList.topModule.moduleDependency['LOADER'] = [altera_loader]
        moduleList.topDependency = moduleList.topDependency + [altera_loader]
