import os
import re
import sys
import string
import shutil
import SCons.Script
import model
import synthesis_library

class PostSynthesize():

    def __init__(self, moduleList):
        qsf_src_dir = moduleList.env['DEFS']['ROOT_DIR_HW_MODEL']
        rel_qsf_src_dir = model.rel_if_not_abspath(qsf_src_dir, moduleList.compileDirectory)

        # If the compilation directory doesn't exist, create it.
        if (not os.path.exists(moduleList.compileDirectory)):
            os.mkdir(moduleList.compileDirectory)

        try:
            aal_hw = moduleList.env['ENV']['AAL_QA_HW']
        except:
            print "Environment variable AAL_QA_HW must point to the AAL Base/HW directory"
            sys.exit(1)

        ##
        ## Make a link to the Xeon+FPGA release directory
        ##
        if (not os.path.exists(moduleList.compileDirectory + '/lib')):
            os.symlink(aal_hw + '/bdw_503_pr_pkg/lib', moduleList.compileDirectory + '/lib')
            # Copy blue bitstream base components
            os.system('rsync -a ' + moduleList.compileDirectory + '/lib/blue/output_files/ ' + \
                      moduleList.compileDirectory + '/output_files/')
            os.system('rsync -a ' + moduleList.compileDirectory + '/lib/blue/qdb_file/ ' + \
                      moduleList.compileDirectory + '/')

        ##
        ## Make links to the QSF and QPF files
        ##
        qsf = map(model.modify_path_hw,
                  moduleList.getAllDependenciesWithPaths('GIVEN_QSFS')) + \
              map(model.modify_path_hw,
                  moduleList.getAllDependenciesWithPaths('GIVEN_QPFS'))
        for tgt in qsf:
            q = moduleList.compileDirectory + '/' + os.path.basename(tgt)
            if (not os.path.exists(q)):
                # Make copies because Quartus modifies them with tags
                shutil.copy2(tgt, q)

        ## QA build expects to find sys_cfg_pkg.svh in the build directory
        if (os.path.exists(qsf_src_dir + '/sys_cfg_pkg.svh') and
            not os.path.exists(moduleList.compileDirectory + '/sys_cfg_pkg.svh')):
            os.symlink(rel_qsf_src_dir + '/sys_cfg_pkg.svh',
                       moduleList.compileDirectory + '/sys_cfg_pkg.svh')

        # pick up awb parameters.
        paramTclFile = moduleList.topModule.moduleDependency['PARAM_TCL'][0]


        ##
        ## List SDC (Tcl) files in a file that can be included in the project.
        ## These must be included in a specific order to honor dependencies
        ## among them.
        ##
        sdcs = map(model.modify_path_hw,
                   moduleList.getAllDependenciesWithPaths('GIVEN_TCL_HEADERS')) + \
               map(model.modify_path_hw,
                   moduleList.getAllDependenciesWithPaths('GIVEN_SDCS')) + \
               map(model.modify_path_hw,
                   moduleList.getAllDependenciesWithPaths('GIVEN_SDC_ALGEBRAS'))

        constrFile_name = moduleList.compileDirectory + '/project_constraints.tcl'
        constrFile = open(constrFile_name, 'w')
        constrFile.write('set_global_assignment -name SEED ' + \
                         str(moduleList.getAWBParamSafe('post_synthesis_tool', 'SEED')) + \
                         '\n')
        for tcl_header in [paramTclFile] + sorted(sdcs):
            constrFile.write('set_global_assignment -name SDC_FILE ' + model.rel_if_not_abspath(tcl_header, moduleList.compileDirectory)+ '\n')
        constrFile.close()

        prjFile_name = moduleList.compileDirectory + '/project_sources.tcl'
        prjFile = open(prjFile_name, 'w')

        ##
        ## Define which version of CCI is in use for SystemVerilog packages
        ## imported from outside LEAP.
        ##
        if (moduleList.getAWBParamSafe('qa_platform_libs', 'CCI_S_IFC')):
            prjFile.write('set_global_assignment -name VERILOG_MACRO "MPF_PLATFORM_OME=1"\n')
        if (moduleList.getAWBParamSafe('qa_platform_libs', 'CCI_P_IFC')):
            prjFile.write('set_global_assignment -name VERILOG_MACRO "MPF_PLATFORM_BDX=1"\n')
            prjFile.write('set_global_assignment -name VERILOG_MACRO "BSV_POSITIVE_RESET=1"\n')

        # Include file path
        inc_dirs = ['hw/include']
        for inc in inc_dirs:
            inc = model.rel_if_not_abspath(inc, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name SEARCH_PATH ' + inc + '\n');

        # List SystemVerilog packages first
        for pkg in moduleList.getAllDependenciesWithPaths('GIVEN_VERILOG_PKGS'):
            v = model.rel_if_not_abspath(pkg, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name SYSTEMVERILOG_FILE ' + v + '\n');

        # Add in all the verilog here.
        [globalVerilogs, globalVHDs] = synthesis_library.globalRTLs(moduleList, moduleList.moduleList)

        # gather verilog for LI Modules.
        for module in [ mod for mod in moduleList.synthBoundaries()] + [moduleList.topModule]:
            globalVerilogs += [model.get_temp_path(moduleList,module) + module.wrapperName() + '.v']

        for v in sorted(globalVerilogs):
            t = 'VERILOG'
            if ((v[-2:] == 'sv') or (v[-2:] == 'vh')):
                t = 'SYSTEMVERILOG'
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name ' + t + '_FILE ' + v + '\n');

        for v in sorted(globalVHDs):
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name VHDL_FILE ' + v + '\n');

        # add the verilogs of the files generated by quartus system builder
        for v in sorted(model.Utils.clean_split(moduleList.env['DEFS']['GIVEN_ALTERAVS'], sep = ' ')):
            v = model.rel_if_not_abspath(v, moduleList.compileDirectory)
            prjFile.write('set_global_assignment -name VERILOG_FILE ' + v + '\n');

        prjFile.close()


        ##
        ## Rules for building...
        ##

        output_dir = moduleList.compileDirectory + '/output_files/'
        proj_name_base = 'BDW_503_BASE_2041_seed2'
        proj_name_synth = 'bdw_503_pr_afu_synth'
        proj_name = 'bdw_503_pr_afu'

        altera_syn = moduleList.env.Command(
            output_dir + proj_name_synth + '.syn.rpt',
            globalVerilogs + globalVHDs + [constrFile_name] + [prjFile_name] + [paramTclFile] + sdcs,
            ['cd ' + moduleList.compileDirectory + \
             '; quartus_syn --read_settings_files=on ' + proj_name_base + ' -c ' + proj_name_synth ])

        altera_syn_qdb = moduleList.env.Command(
            moduleList.compileDirectory + '/' + proj_name_synth + '.qdb',
            altera_syn,
            ['cd ' + moduleList.compileDirectory + \
               '; quartus_cdb --read_settings_files=on ' + proj_name_synth + ' --export_block root_partition --snapshot synthesized --file ' + proj_name_synth + '.qdb', \
             'cd ' + moduleList.compileDirectory + \
               '; quartus_cdb --read_settings_files=on ' + proj_name + ' --import_block root_partition --file ' + proj_name_base + '.qdb', \
             'cd ' + moduleList.compileDirectory + \
               '; quartus_cdb --read_settings_files=on ' + proj_name + ' --import_block persona1 --file ' + proj_name_synth + '.qdb' ])

        altera_fit = moduleList.env.Command(
            output_dir + proj_name + '.fit.rpt',
            altera_syn_qdb,
            ['cd ' + moduleList.compileDirectory + \
             '; quartus_fit --read_settings_files=on ' + proj_name_base + ' -c ' + proj_name ])

        altera_sof = moduleList.env.Command(
            output_dir + proj_name + '.sof',
            altera_fit,
            ['cd ' + moduleList.compileDirectory + \
             '; quartus_asm ' + proj_name_base + ' -c ' + proj_name ])

        altera_sta = moduleList.env.Command(
            output_dir + proj_name + '.sta.rpt',
            altera_sof,
            ['cd ' + moduleList.compileDirectory + \
             '; quartus_sta --do_report_timing ' + proj_name_base + ' -c ' + proj_name ])

        altera_pmsf = moduleList.env.Command(
            output_dir + proj_name + '.pmsf',
            altera_sof,
            ['cd ' + output_dir + \
             '; quartus_cpf -p ' + proj_name + '.persona1.msf ' + proj_name + '.sof ' + proj_name + '.pmsf' ])

        altera_rbf = moduleList.env.Command(
            output_dir + proj_name + '.rbf',
            altera_pmsf,
            ['cd ' + output_dir + \
             '; quartus_cpf -c ' + proj_name + '.pmsf ' + proj_name + '.rbf' ])

        moduleList.topModule.moduleDependency['BIT'] = [altera_rbf]

        # generate the download program
        newDownloadFile = open('config/' + moduleList.apmName + '.download.temp', 'w')
        newDownloadFile.write('#!/bin/sh\n')
        newDownloadFile.write('aliconfafu --bitstream=' + output_dir + proj_name + '.rbf\n')
        newDownloadFile.close()

        altera_download = moduleList.env.Command(
            'config/' + moduleList.apmName + '.download',
            'config/' + moduleList.apmName + '.download.temp',
            ['cp $SOURCE $TARGET',
             'chmod 755 $TARGET'])

        altera_loader = moduleList.env.Command(
            moduleList.apmName + '_hw.errinfo',
            moduleList.swExe + moduleList.topModule.moduleDependency['BIT'] + altera_download + altera_sta,
            ['@ln -fs ' + moduleList.swExeOrTarget + ' ' + moduleList.apmName,
             SCons.Script.Delete(moduleList.apmName + '_hw.exe'),
             SCons.Script.Delete(moduleList.apmName + '_hw.vexe'),
             '@echo "++++++++++++ Post-Place & Route ++++++++"',
             synthesis_library.leap_physical_summary(str(altera_sta[0]), moduleList.apmName + '_hw.errinfo', 'Timing Analyzer was successful', 'Timing requirements not met')])

        moduleList.topModule.moduleDependency['LOADER'] = [altera_loader]
        moduleList.topDependency = moduleList.topDependency + [altera_loader]
