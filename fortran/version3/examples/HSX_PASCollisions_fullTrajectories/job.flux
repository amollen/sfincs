#!/bin/bash

# Standard output and error:
#SBATCH -o ./sfincsJob.out.%j
#SBATCH -e ./sfincsJob.err.%j
# Initial working directory:
#SBATCH -D ./
# Job Name:
#SBATCH -J sfincs

# Queue (Partition):
#SBATCH --partition=all

#SBATCH --nodes=1
#SBATCH --ntasks-per-node=8
#SBATCH --mem=245G
# for OpenMP:
#SBATCH --cpus-per-task=8
export OMP_NUM_THREADS=8
# For pinning threads correctly:
export OMP_PLACES=cores

# Wall clock limit:
#SBATCH --time=00:30:00

srun --mpi=pmix ../../sfincs -ksp_view
