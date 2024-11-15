#!/usr/bin/env python

# This python script checks the sfincsOutput.h5 file for an example to 
# see if the results are close to expected values.  This script may be
# run directly, and it is also called when "make test" is run from the
# main SFINCS directory.

execfile('../testsCommon.py')

desiredTolerance = 0.001

numFailures = 0

numFailures += shouldBe("FSABFlow[0,0;;;]", -1.52139e-05, desiredTolerance)
numFailures += shouldBe("particleFlux_vm_psiHat[0,0;;;]", -6.20784e-09, desiredTolerance)
numFailures += shouldBe("heatFlux_vm_psiHat[0,0;;;]", -4.94005e-10, desiredTolerance)

exit(numFailures > 0)
