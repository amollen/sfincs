# -*- mode: makefile -*-
#
# To compile on raven, the following modules worked on 4 Dec 2020
#
# module purge
# module load intel/19.1.2 impi/2019.8 hdf5-mpi netcdf-mpi petsc-real
#
# Also set the following environment variables:
#
# export SFINCS_SYSTEM=viper
# export PATH=${PATH}:${HDF5_HOME}/bin
# export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${HDF5_HOME}/lib:${NETCDF_HOME}/lib
#
# (You might wish to put the above lines in your .bashrc file.)
#
# Then run 
# make clean
# make -j
#
# To use the plotting routines in utils/ you also need to load the following modules:
# module load anaconda/2

# These next 2 includes set FC, FLINKER, and PETSC_LIB:
# For PETSc version 3.6.0 and later, use the following 2 lines:
include ${PETSC_DIR}/lib/petsc/conf/variables
include ${PETSC_DIR}/lib/petsc/conf/rules
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
EXTRA_COMPILE_FLAGS = -I${HDF5_HOME}/include -I${PETSC_DIR}/include -I${PETSC_DIR}/${PETSC_ARCH}/include -I${NETCDF_HOME}/include

# The cray compiler needs -I. or else it cannot find PETSCVersions.F90

# Any other flags for linking, such as -l library flags:
EXTRA_LINK_FLAGS = -L${HDF5_HOME}/lib -lhdf5_fortran -lhdf5 -lhdf5_hl -lhdf5hl_fortran -L${NETCDF_HOME}/lib -lnetcdf -lnetcdff

# The next parameters are used only for running selected examples "make test"

# For "make test", are runs submitted using a batch system (such as PBS)?  
# The value of this variable must be "yes" or "no".
SFINCS_IS_A_BATCH_SYSTEM_USED=yes

# This next line matters only if a batch system is used:
SFINCS_COMMAND_TO_SUBMIT_JOB=sbatch job.raven
