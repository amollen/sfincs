function matrix = sfincs_populateMatrix(whichMatrix)

global THats mHats Zs nHats RosenbluthPotentialTerms xGridScheme
global matrixSize Nalpha Nzeta Nxi Nx NL Nspecies pointAtX0
global ddalpha ddalpha_preconditioner ddzeta ddzeta_preconditioner
global ddx d2dx2 ddx_preconditioner x xWeights xMaxPotentials
global NxPotentials xPotentials ddxPotentials d2dx2Potentials interpolateXToXPotentials
global preconditioner_alpha_min_L alphaWeights
global preconditioner_zeta_min_L zetaWeights
global preconditioner_species preconditioner_x preconditioner_x_min_L
global preconditioner_xi collisionOperator constraintScheme
global BLOCK_F BLOCK_QN BLOCK_PHI1_CONSTRAINT BLOCK_DENSITY_CONSTRAINT BLOCK_PRESSURE_CONSTRAINT BLOCK_F_CONSTRAINT indexVars
global includePhi1 includePhi1InKineticEquation useDKESExBDrift includeXDotTerm includeElectricFieldTermInXiDot magneticDriftScheme
global Delta gamma nu_n Phi1Hat dPhi1Hatdalpha dPhi1Hatdzeta stateVector
global BDotCurlB FSABHat2 dPhiHatdpsiHat force0RadialCurrentInEquilibrium
global BHat dBHatdtheta dBHatdzeta dBHatdpsiHat
global DHat BHat_sub_psi BHat_sub_theta BHat_sub_zeta BHat_sup_theta BHat_sup_zeta
global dBHat_sub_psi_dtheta dBHat_sub_psi_dzeta
global dBHat_sub_theta_dpsiHat dBHat_sub_theta_dzeta
global dBHat_sub_zeta_dpsiHat dBHat_sub_zeta_dtheta
global adiabaticZ adiabaticNHat adiabaticTHat withAdiabatic quasineutralityOption
global dnHatdpsiHats dTHatdpsiHats reusePreconditioner
global zeta_to_impose_DKE zetaMax
global alpha_interpolation_stencil preconditioner_alpha_interpolation_stencil zetaDerivativeScheme alpha iota

populateMatrixTic = tic;

if pointAtX0
    ixMin = 2;
else
    ixMin = 1;
end

x2 = x.*x;
expx2 = exp(-x2);
sqrtpi = sqrt(pi);

switch whichMatrix
    case 0
        whichMatrixName = 'Jacobian preconditioner';
    case 1
        whichMatrixName = 'Jacobian';
    case 2
        whichMatrixName = 'Residual f0';
    case 3
        whichMatrixName = 'Residual f1';
    otherwise
        error('Invalid whichMatrix')
end

fprintf('Populating matrix: %s\n',whichMatrixName)

% To build the matrix as efficiently as possible, a reasonably
% accurate estimate of the number of nonzeros (nnz) is needed beforehand:
estimated_nnz = 1 * (Nx*Nx*Nspecies*Nspecies*Nxi*Nalpha*Nzeta ...
    + Nspecies*(nnz(ddalpha)*Nx*(3*Nxi)*Nzeta + nnz(ddzeta)*Nx*(3*Nxi)*Nalpha ...
    + Nx*(5*Nxi)*Nalpha*Nzeta + 3*Nx*Nx*Nxi*Nalpha*Nzeta ...
    + 2*2*Nx*1*Nalpha*Nzeta));

estimated_nnz = Nspecies*(Nalpha*5)*Nzeta*(Nxi*5)*Nx ...  %ddalpha terms
    + Nspecies*Nalpha*(Nzeta*5)*(Nxi*5)*Nx ...            %ddzeta terms
    + Nspecies*Nalpha*Nzeta*(Nxi*5)*Nx ...                %ddxi terms
    + Nspecies*Nalpha*Nzeta*(Nxi*5)*(Nx*Nx) ...           %ddx terms (collisionless)
    + Nspecies*Nalpha*Nzeta*(Nxi*5)*(Nx*Nx);              %collision terms

if constraintScheme==1
elseif constraintScheme==2
end

if includePhi1
    estimated_nnz = estimated_nnz + Nalpha*Nzeta*Nx ...  % quasineutrality equation
        + (Nalpha*5)*Nzeta*Nxi*Nx ...                    % dPhi1/dalpha
        + Nalpha*(Nzeta*5)*Nxi*Nx;                    % dPhi1/dzeta
end

sparseCreatorIndex=1;
sparseCreator_i=0;
sparseCreator_j=0;
sparseCreator_s=0;
resetSparseCreator()

% -----------------------------------------
% Add interpolations:
% -----------------------------------------

if whichMatrix==0
    stencil = preconditioner_alpha_interpolation_stencil;
else
    stencil = alpha_interpolation_stencil;
end

% First handle the points needed by the DKE to the left of zeta=0:
theta_left = alpha;

theta_right = alpha - iota * zetaMax;
interpolationMatrix_left = sfincs_periodicInterpolation(theta_left, theta_right, 2*pi, stencil);

theta_right = alpha + iota * zetaMax;
interpolationMatrix_right = sfincs_periodicInterpolation(theta_left, theta_right, 2*pi, stencil);

izetas_left = 1:buffer_zeta_points_on_each_side;
izetas_right = (Nzeta-buffer_zeta_points_on_each_side+1):Nzeta;
izeta_shift = Nzeta-2*buffer_zeta_points_on_each_side;
for ispecies = 1:Nspecies
    for ix = 1:Nx
        for ixi = 1:Nxi
            for izeta = izetas_left
                % Add 1's along the diagonal
                rowIndices = sfincs_indices(ispecies, ix, ixi, 1:Nalpha, izeta, BLOCK_F, indexVars);
                addToSparse(rowIndices, rowIndices, ones(size(rowIndices)));
                colIndices = sfincs_indices(ispecies, ix, ixi, 1:Nalpha, izeta+izeta_shift, BLOCK_F, indexVars);
                addSparseBlock(rowIndices,colIndices,-interpolationMatrix_left);
            end
            
            for izeta = izetas_right
                % Add 1's along the diagonal
                rowIndices = sfincs_indices(ispecies, ix, ixi, 1:Nalpha, izeta, BLOCK_F, indexVars);
                addToSparse(rowIndices, rowIndices, ones(size(rowIndices)));
                colIndices = sfincs_indices(ispecies, ix, ixi, 1:Nalpha, izeta-izeta_shift, BLOCK_F, indexVars);
                addSparseBlock(rowIndices,colIndices,-interpolationMatrix_right);
            end
        end
    end
end

% -----------------------------------------
% Add collisionless terms:
% -----------------------------------------

for ispecies = 1:Nspecies
    THat = THats(ispecies);
    nHat = nHats(ispecies);
    mHat = mHats(ispecies);
    Z = Zs(ispecies);
    sqrtT = sqrt(THat);
    sqrtm = sqrt(mHat);
    
    
    % -----------------------------------------
    % Add d/dzeta terms:
    % -----------------------------------------
    
    if whichMatrix ~= 2
        streamingTermSpatialPart = sqrtT/sqrtm*BHat_sup_zeta./BHat;
        for L=0:(Nxi-1)
            if whichMatrix==0 && L >= preconditioner_zeta_min_L
                ddzeta_sum_to_use = streaming_ddzeta_sum_preconditioner;
                ddzeta_difference_to_use = streaming_ddzeta_difference_preconditioner;
            else
                ddzeta_sum_to_use = streaming_ddzeta_sum;
                ddzeta_difference_to_use = streaming_ddzeta_difference;
            end
                        
            for ialpha = 1:Nalpha
                streaming_term_sum = diag(streamingTermSpatialPart(ialpha,:))*ddzeta_sum_to_use;
                streaming_term_difference = diag(streamingTermSpatialPart(ialpha,:))*ddzeta_difference_to_use;
                
                streaming_term_sum = streaming_term_sum(zeta_to_impose_DKE,:);
                streaming_term_difference = streaming_term_difference(zeta_to_impose_DKE,:);
                
                for ix = ixMin:Nx
                    rowIndices = sfincs_indices(ispecies, ix, L+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);

                    % Diagonal in L
                    colIndices = sfincs_indices(ispecies, ix, L+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                    addSparseBlock(rowIndices, colIndices, ExBTerm + nonlinearTerm ...
                        + x2(ix)*(magneticDriftTerm1*2*(3*L*L+3*L-2)+magneticDriftTerm2*(2*L*L+2*L-1))/((2*L+3)*(2*L-1))...
                        + x2(ix)*magneticDriftTerm3*(-2)*L*(L+1)/((2*L+3)*(2*L-1)))
    
                    % Super-diagonal in L
                    ell = L + 1;
                    if (ell <= Nxi-1)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, streamingTerm*x(ix)*(L+1)/(2*L+3))
                    end
                    
                    % Sub-diagonal in L
                    ell = L - 1;
                    if (ell >= 0)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, streamingTerm*x(ix)*L/(2*L-1))
                    end
                    
                    if whichMatrix>0 || (preconditioner_xi==0)
                        % Super-super-diagonal in L
                        ell = L + 2;
                        if (ell <= Nxi-1)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L+2)*(L+1)/((2*L+5)*(2*L+3))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L+2)*(L+1)/((2*L+5)*(2*L+3)))
                        end
                        
                        % Sub-sub-diagonal in L
                        ell = L - 2;
                        if (ell >= 0)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L-1)*L/((2*L-3)*(2*L-1))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L-1)*L/((2*L-3)*(2*L-1)))
                        end
                    end
                end
            end
        end
    end
    
    %{
    % -----------------------------------------
    % Add d/dalpha terms:
    % -----------------------------------------
    
    if whichMatrix ~= 2
        ExBTermSpatialPart = (gamma/2)*Delta*dPhiHatdpsiHat*DHat.*BHat_sub_zeta;
        if useDKESExBDrift
            ExBTermSpatialPart = ExBTermSpatialPart / FSABHat2;
        else
            ExBTermSpatialPart = ExBTermSpatialPart ./ (BHat.*BHat);
        end
        
        magneticDriftFactor = Delta*THat*DHat./(2*Z*(BHat.^3));
        if magneticDriftScheme>0
            magneticDriftSpatialPart1 = magneticDriftFactor .* (BHat_sub_zeta.*dBHatdpsiHat - BHat_sub_psi.*dBHatdzeta);
            magneticDriftSpatialPart2 = 2*BHat.*magneticDriftFactor .* (dBHat_sub_psi_dzeta - dBHat_sub_zeta_dpsiHat);
        else
            magneticDriftSpatialPart1 = zeros(Nalpha,Nzeta);
            magneticDriftSpatialPart2 = zeros(Nalpha,Nzeta);
        end
        if magneticDriftScheme==2
            magneticDriftSpatialPart3 = magneticDriftFactor .* BDotCurlB .* BHat_sup_theta ./ (BHat.*DHat);
        else
            magneticDriftSpatialPart3 = zeros(Nalpha,Nzeta);
        end
        
        % 20160328:
        % This nonlinear df1/dalpha term appears in the SFINCS technical
        % documentation (eq 61) but not in our latest DKE with Phi1.
        if false
            nonlinearTermSpatialPart = -gamma*Delta*DHat.*BHat_sub_psi.*dPhi1Hatdzeta./(2*BHat.*BHat);
        else
            nonlinearTermSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        for L=0:(Nxi-1)
            if whichMatrix==0 && L >= preconditioner_alpha_min_L
                ddalphaToUse = ddalpha_preconditioner;
            else
                ddalphaToUse = ddalpha;
            end
                        
            for izeta = zeta_to_impose_DKE
                ExBTerm = diag(ExBTermSpatialPart(:,izeta))*ddalphaToUse;
                magneticDriftTerm1 = diag(magneticDriftSpatialPart1(:,izeta))*ddalphaToUse;
                magneticDriftTerm2 = diag(magneticDriftSpatialPart2(:,izeta))*ddalphaToUse;
                magneticDriftTerm3 = diag(magneticDriftSpatialPart3(:,izeta))*ddalphaToUse;
                nonlinearTerm = diag(nonlinearTermSpatialPart(:,izeta))*ddalphaToUse;
                
                for ix = ixMin:Nx
                    rowIndices = sfincs_indices(ispecies, ix, L+1, 1:Nalpha, izeta, BLOCK_F, indexVars);

                    % Diagonal in L
                    colIndices = rowIndices;
                    addSparseBlock(rowIndices, colIndices, ExBTerm + nonlinearTerm ...
                        + x2(ix)*(magneticDriftTerm1*2*(3*L*L+3*L-2)+magneticDriftTerm2*(2*L*L+2*L-1))/((2*L+3)*(2*L-1))...
                        + x2(ix)*magneticDriftTerm3*(-2)*L*(L+1)/((2*L+3)*(2*L-1)))
    
                    if whichMatrix>0 || (preconditioner_xi==0)
                        % Super-super-diagonal in L
                        ell = L + 2;
                        if (ell <= Nxi-1)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, 1:Nalpha, izeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L+2)*(L+1)/((2*L+5)*(2*L+3))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L+2)*(L+1)/((2*L+5)*(2*L+3)))
                        end
                        
                        % Sub-sub-diagonal in L
                        ell = L - 2;
                        if (ell >= 0)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, 1:Nalpha, izeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L-1)*L/((2*L-3)*(2*L-1))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L-1)*L/((2*L-3)*(2*L-1)))
                        end
                    end
                end
            end
        end
    end
    
    % -----------------------------------------
    % Add d/dzeta terms:
    % -----------------------------------------
    
    if whichMatrix ~= 2
        streamingTermSpatialPart = sqrtT/sqrtm*BHat_sup_zeta./BHat;
        
        ExBTermSpatialPart = -(gamma/2)*Delta*dPhiHatdpsiHat*DHat.*BHat_sub_theta;
        if useDKESExBDrift
            ExBTermSpatialPart = ExBTermSpatialPart / FSABHat2;
        else
            ExBTermSpatialPart = ExBTermSpatialPart ./ (BHat.*BHat);
        end
        
        
        magneticDriftFactor = Delta*THat*DHat./(2*Z*(BHat.^3));
        if magneticDriftScheme>0
            magneticDriftSpatialPart1 = magneticDriftFactor .* (-BHat_sub_theta.*dBHatdpsiHat + BHat_sub_psi.*dBHatdtheta);
            magneticDriftSpatialPart2 = 2*BHat.*magneticDriftFactor .* (-dBHat_sub_psi_dtheta + dBHat_sub_theta_dpsiHat);
        else
            magneticDriftSpatialPart1 = zeros(Nalpha,Nzeta);
            magneticDriftSpatialPart2 = zeros(Nalpha,Nzeta);
        end
        if magneticDriftScheme==2
            magneticDriftSpatialPart3 = magneticDriftFactor .* BDotCurlB .* BHat_sup_zeta ./ (BHat.*DHat);
        else
            magneticDriftSpatialPart3 = zeros(Nalpha,Nzeta);
        end
        %{
        magneticDriftSpatialPart1 = zeros(Nalpha,Nzeta);
        magneticDriftSpatialPart2 = zeros(Nalpha,Nzeta);
        magneticDriftSpatialPart3 = zeros(Nalpha,Nzeta);
        %}
        
        % 20160328:
        % This nonlinear df1/dalpha term appears in the SFINCS technical
        % documentation (eq 61) but not in our latest DKE with Phi1.
        if false
            nonlinearTermSpatialPart = gamma*Delta*DHat.*BHat_sub_psi.*dPhi1Hatdalpha./(2*BHat.*BHat);
        else
            nonlinearTermSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        for L=0:(Nxi-1)
            if whichMatrix==0 && L >= preconditioner_zeta_min_L
                ddzetaToUse = ddzeta_preconditioner;
            else
                ddzetaToUse = ddzeta;
            end
                        
            for ialpha = 1:Nalpha
                streamingTerm = diag(streamingTermSpatialPart(ialpha,:))*ddzetaToUse;
                ExBTerm = diag(ExBTermSpatialPart(ialpha,:))*ddzetaToUse;
                magneticDriftTerm1 = diag(magneticDriftSpatialPart1(ialpha,:))*ddzetaToUse;
                magneticDriftTerm2 = diag(magneticDriftSpatialPart2(ialpha,:))*ddzetaToUse;
                magneticDriftTerm3 = diag(magneticDriftSpatialPart3(ialpha,:))*ddzetaToUse;
                nonlinearTerm = diag(nonlinearTermSpatialPart(ialpha,:))*ddzetaToUse;
                
                streamingTerm = streamingTerm(zeta_to_impose_DKE,:);
                ExBTerm = ExBTerm(zeta_to_impose_DKE,:);
                magneticDriftTerm1 = magneticDriftTerm1(zeta_to_impose_DKE,:);
                magneticDriftTerm2 = magneticDriftTerm2(zeta_to_impose_DKE,:);
                magneticDriftTerm3 = magneticDriftTerm3(zeta_to_impose_DKE,:);
                nonlinearTerm = nonlinearTerm(zeta_to_impose_DKE,:);
                
                for ix = ixMin:Nx
                    rowIndices = sfincs_indices(ispecies, ix, L+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);

                    % Diagonal in L
                    colIndices = sfincs_indices(ispecies, ix, L+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                    addSparseBlock(rowIndices, colIndices, ExBTerm + nonlinearTerm ...
                        + x2(ix)*(magneticDriftTerm1*2*(3*L*L+3*L-2)+magneticDriftTerm2*(2*L*L+2*L-1))/((2*L+3)*(2*L-1))...
                        + x2(ix)*magneticDriftTerm3*(-2)*L*(L+1)/((2*L+3)*(2*L-1)))
    
                    % Super-diagonal in L
                    ell = L + 1;
                    if (ell <= Nxi-1)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, streamingTerm*x(ix)*(L+1)/(2*L+3))
                    end
                    
                    % Sub-diagonal in L
                    ell = L - 1;
                    if (ell >= 0)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, streamingTerm*x(ix)*L/(2*L-1))
                    end
                    
                    if whichMatrix>0 || (preconditioner_xi==0)
                        % Super-super-diagonal in L
                        ell = L + 2;
                        if (ell <= Nxi-1)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L+2)*(L+1)/((2*L+5)*(2*L+3))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L+2)*(L+1)/((2*L+5)*(2*L+3)))
                        end
                        
                        % Sub-sub-diagonal in L
                        ell = L - 2;
                        if (ell >= 0)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                x2(ix)*(magneticDriftTerm1+magneticDriftTerm2)*(L-1)*L/((2*L-3)*(2*L-1))...
                                + x2(ix)*magneticDriftTerm3*(-3)*(L-1)*L/((2*L-3)*(2*L-1)))
                        end
                    end
                end
            end
        end
    end
    %}
        
    
    % -----------------------------------------
    % Add df/dxi terms:
    % -----------------------------------------
    
    if whichMatrix ~= 2
        mirrorTermSpatialPart = -sqrtT./(sqrtm*2*BHat.*BHat).*(BHat_sup_theta.*dBHatdtheta + BHat_sup_zeta.*dBHatdzeta);
        
        if includeElectricFieldTermInXiDot
            factor = gamma*Delta*dPhiHatdpsiHat*DHat./(4*(BHat.^3));
            ErTermSpatialPart = factor .* (BHat_sub_zeta.*dBHatdtheta - BHat_sub_theta.*dBHatdzeta);
            if ~force0RadialCurrentInEquilibrium
                ErTermSpatialPart = ErTermSpatialPart - factor.*(2*BHat).*(dBHat_sub_zeta_dtheta - dBHat_sub_theta_dzeta);
            end
        else
            ErTermSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        %if false
        if includePhi1 && includePhi1InKineticEquation
            nonlinearTermSpatialPart = -gamma*Z./(2*sqrtm*sqrtT*BHat).*(BHat_sup_theta.*dPhi1Hatdalpha + BHat_sup_zeta.*dPhi1Hatdzeta);
        else
            nonlinearTermSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        if magneticDriftScheme>0
        %if false
            factor = -Delta*THat*DHat./(2*Z*(BHat.^3));
            magneticDriftSpatialPart = factor.* ...
                (dBHatdtheta.*(dBHat_sub_psi_dzeta - dBHat_sub_zeta_dpsiHat) ...
                + dBHatdzeta.*(dBHat_sub_theta_dpsiHat - dBHat_sub_psi_dtheta));
            if ~ force0RadialCurrentInEquilibrium
                magneticDriftSpatialPart = magneticDriftSpatialPart ...
                    + factor.*dBHatdpsiHat.*(dBHat_sub_zeta_dtheta - dBHat_sub_theta_dzeta);
            end
        else
            magneticDriftSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        for L = 0:(Nxi-1)
            for ialpha = 1:Nalpha
                for ix = ixMin:Nx
                    rowIndices = sfincs_indices(ispecies, ix, L+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                    
                    % Diagonal in L
                    colIndices = rowIndices;
                    addToSparse(rowIndices, colIndices, ErTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L+1)*L/((2*L-1)*(2*L+3)) ...
                        + magneticDriftSpatialPart(ialpha,zeta_to_impose_DKE)*x2(ix)*(L+1)*L/((2*L-1)*(2*L+3)))
                    
                    % Super-diagonal in L
                    ell = L + 1;
                    if (ell <= Nxi-1)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                        addToSparse(rowIndices, colIndices, ...
                            x(ix)*mirrorTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L+1)*(L+2)/(2*L+3) ...
                            + (1/x(ix))*nonlinearTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L+1)*(L+2)/(2*L+3))
                    end
                    
                    % Sub-diagonal in L
                    ell = L - 1;
                    if (ell >= 0)
                        colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                        addToSparse(rowIndices, colIndices, ...
                            - x(ix)*mirrorTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L-1)*L/(2*L-1) ...
                            - (1/x(ix))*nonlinearTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L-1)*L/(2*L-1))
                    end
                    
                    if whichMatrix>0 || (preconditioner_xi==0)
                        % Super-super-diagonal in L
                        ell = L + 2;
                        if (ell <= Nxi-1)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                            addToSparse(rowIndices, colIndices, ...
                                ErTermSpatialPart(ialpha,zeta_to_impose_DKE)*(L+3)*(L+2)*(L+1)/((2*L+5)*(2*L+3)) ...
                                + magneticDriftSpatialPart(ialpha,zeta_to_impose_DKE)*x2(ix)*(L+3)*(L+2)*(L+1)/((2*L+5)*(2*L+3)))
                        end
                        
                        % Sub-sub-diagonal in L
                        ell = L - 2;
                        if (ell >= 0)
                            colIndices = sfincs_indices(ispecies, ix, ell+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                            addToSparse(rowIndices, colIndices, ...
                                ErTermSpatialPart(ialpha,zeta_to_impose_DKE)*(-L)*(L-1)*(L-2)/((2*L-3)*(2*L-1)) ...
                                + magneticDriftSpatialPart(ialpha,zeta_to_impose_DKE)*x2(ix)*(-L)*(L-1)*(L-2)/((2*L-3)*(2*L-1)))
                        end
                    end
                end
            end
        end

    end
    
    % -----------------------------------------
    % Add the collisionless df1/dx term:
    % -----------------------------------------
    
    if whichMatrix ~= 2
        if includeXDotTerm
            factor = -gamma*Delta*dPhiHatdpsiHat*DHat./(4*(BHat.^3));
            ErTermSpatialPart1 = factor .* (BHat_sub_theta.*dBHatdzeta - BHat_sub_zeta.*dBHatdtheta);
            if ~force0RadialCurrentInEquilibrium
                ErTermSpatialPart2 = factor.*(2*BHat).*(dBHat_sub_zeta_dtheta - dBHat_sub_theta_dzeta);
            else
                ErTermSpatialPart2 = zeros(Nalpha,Nzeta);
            end
        else
            ErTermSpatialPart1 = zeros(Nalpha,Nzeta);
            ErTermSpatialPart2 = zeros(Nalpha,Nzeta);
        end
        
        %if false
        if includePhi1 && includePhi1InKineticEquation
            nonlinearTermSpatialPart = -gamma*Z./(2*sqrtT*sqrtm*BHat).*(BHat_sup_theta.*dPhi1Hatdalpha + BHat_sup_zeta.*dPhi1Hatdzeta);
        else
            nonlinearTermSpatialPart = zeros(Nalpha,Nzeta);
        end
        
        for L = 0:(Nxi-1)
            if whichMatrix==0 && L >= preconditioner_x_min_L
                ddxToUse = ddx_preconditioner;
            else
                ddxToUse = ddx;
            end
            if pointAtX0
                % Do not enforce the kinetic equation at x=0:
                ddxToUse(1,:)=0;
                if L ~= 0
                    ddxToUse(:,1)=0;
                end
            end
            xddxToUse = diag(x)*ddxToUse;
            
            for ialpha = 1:Nalpha
                for izeta = zeta_to_impose_DKE
                    rowIndices = sfincs_indices(ispecies, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);

                    % Diagonal in L
                    colIndices = rowIndices;
                    addSparseBlock(rowIndices, colIndices, ...
                        xddxToUse*ErTermSpatialPart1(ialpha,izeta)*2*(3*L*L+3*L-2)/((2*L+3)*(2*L-1))...
                        + ErTermSpatialPart2(ialpha,izeta)*(2*L*L+2*L-1)/((2*L+3)*(2*L-1)))
                    
                    % Super-diagonal in L
                    ell = L + 1;
                    if (ell <= Nxi-1)
                        colIndices = sfincs_indices(ispecies, 1:Nx, ell+1, ialpha, izeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, ddxToUse*nonlinearTermSpatialPart(ialpha,izeta)*(L+1)/(2*L+3))
                    end
                    
                    % Sub-diagonal in L
                    ell = L - 1;
                    if (ell >= 0)
                        colIndices = sfincs_indices(ispecies, 1:Nx, ell+1, ialpha, izeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndices, ddxToUse*nonlinearTermSpatialPart(ialpha,izeta)*L/(2*L-1))
                    end

                    if whichMatrix>0 || (preconditioner_xi==0)
                        % Super-super-diagonal in L
                        ell = L + 2;
                        if (ell <= Nxi-1)
                            colIndices = sfincs_indices(ispecies, 1:Nx, ell+1, ialpha, izeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                xddxToUse*(ErTermSpatialPart1(ialpha,izeta)+ErTermSpatialPart2(ialpha,izeta))...
                                *(L+2)*(L+1)/((2*L+5)*(2*L+3)))
                        end
                        
                        % Sub-sub-diagonal in L
                        ell = L - 2;
                        if (ell >= 0)
                            colIndices = sfincs_indices(ispecies, 1:Nx, ell+1, ialpha, izeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, ...
                                xddxToUse*(ErTermSpatialPart1(ialpha,izeta)+ErTermSpatialPart2(ialpha,izeta))...
                                *(L-1)*L/((2*L-3)*(2*L-1)))
                        end
                    end
                end
            end
        end
    end
    
    %{
    % Next section was removed 20160328 for the new Phi1 implementation.
    % -----------------------------------------
    % Add the Phi1 terms that act on f0 rather than f1.
    % These terms are linear and give the adiabatic response.
    % -----------------------------------------
    
    if includePhi1 && (whichMatrix ~= 2)
        df0dx = -2*((mHat/(pi*THat))^(3/2))*nHat*x.*expx2;
        % If there is a point at x=0, then dfxdx=0 there, so we do not need
        % to take any special action in this case.
        
        L=1;
        
        % dPhi1/dalpha term
        spatialPart = -gamma*Z*BHat_sup_theta./(2*sqrtT*sqrtm*BHat);
        for izeta = 1:Nzeta
            factor = diag(spatialPart(:,izeta))*ddalpha;
            for ix = 1:Nx
                rowIndices = sfincs_indices(ispecies,ix,L+1,1:Nalpha,izeta,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,1:Nalpha,izeta,BLOCK_QN, indexVars);
                addSparseBlock(rowIndices, colIndices, factor*df0dx(ix))
            end
        end
        
        % dPhi1/dzeta term
        spatialPart = -gamma*Z*BHat_sup_zeta./(2*sqrtT*sqrtm*BHat);
        for ialpha = 1:Nalpha
            factor = diag(spatialPart(ialpha,:))*ddzeta;
            for ix = 1:Nx
                rowIndices = sfincs_indices(ispecies,ix,L+1,ialpha,1:Nzeta,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,ialpha,1:Nzeta,BLOCK_QN, indexVars);
                addSparseBlock(rowIndices, colIndices, factor*df0dx(ix))
            end
        end
    end
    %}
    
    % -----------------------------------------
    % Add the radial ExB-drift terms in the residual (R_E), which are also used
    % for some terms in the Jacobian.
    % -----------------------------------------
    
    if includePhi1 && includePhi1InKineticEquation && (whichMatrix ~= 2)
        L=0;
        
        % dPhi1/dalpha term
        spatialPart = -(Delta*nHat*mHat*sqrtm*gamma/(2*pi*sqrtpi*THat*sqrtT)) ...
            * (DHat.*exp(-(gamma*Z/THat)*Phi1Hat).*BHat_sub_zeta)./(BHat.*BHat);
        for ix = ixMin:Nx
            spatialAndXPart = expx2(ix)*(spatialPart .* (dnHatdpsiHats(ispecies)/nHat ...
                + gamma*Z/THat*dPhiHatdpsiHat ...
                + (x2(ix) - 3/2 + (gamma*Z/THat)*Phi1Hat)*dTHatdpsiHats(ispecies)/THat));
            for izeta = zeta_to_impose_DKE
                rowIndices = sfincs_indices(ispecies,ix,L+1,1:Nalpha,izeta,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,1:Nalpha,izeta,BLOCK_QN, indexVars);
                addSparseBlock(rowIndices, colIndices, diag(spatialAndXPart(:,izeta))*ddalpha)
            end
        end
        
        % dPhi1/dzeta term
        spatialPart = (Delta*nHat*mHat*sqrtm*gamma/(2*pi*sqrtpi*THat*sqrtT)) ...
            * (DHat.*exp(-(gamma*Z/THat)*Phi1Hat).*BHat_sub_theta)./(BHat.*BHat);
        for ix = ixMin:Nx
            spatialAndXPart = expx2(ix)*(spatialPart .* (dnHatdpsiHats(ispecies)/nHat ...
                + gamma*Z/THat*dPhiHatdpsiHat ...
                + (x2(ix) - 3/2 + (gamma*Z/THat)*Phi1Hat)*dTHatdpsiHats(ispecies)/THat));            
            for ialpha = 1:Nalpha
                rowIndices = sfincs_indices(ispecies,ix,L+1,ialpha,zeta_to_impose_DKE,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,ialpha,1:Nzeta,BLOCK_QN, indexVars);
                temp = diag(spatialAndXPart(ialpha,:))*ddzeta;
                addSparseBlock(rowIndices, colIndices, temp(zeta_to_impose_DKE,:))
            end
        end
    end
    
    
    % -----------------------------------------
    % Add the terms in the Jacobian associated with Phi1 in the radial
    % drift term but which do not appear in the residual.
    % -----------------------------------------
    
    if includePhi1 && includePhi1InKineticEquation && (whichMatrix == 0 || whichMatrix==1)
        factors = -gamma*Z*Delta*nHat*mHat*sqrtm/(THat*2*pi*sqrtpi*THat*sqrtT);
        spatialPartOfMagneticDriftTerm = (THat/Z)*(DHat./(BHat.*BHat.*BHat)).*(BHat_sub_theta .* dBHatdzeta - BHat_sub_zeta.*dBHatdtheta);
        spatialPartOfExBDriftTerm = gamma*DHat./(BHat.*BHat).*(BHat_sub_theta .* dPhi1Hatdzeta - BHat_sub_zeta.*dPhi1Hatdalpha);
        for ix = ixMin:Nx
            xPart = factors*expx2(ix)*exp(-(gamma*Z/THat)*Phi1Hat) ...
                .* (dnHatdpsiHats(ispecies)/nHat + gamma*Z/THat*dPhiHatdpsiHat ...
                + (x2(ix) - 5/2 + (gamma*Z/THat)*Phi1Hat)*dTHatdpsiHats(ispecies)/THat);
            % In the above line, note that we have replaced 3/2 -> 5/2
            % because 2 terms were combined.
            
            L=0;
            stuffToAdd = xPart .* ((4/3)*x2(ix)*spatialPartOfMagneticDriftTerm + spatialPartOfExBDriftTerm);
            for ialpha = 1:Nalpha
                rowIndices = sfincs_indices(ispecies,ix,L+1,ialpha,zeta_to_impose_DKE,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,ialpha,zeta_to_impose_DKE,BLOCK_QN, indexVars);
                addToSparse(rowIndices, colIndices, stuffToAdd(ialpha,zeta_to_impose_DKE))
            end

            L=2;
            stuffToAdd = xPart .* ((2/3)*x2(ix)*spatialPartOfMagneticDriftTerm);
            for ialpha = 1:Nalpha
                rowIndices = sfincs_indices(ispecies,ix,L+1,ialpha,zeta_to_impose_DKE,BLOCK_F, indexVars);
                colIndices = sfincs_indices(1,1,1,ialpha,zeta_to_impose_DKE,BLOCK_QN, indexVars);
                addToSparse(rowIndices, colIndices, stuffToAdd(ialpha,zeta_to_impose_DKE))
            end
            
        end
    end
    
    % -----------------------------------------
    % Add the terms in the Jacobian associated with dN/dPhi1 for the nonlinear 
    % term N = E|| df/dv||.
    % This term appears in the Jacobian but is not used for the residual.
    % -----------------------------------------
    
    if includePhi1 && includePhi1InKineticEquation && ((whichMatrix == 0 && (~ reusePreconditioner))  || whichMatrix==1)
        spatialPart = -gamma*Z./(2*sqrtT*sqrtm*BHat);
        for ialphaRow=1:Nalpha
            colIndices_zeta = sfincs_indices(1,1,1,ialpha,1:Nzeta,BLOCK_QN, indexVars);
            for izetaRow = zeta_to_impose_DKE
                colIndices_alpha = sfincs_indices(1,1,1,1:Nalpha,izetaRow,BLOCK_QN, indexVars);
                for ell=0:(Nxi-1)
                    indices = sfincs_indices(ispecies,1:Nx,ell+1,ialphaRow,izetaRow,BLOCK_F, indexVars);
                    df1dx = ddx*stateVector(indices);
                    L=ell-1; % So L+1 = ell
                    nonlinearTerm_Lp1 = spatialPart(ialphaRow,izetaRow)*( (L+1)*(L+2)/(2*L+3)*stateVector(indices)./x + (L+1)/(2*L+3)*df1dx);
                    L=ell+1; % So L-1 = ell
                    nonlinearTerm_Lm1 = spatialPart(ialphaRow,izetaRow)*(-L*(L-1)/(2*L-1)*stateVector(indices)./x + L/(2*L-1)*df1dx);
                    
                    for ix=ixMin:Nx
                        % L+1=ell terms
                        if ell>0
                            L = ell-1;
                            rowIndices = sfincs_indices(ispecies,ix,L+1,ialphaRow,izetaRow,BLOCK_F, indexVars);
                            
                            % Add d/dalpha (on Phi1) term:
                            addSparseBlock(rowIndices, colIndices_alpha, BHat_sup_theta(ialphaRow,izetaRow)*nonlinearTerm_Lp1(ix)*ddalpha(ialphaRow,:))
                            % Add d/dzeta (on Phi1) term:
                            addSparseBlock(rowIndices, colIndices_zeta, BHat_sup_zeta(ialphaRow,izetaRow)*nonlinearTerm_Lp1(ix)*ddzeta(izetaRow,:))
                        end
                        
                        % L-1=ell terms
                        if ell<Nxi-1
                            L = ell+1;
                            rowIndices = sfincs_indices(ispecies,ix,L+1,ialphaRow,izetaRow,BLOCK_F, indexVars);
                            
                            % Add d/dalpha (on Phi1) term:
                            addSparseBlock(rowIndices, colIndices_alpha, BHat_sup_theta(ialphaRow,izetaRow)*nonlinearTerm_Lm1(ix)*ddalpha(ialphaRow,:))
                            % Add d/dzeta (on Phi1) term:
                            addSparseBlock(rowIndices, colIndices_zeta, BHat_sup_zeta(ialphaRow,izetaRow)*nonlinearTerm_Lm1(ix)*ddzeta(izetaRow,:))
                        end
                    end
                end
            end
        end
    end
end

switch (collisionOperator)
    case 0
        % Linearized Fokker-Planck operator
        
        xWith0s = [0, xPotentials(2:(end-1))', 0];
        M21 = 4*pi*diag(xWith0s.^2) * interpolateXToXPotentials;
        xWith0s = [0, xPotentials(2:(end-1))', 0];
        M32 = -2*diag(xWith0s.^2);
        LaplacianTimesX2WithoutL = diag(xPotentials.^2)*d2dx2Potentials + 2*diag(xPotentials)*ddxPotentials;
        
        x2 = x.*x;
        expx2 = exp(-x.*x);
        
        CE = zeros(Nx, Nx, Nspecies);
        nuD = zeros(Nx, Nspecies);
        regridSpecies = zeros(Nx, Nx, Nspecies, Nspecies);
        M12IncludingX0 = zeros(Nx, NxPotentials, Nspecies, Nspecies, NL);
        M13IncludingX0 = zeros(Nx, NxPotentials, Nspecies, Nspecies, NL);
        for speciesA = 1:Nspecies
            for speciesB = 1:Nspecies
                speciesFactorTest = 3*sqrtpi/4*nHats(speciesB) * Zs(speciesA)*Zs(speciesA)*Zs(speciesB)*Zs(speciesB)/(THats(speciesA)^(3/2)*sqrt(mHats(speciesA)));
                xb = x * sqrt(THats(speciesA)*mHats(speciesB)/(THats(speciesB)*mHats(speciesA)));
                erfs = erf(xb);
                xb2  = xb.*xb;
                expxb2 = exp(-xb2);
                Psi = (erfs - 2/sqrtpi*xb .* expxb2) ./ (2*xb2);
                nuD(:,speciesA) = nuD(:,speciesA) + (speciesFactorTest * (erfs - Psi) ./ (x.^3));
                coefficientOfd2dx2 = Psi./x;
                coefficientOfddx = -2*THats(speciesA)*mHats(speciesB)/(THats(speciesB)*mHats(speciesA))*Psi*(1-mHats(speciesA)/mHats(speciesB)) ...
                    + (erfs - Psi)./(x.*x);
                diagonalPartOfCE = 4/sqrtpi*THats(speciesA)/THats(speciesB)*sqrt(THats(speciesA)*mHats(speciesB)/(THats(speciesB)*mHats(speciesA))) .* expxb2;
                CE(:,:,speciesA) = CE(:,:,speciesA) + speciesFactorTest*(diag(coefficientOfd2dx2)*d2dx2 + diag(coefficientOfddx)*ddx + diag(diagonalPartOfCE));
                
                if speciesA==speciesB
                    regridSpecies(:,:,speciesA,speciesB) = eye(Nx);
                else
                    regridSpecies(:,:,speciesA,speciesB) = sfincs_polynomialInterpolationMatrix(x,xb,sfincs_xWeight(x),sfincs_xWeight(xb));
                end
                
                speciesFactorField = nHats(speciesA) * Zs(speciesA)*Zs(speciesA)*Zs(speciesB)*Zs(speciesB)...
                    * mHats(speciesA) * THats(speciesB)/(THats(speciesA)^(5/2) * mHats(speciesB) * sqrt(mHats(speciesA)));
                for L=0:(NL-1)
                    regridUniformToPolynomial = m20120925_09_makeHighOrderUniformRegriddingMatrix(xPotentials,xb,L,'H');
                    M12IncludingX0(:,:,speciesA, speciesB, L+1) = -3/(2*pi)*speciesFactorField*diag(expx2)* regridUniformToPolynomial...
                        * (diag(xPotentials*(1-mHats(speciesA)/mHats(speciesB)))*ddxPotentials + eye(NxPotentials)) ;
                    regridUniformToPolynomial = m20120925_09_makeHighOrderUniformRegriddingMatrix(xPotentials,xb,L,'G');
                    M13IncludingX0(:,:,speciesA, speciesB, L+1) = 3/(2*pi) * speciesFactorField * diag(x2.*expx2) * regridUniformToPolynomial* d2dx2Potentials;
                end
            end
        end
        
        for L=0:(Nxi-1)
            if L <= (NL-1)
                % Add Rosenbluth potential stuff
                
                M22 = LaplacianTimesX2WithoutL-L*(L+1)*eye(NxPotentials);
                % Add Dirichlet or Neumann boundary condition for
                % potentials at x=0:
                if L==0
                    M22(1,:)=ddxPotentials(1,:);
                else
                    M22(1,:) = 0;
                    M22(1,1) = 1;
                end
                M33 = M22;
                
                % Add Robin boundary condition for potentials at x=xMaxPotentials:
                M22(NxPotentials,:) = xMaxPotentials*ddxPotentials(NxPotentials,:);
                M22(NxPotentials,NxPotentials) = M22(NxPotentials,NxPotentials) + L+1;
                
                % Boundary conditions:
                M33(NxPotentials,:) = xMaxPotentials*xMaxPotentials*d2dx2Potentials(NxPotentials,:) + (2*L+1)*xMaxPotentials*ddxPotentials(NxPotentials,:);
                M33(NxPotentials,NxPotentials) = M33(NxPotentials,NxPotentials) + (L*L-1);
                
                if L~=0
                    M22(NxPotentials,1)=0;
                    M33(NxPotentials,1)=0;
                end
                
                M22BackslashM21 = M22 \ M21;
                M33BackslashM32 = M33 \ M32;
                
            end
            
            for speciesA = 1:Nspecies
                if whichMatrix > 0
                    % We're not making the preconditioner.
                    speciesBToUse = 1:Nspecies;
                else
                    % We're making the preconditioner.
                    switch preconditioner_species
                        case 0
                            % Full inter-species coupling
                            speciesBToUse = 1:Nspecies;
                        case 1
                            % No inter-species coupling
                            speciesBToUse = speciesA;
                        otherwise
                            error('Invalid preconditioner_species')
                    end
                end
                for speciesB = speciesBToUse
                    % Add CD
                    CD = 3*nHats(speciesA)*Zs(speciesA)*Zs(speciesA)*Zs(speciesB)*Zs(speciesB)...
                        * mHats(speciesA)/(mHats(speciesB)*THats(speciesA)*sqrt(THats(speciesA)*mHats(speciesA))) ...
                        * diag(expx2) * regridSpecies(:,:,speciesA, speciesB);
                    
                    if speciesA == speciesB
                        M11 = -0.5*diag(nuD(:,speciesA))*L*(L+1) + CE(:,:,speciesA) + CD;
                    else
                        M11 = CD;
                    end
                    
                    if L <= (NL-1)
                        % Add terms of the collision operator involving
                        % the Rosenbluth potentials.
                        if xGridScheme>=5
                            CHat = M11 + squeeze(RosenbluthPotentialTerms(speciesA,speciesB,L+1,:,:));
                        else
                            M13 = M13IncludingX0(:,:,speciesA, speciesB, L+1);
                            M12 = M12IncludingX0(:,:,speciesA, speciesB, L+1);
                            
                            % Add Dirichlet or Neumann boundary condition for
                            % potentials at x=0:
                            if L~=0
                                M12(:,1) = 0;
                                M13(:,1) = 0;
                            end
                            
                            CHat = M11 -  (M12 - M13 * M33BackslashM32) * M22BackslashM21;
                        end
                    else
                        CHat = M11;
                    end
                    
                    % The lines below are invoked to make the preconditioner.
                    if whichMatrix == 0 && L >= preconditioner_x_min_L
                        switch preconditioner_x
                            case 0
                                % Nothing to do here.
                            case 1
                                CHat = diag(diag(CHat));
                            case 2
                                CHat = triu(CHat);
                            case 3
                                mask = eye(Nx) + diag(ones(Nx-1,1),1) + diag(ones(Nx-1,1),-1);
                                CHat = CHat .* mask;
                            case 4
                                mask = eye(Nx) + diag(ones(Nx-1,1),1);
                                CHat = CHat .* mask;
                            otherwise
                                error('Invalid preconditioner_x')
                        end
                        
                    end
                    
                    if pointAtX0
                        CHat(1,:) = 0;
                        if L ~= 0
                            CHat(:,1) = 0;
                        end
                    end
                    
                    % At this point, CHat holds the collision operator
                    % divided by \bar{nu}
                    
                    for ialpha = 1:Nalpha
                        for izeta = zeta_to_impose_DKE
                            rowIndices = sfincs_indices(speciesA, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                            colIndices = sfincs_indices(speciesB, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                            addSparseBlock(rowIndices, colIndices, -nu_n*CHat)
                        end
                    end
                    
                    
                end
            end
            
        end
        % End of multi-species Fokker-Planck collision
        % operator.
        
    case (1)
        % Pure pitch angle scattering collision operator
        
        % First, assemble the deflection frequency nuD for
        % species A, which involves a sum over species B:
        nuD = zeros(Nx, Nspecies);
        for speciesA = 1:Nspecies
            for speciesB = 1:Nspecies
                speciesFactorTest = 3*sqrtpi/4*nHats(speciesB) * Zs(speciesA)*Zs(speciesA)*Zs(speciesB)*Zs(speciesB)/(THats(speciesA)^(3/2)*sqrt(mHats(speciesA)));
                xb = x * sqrt(THats(speciesA)*mHats(speciesB)/(THats(speciesB)*mHats(speciesA)));
                erfs = erf(xb);
                xb2  = xb.*xb;
                expxb2 = exp(-xb2);
                Psi = (erfs - 2/sqrtpi*xb .* expxb2) ./ (2*xb2);
                nuD(:,speciesA) = nuD(:,speciesA) + (speciesFactorTest * (erfs - Psi) ./ (x.^3));
            end
        end
        
        % Now that nuD has been assembled,
        for L=1:(Nxi-1)  % We can skip L=0 since C \propto L*(L+1)
            for iSpecies = 1:Nspecies
                CHat = -0.5*nuD(:,iSpecies)*L*(L+1);
                
                % At this point, CHat holds the collision operator
                % divided by \bar{nu}

                if pointAtX0
                    CHat(1,:) = 0;
                    % We skip L=0 in this loop, so we know L is nonzero.
                    % Hence,
                    CHat(:,1) = 0;
                end
                
                for ialpha = 1:Nalpha
                    for izeta = zeta_to_impose_DKE
                        indices = sfincs_indices(iSpecies, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                        addToSparse(indices, indices, -nu_n*CHat)
                    end
                end
            end
        end
        
        % End of new multi-species pitch-angle scattering collision
        % operator.
        
    otherwise
        error('collisionOperator must be 0 or 1.')
end

% --------------------------------------------------
% If there is a grid point at x=0, impose the appropriate boundary
% condition there.
% --------------------------------------------------

if whichMatrix ~= 2 && pointAtX0
    L = 0;
    if (whichMatrix==0 && L >= preconditioner_x_min_L)
        ddxToUse = ddx_preconditioner;
    else
        ddxToUse = ddx;
    end
    
    for ispecies = 1:Nspecies
        for ialpha = 1:Nalpha
            for izeta = zeta_to_impose_DKE
                % For L=0, force df/dx=0 at x=0 (regularity)
                L = 0;
                rowIndex = sfincs_indices(ispecies, 1, L+1, ialpha, izeta, BLOCK_F, indexVars);
                colIndices = sfincs_indices(ispecies, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                addSparseBlock(rowIndex, colIndices, ddxToUse(1,:))
                
                % For L>0, set f=0 at x=0:
                indices = sfincs_indices(ispecies, 1, 2:Nxi, ialpha, izeta, BLOCK_F, indexVars);
                addToSparse(indices, indices, ones(size(indices)))
            end
        end
    end
end

% --------------------------------------------------
% Add density and pressure constraints.
% --------------------------------------------------

if whichMatrix ~= 2
    switch constraintScheme
        case 0
            % Do nothing.
            
        case 1
            L=0;
            for ispecies = 1:Nspecies
                for ialpha = 1:Nalpha
                    for izeta = 1:Nzeta
                        colIndices = sfincs_indices(ispecies, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                        
                        rowIndex = sfincs_indices(ispecies, 1, 1, 1, 1, BLOCK_DENSITY_CONSTRAINT, indexVars);
                        addSparseBlock(rowIndex, colIndices, alphaWeights(ialpha)*zetaWeights(izeta)*(x2.*xWeights)' / (DHat(ialpha,izeta)))
                        
                        rowIndex = sfincs_indices(ispecies, 1, 1, 1, 1, BLOCK_PRESSURE_CONSTRAINT, indexVars);
                        addSparseBlock(rowIndex, colIndices, alphaWeights(ialpha)*zetaWeights(izeta)*(x2.*x2.*xWeights)' / (DHat(ialpha,izeta)))
                    end
                end
            end
            
        case 2
            L=0;
            for ispecies = 1:Nspecies
                % I think this loop should go from 1 rather than from
                % ixMin. But I could be convinced otherwise.
                for ix = 1:Nx
                    rowIndex = sfincs_indices(ispecies, ix, 1, 1, 1, BLOCK_F_CONSTRAINT, indexVars);
                    for ialpha = 1:Nalpha
                        colIndices = sfincs_indices(ispecies, ix, L+1, ialpha, 1:Nzeta, BLOCK_F, indexVars);
                        addSparseBlock(rowIndex, colIndices, alphaWeights(ialpha)*(zetaWeights')./DHat(ialpha,:))
                    end
                end
            end
            
        otherwise
            error('Invalid constraintScheme')
    end
end

% --------------------------------------------------
% Add sources.
% --------------------------------------------------

if whichMatrix ~= 2
    switch constraintScheme
        case 0
            % Do nothing
            
        case 1
            xPartOfSource1 = (1/(pi*sqrtpi))*(   -x2 + 5/2).*expx2;
            xPartOfSource2 = (1/(pi*sqrtpi))*(2/3*x2 -   1).*expx2;
            %xPartOfSource1 = (x2-5/2).*expx2;
            %xPartOfSource2 = (x2-3/2).*expx2;
            
            L=0;
            for ispecies = 1:Nspecies
                for ix = ixMin:Nx
                    for ialpha = 1:Nalpha
                        rowIndices = sfincs_indices(ispecies, ix, L+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                        
                        colIndex = sfincs_indices(ispecies, 1, 1, 1, 1, BLOCK_DENSITY_CONSTRAINT, indexVars);
                        addSparseBlock(rowIndices, colIndex, xPartOfSource1(ix)*ones(numel(zeta_to_impose_DKE),1))
                        
                        colIndex = sfincs_indices(ispecies, 1, 1, 1, 1, BLOCK_PRESSURE_CONSTRAINT, indexVars);
                        addSparseBlock(rowIndices, colIndex, xPartOfSource2(ix)*ones(numel(zeta_to_impose_DKE),1))
                    end
                end
            end
            
        case 2
            L=0;
            for ispecies = 1:Nspecies
                for ix = ixMin:Nx
                    colIndex = sfincs_indices(ispecies, ix, 1, 1, 1, BLOCK_F_CONSTRAINT, indexVars);
                    for ialpha = 1:Nalpha
                        rowIndices = sfincs_indices(ispecies, ix, L+1, ialpha, zeta_to_impose_DKE, BLOCK_F, indexVars);
                        addSparseBlock(rowIndices, colIndex, ones(numel(zeta_to_impose_DKE),1))
                    end
                end
            end
        otherwise
            error('Invalid constraintScheme')
    end
end

% --------------------------------------------------
% Add quasineutrality equation.
% --------------------------------------------------

% Part with column indices in BLOCK_F, which is also used for the residual:

if whichMatrix ~= 2 && includePhi1
    switch quasineutralityOption
        case 1
            ispecies_max = Nspecies;
        case 2
            ispecies_max = 1;
        otherwise
            error('Invalid quasineutralityOption')
    end
    L = 0;
    xPart = x2.*xWeights;
    speciesFactor = 4*pi*Zs .* ((THats./mHats).^(3/2));
    for ialpha = 1:Nalpha
        for izeta = 1:Nzeta
            rowIndex = sfincs_indices(1, 1, 1, ialpha, izeta, BLOCK_QN, indexVars);
            for ispecies = 1:ispecies_max
                colIndices = sfincs_indices(ispecies, 1:Nx, L+1, ialpha, izeta, BLOCK_F, indexVars);
                addSparseBlock(rowIndex, colIndices, xPart' *speciesFactor(ispecies))
            end
        end
    end
end

% For quasineutralityOption=1: Part of the Jacobian with column indices in BLOCK_QN, which is NOT used for the residual:
if includePhi1 && (quasineutralityOption==1) && (whichMatrix==0 || whichMatrix==1)
    stuffToAdd = zeros(Nalpha,Nzeta);
    for ispecies = 1:Nspecies
        stuffToAdd = stuffToAdd - gamma*Zs(ispecies)*Zs(ispecies)*nHats(ispecies)/THats(ispecies) ...
            *exp(-gamma*Zs(ispecies)/THats(ispecies)*Phi1Hat);
    end
    if withAdiabatic
        stuffToAdd = stuffToAdd - gamma*adiabaticZ*adiabaticZ*adiabaticNHat/adiabaticTHat ...
            *exp(-gamma*adiabaticZ/adiabaticTHat*Phi1Hat);
    end
    
    for ialpha = 1:Nalpha
        indices = sfincs_indices(1, 1, 1, ialpha, 1:Nzeta, BLOCK_QN, indexVars);
        addToSparse(indices, indices, stuffToAdd(ialpha,:))
    end
end

% For quasineutralityOption=2: Part of the Jacobian with column indices in BLOCK_QN, which IS used for the residual:
if includePhi1 && (quasineutralityOption==2) && (whichMatrix~=2)
    factor = -gamma*(Zs(1)*Zs(1)*nHats(1)/THats(1) ...
        +adiabaticZ*adiabaticZ*adiabaticNHat/adiabaticTHat);
    stuffToAdd = factor * ones(Nzeta,1);
    for ialpha = 1:Nalpha
        indices = sfincs_indices(1, 1, 1, ialpha, 1:Nzeta, BLOCK_QN, indexVars);
        addToSparse(indices, indices, stuffToAdd)
    end
end

% --------------------------------------------------
% Add Lagrange multiplier lambda
% --------------------------------------------------

if whichMatrix ~= 2 && includePhi1
    colIndex = sfincs_indices(1, 1, 1, 1, 1, BLOCK_PHI1_CONSTRAINT, indexVars);
    for ialpha = 1:Nalpha
        rowIndices = sfincs_indices(1, 1, 1, ialpha, 1:Nzeta, BLOCK_QN, indexVars);
        addSparseBlock(rowIndices, colIndex, ones(Nzeta,1))
    end
end

% --------------------------------------------------
% Add phi1 constraint.
% --------------------------------------------------

if whichMatrix ~= 2 && includePhi1
    for ialpha = 1:Nalpha
        colIndices = sfincs_indices(1, 1, 1, ialpha, 1:Nzeta, BLOCK_QN, indexVars);
        rowIndex = sfincs_indices(1, 1, 1, 1, 1, BLOCK_PHI1_CONSTRAINT, indexVars);
        addSparseBlock(rowIndex, colIndices, alphaWeights(ialpha)*(zetaWeights') ./ (DHat(ialpha,:)))
    end
end

% --------------------------------------------------
% End of adding entries to the matrix.
% --------------------------------------------------

fprintf('Time to contruct %s: %g seconds.\n',whichMatrixName,toc(populateMatrixTic))
tic
matrix = createSparse();
fprintf('Time to sparsify %s: %g seconds.\n',whichMatrixName,toc)
fprintf('This matrix has %d nonzeros. Fill fraction = %g. Original estimated nnz = %d\n',nnz(matrix), nnz(matrix)/(matrixSize*matrixSize),estimated_nnz)

index_lookup = zeros(matrixSize,5);
for ispecies = 1:Nspecies
    for ix = 1:Nx
        for ixi = 1:Nxi
            for ialpha = 1:Nalpha
                for izeta = 1:Nzeta
                    index = sfincs_indices(ispecies, ix, ixi, ialpha, izeta, BLOCK_F, indexVars);
                    index_lookup(index,1) = ispecies;
                    index_lookup(index,2) = ix;
                    index_lookup(index,3) = ixi;
                    index_lookup(index,4) = ialpha;
                    index_lookup(index,5) = izeta;
                end
            end
        end
    end
end
assignin('base','index_lookup',index_lookup)


% --------------------------------------------------------
% Below are some utilities for building sparse matrices.
% --------------------------------------------------------

    function resetSparseCreator()
        sparseCreatorIndex=1;
        sparseCreator_i=zeros(estimated_nnz,1);
        sparseCreator_j=zeros(estimated_nnz,1);
        sparseCreator_s=zeros(estimated_nnz,1);
    end

    function addToSparse(i,j,s)
        n=numel(i);
        if n ~= numel(j)
            error('Error A');
        end
        if n ~= numel(s)
            error('Error B');
        end
        if any(i<1)
            error('Error Q: i<1');
        end
        if any(j<1)
            error('Error Q: j<1');
        end
        sparseCreator_i(sparseCreatorIndex:(sparseCreatorIndex+n-1)) = i;
        sparseCreator_j(sparseCreatorIndex:(sparseCreatorIndex+n-1)) = j;
        sparseCreator_s(sparseCreatorIndex:(sparseCreatorIndex+n-1)) = s;
        sparseCreatorIndex = sparseCreatorIndex+n;
        if sparseCreatorIndex > estimated_nnz
            fprintf('Error! estimated_nnz is too small.\n')
        end
    end

    function addSparseBlock(rowIndices, colIndices, block)
        s=size(block);
        if (s(1) ~= numel(rowIndices)) || (s(2) ~= numel(colIndices))
            s
            size(rowIndices)
            size(colIndices)
            error('Error in addSparseBlock!')
        end
        [rows, cols, values] = find(block);
        addToSparse(rowIndices(rows),colIndices(cols),values)
    end

    function sparseMatrix = createSparse()
        %fprintf('estimated nnz: %d   Actual value required: %d\n',estimated_nnz_original, sparseCreatorIndex)
        sparseMatrix = sparse(sparseCreator_i(1:(sparseCreatorIndex-1)), sparseCreator_j(1:(sparseCreatorIndex-1)), sparseCreator_s(1:(sparseCreatorIndex-1)), matrixSize, matrixSize);
        resetSparseCreator()
    end


end
