# -*- mode: makefile -*-
#
# THIS WORKED 2024-11
#
# To compile on the PPPL Flux Cluster, load the following modules:
#
# module purge
# module load pgi/24.3 openmpi/4.1.6-pgi-24.3 hdf5/1.14.3-pgi-24.3-qesd7 openmpi-4.1.6/pgi-24.3/netcdf-fortran/4.6.1-mybjs openmpi-4.1.6/pgi-24.3/petsc/3.19.6-lx7cx
#
# Also set the following environment variable:
#
# export SFINCS_SYSTEM=flux
#
# (You might wish to put the above lines in your .bashrc file.)
#
# Then run 
# make clean
# make
#
# To use the scanning routines in utils/ you also need to load the following module:
#
# module load anaconda3/2023.09-0-gcc-13.2.0-ajty2
#

# These next 2 includes set FC, FLINKER, and PETSC_LIB:
# For PETSc version 3.6.0 and later, use the following 2 lines:
include ${PETSC_HOME}/lib/petsc/conf/variables
include ${PETSC_HOME}/lib/petsc/conf/rules
# The next 2 lines are used instead of the above 2 lines for PETSc versions prior to 3.6.0:
#include ${PETSC_DIR}/conf/variables
#include ${PETSC_DIR}/conf/rules

# The variable LIBSTELL_DIR should either be "mini_libstell", if you use this reduced version of libstell
# that comes packaged with SFINCS, or else it should point to a directory containing libstell .mod files
# elsewhere on your system.
LIBSTELL_DIR=mini_libstell

# The variable LIBSTELL_FOR_SFINCS should either be "mini_libstell/mini_libstell.a", if you use this reduced version of libstell
# that comes packaged with SFINCS, or else it should point to a libstell.a library elsewhere on your system.
LIBSTELL_FOR_SFINCS=mini_libstell/mini_libstell.a

# Any other flags for compiling, such as -I include flags:
EXTRA_COMPILE_FLAGS = -I${HDF5_HOME}/include -I${PETSC_HOME}/include -I${NETCDF_FORTRAN_HOME}/include

# Any other flags for linking, such as -l library flags:
EXTRA_LINK_FLAGS = -L${HDF5_HOME}/lib -lhdf5_fortran -lhdf5 -lhdf5_hl -lhdf5hl_fortran -L${NETCDF_FORTRAN_HOME}/lib -lnetcdff

# The next parameters are used only for running selected examples "make test"

# For "make test", are runs submitted using a batch system (such as PBS)?
# The value of this variable must be "yes" or "no".
SFINCS_IS_A_BATCH_SYSTEM_USED=yes

# This next line matters only if a batch system is used:
SFINCS_COMMAND_TO_SUBMIT_JOB=sbatch job.flux
