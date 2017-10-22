function sfincs_solver()

global matrixSize reusePreconditioner nonlinearTolerance maxNumNonlinearIterations stateVector useIterativeLinearSolver includePhi1
global dnHatdpsiHats dTHatdpsiHats EParallelHat nHats THats Phi1Hat dPhi1Hatdalpha dPhi1Hatdzeta
global Nalpha Nzeta RHSMode whichRHS
global preconditioner_L preconditioner_U preconditioner_P preconditioner_Q
global Jacobian preconditionerMatrix initialResidual

sfincs_initF0()
Phi1Hat = zeros(Nalpha,Nzeta);
dPhi1Hatdalpha = zeros(Nalpha,Nzeta);
dPhi1Hatdzeta = zeros(Nalpha,Nzeta);

preconditioner_L = 0;
preconditioner_U = 0;
preconditioner_P = 0;
preconditioner_Q = 0;

switch RHSMode
    case 1
        % Single solve, either linear or nonlinear

        stateVector = zeros(matrixSize,1);

        if includePhi1
            numJacobianIterations = maxNumNonlinearIterations;
        else
            numJacobianIterations = 1;
        end
        
        % Main loop for Newton's method:
        for whichNonlinearIteration = 1:numJacobianIterations
            residual = sfincs_evaluateResidual();
            residualNorm = norm(residual);
            if whichNonlinearIteration == 1
                initialResidualNorm = residualNorm;
                initialResidual = residual;
                fprintf('Residual norm: absolute = %g\n',residualNorm)
            else
                fprintf('Residual norm: absolute = %g, compared to 1st iteration = %g\n',residualNorm,residualNorm/initialResidualNorm)
            end
            
            if residualNorm / initialResidualNorm < nonlinearTolerance
                fprintf('Residual norm is below nonlinear tolerance, so exiting Newton iteration.\n')
                break
            end
            
            whichMatrix = 1;
            Jacobian = sfincs_populateMatrix(whichMatrix);

            if useIterativeLinearSolver && (whichNonlinearIteration==1 || (~reusePreconditioner))
                whichMatrix = 0;
                preconditionerMatrix = sfincs_populateMatrix(whichMatrix);
                fprintf('LU-factorizing preconditioner...  ')
                tic
                [preconditioner_L, preconditioner_U, preconditioner_P, preconditioner_Q] = lu(preconditionerMatrix);
                fprintf('Done.  Took %g seconds.\n',toc)
            end
            
            delta = sfincs_solveLinearSystem(Jacobian, -residual);
            stateVector = stateVector + delta;

            if whichNonlinearIteration < numJacobianIterations
                sfincs_diagnostics();
            end
        end
        sfincs_diagnostics();


    case {2,3}
        % Multiple linear solves for different right-hand sides.
        
        whichMatrix = 1;
        Jacobian = sfincs_populateMatrix(whichMatrix);
        
        if useIterativeLinearSolver
            whichMatrix = 0;
            preconditionerMatrix = sfincs_populateMatrix(whichMatrix);
            fprintf('LU-factorizing preconditioner...  ')
            tic
            [preconditioner_L, preconditioner_U, preconditioner_P, preconditioner_Q] = lu(preconditionerMatrix);
            fprintf('Done.  Took %g seconds.\n',toc)
        end
        
        switch RHSMode
            case 2
                numRHSs = 3;
            case 3
                numRHSs = 2;
            otherwise
                error('Should not get here')
        end
        
        for whichRHS = 1:numRHSs
            fprintf('*********************************************\n')
            fprintf('Solving system with right-hand side %d of %d.\n',whichRHS, numRHSs)
            
            switch RHSMode
                case 2
                    switch whichRHS
                        case 1
                            dnHatdpsiHats = 1;
                            dTHatdpsiHats = 0;
                            EParallelHat  = 0;
                        case 2
                            dnHatdpsiHats = (3/2)*nHats(1)*THats(1);
                            dTHatdpsiHats = 1;
                            EParallelHat  = 0;
                        case 3
                            dnHatdpsiHats = 0;
                            dTHatdpsiHats = 0;
                            EParallelHat  = 1;
                        otherwise
                            error('Should not get here')
                    end
                case 3
                    switch whichRHS
                        case 1
                            dnHatdpsiHats = 1;
                            dTHatdpsiHats = 0;
                            EParallelHat  = 0;
                        case 2
                            dnHatdpsiHats = 0;
                            dTHatdpsiHats = 0;
                            EParallelHat  = 1;
                        otherwise
                            error('Should not get here')
                    end
                otherwise
                    error('Should not get here')
            end
            
            stateVector = zeros(matrixSize,1);
            residual = sfincs_evaluateResidual();
            stateVector = sfincs_solveLinearSystem(Jacobian, -residual);
            sfincs_diagnostics()

        end
        
    otherwise
        error('Invalid RHSMode')
end

end
