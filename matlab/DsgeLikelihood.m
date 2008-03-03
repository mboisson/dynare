function [fval,cost_flag,ys,trend_coeff,info] = DsgeLikelihood(xparam1,gend,data)

% function [fval,cost_flag,ys,trend_coeff,info] = DsgeLikelihood(xparam1,gend,data)
% Evaluates the posterior kernel of a dsge model. 
% 
% INPUTS 
%   xparam1:          vector of model parameters.
%   gend   :          scalar specifying the number of observations.
%   data   :          matrix of data
%  
% OUTPUTS 
%   fval        :     value of the posterior kernel at xparam1.
%   cost_flag   :     zero if the function returns a penalty, one otherwise.
%   ys          :     steady state of original endogenous variables
%   trend_coeff :
%   info        :     vector of informations about the penalty:
%                     41: one (many) parameter(s) do(es) not satisfied the lower bound
%                     42: one (many) parameter(s) do(es) not satisfied the upper bound
%               
% SPECIAL REQUIREMENTS
%   Adapted from mj_optmumlik.m
%  
% part of DYNARE, copyright Dynare Team (2004-2008)
% Gnu Public License.

  global bayestopt_ estim_params_ options_ trend_coeff_ M_ oo_ xparam1_test

  fval		= [];
  ys		= [];
  trend_coeff	= [];
  xparam1_test  = xparam1;
  cost_flag  	= 1;
  nobs 		= size(options_.varobs,1);
  %------------------------------------------------------------------------------
  % 1. Get the structural parameters & define penalties
  %------------------------------------------------------------------------------
  if options_.mode_compute ~= 1 & any(xparam1 < bayestopt_.lb)
    k = find(xparam1 < bayestopt_.lb);
    fval = bayestopt_.penalty+sum((bayestopt_.lb(k)-xparam1(k)).^2);
    cost_flag = 0;
    info = 41;
    return;
  end
  if options_.mode_compute ~= 1 & any(xparam1 > bayestopt_.ub)
    k = find(xparam1 > bayestopt_.ub);
    fval = bayestopt_.penalty+sum((xparam1(k)-bayestopt_.ub(k)).^2);
    cost_flag = 0;
    info = 42;
    return;
  end
  Q = M_.Sigma_e;
  H = M_.H;
  for i=1:estim_params_.nvx
    k =estim_params_.var_exo(i,1);
    Q(k,k) = xparam1(i)*xparam1(i);
  end
  offset = estim_params_.nvx;
  if estim_params_.nvn
    for i=1:estim_params_.nvn
      k = estim_params_.var_endo(i,1);
      H(k,k) = xparam1(i+offset)*xparam1(i+offset);
    end
    offset = offset+estim_params_.nvn;
  end	
  if estim_params_.ncx
    for i=1:estim_params_.ncx
      k1 =estim_params_.corrx(i,1);
      k2 =estim_params_.corrx(i,2);
      Q(k1,k2) = xparam1(i+offset)*sqrt(Q(k1,k1)*Q(k2,k2));
      Q(k2,k1) = Q(k1,k2);
    end
    [CholQ,testQ] = chol(Q);
    if testQ 	%% The variance-covariance matrix of the structural innovations is not definite positive.
		%% We have to compute the eigenvalues of this matrix in order to build the penalty.
		a = diag(eig(Q));
		k = find(a < 0);
		if k > 0
		  fval = bayestopt_.penalty+sum(-a(k));
		  cost_flag = 0;
		  info = 43;
		  return
		end
    end
    offset = offset+estim_params_.ncx;
  end
  if estim_params_.ncn 
    for i=1:estim_params_.ncn
      k1 = options_.lgyidx2varobs(estim_params_.corrn(i,1));
      k2 = options_.lgyidx2varobs(estim_params_.corrn(i,2));
      H(k1,k2) = xparam1(i+offset)*sqrt(H(k1,k1)*H(k2,k2));
      H(k2,k1) = H(k1,k2);
    end
    [CholH,testH] = chol(H);
    if testH
      a = diag(eig(H));
      k = find(a < 0);
      if k > 0
	fval = bayestopt_.penalty+sum(-a(k));
	cost_flag = 0;
	info = 44;
	return
      end
    end
    offset = offset+estim_params_.ncn;
  end
  if estim_params_.np > 0
      M_.params(estim_params_.param_vals(:,1)) = xparam1(offset+1:end);
  end
  % for i=1:estim_params_.np
  %  M_.params(estim_params_.param_vals(i,1)) = xparam1(i+offset);
  %end
  M_.Sigma_e = Q;
  M_.H = H;
  %------------------------------------------------------------------------------
  % 2. call model setup & reduction program
  %------------------------------------------------------------------------------
  [T,R,SteadyState,info] = dynare_resolve(bayestopt_.restrict_var_list,...
					  bayestopt_.restrict_columns,...
					  bayestopt_.restrict_aux);
  if info(1) == 1 | info(1) == 2 | info(1) == 5
    fval = bayestopt_.penalty+1;
    cost_flag = 0;
    return
  elseif info(1) == 3 | info(1) == 4 | info(1) == 20
    fval = bayestopt_.penalty+info(2)^2;
    cost_flag = 0;
    return
  end
  bayestopt_.mf = bayestopt_.mf1;
  if ~options_.noconstant
    if options_.loglinear == 1
      constant = log(SteadyState(bayestopt_.mfys));
    else
      constant = SteadyState(bayestopt_.mfys);
    end
  else
    constant = zeros(nobs,1);
  end
  if bayestopt_.with_trend == 1
    trend_coeff = zeros(nobs,1);
    t = options_.trend_coeffs;
    for i=1:length(t)
      if ~isempty(t{i})
	trend_coeff(i) = evalin('base',t{i});
      end
    end
    trend = repmat(constant,1,gend)+trend_coeff*[1:gend];
  else
    trend = repmat(constant,1,gend);
  end
  start = options_.presample+1;
  np    = size(T,1);
  mf    = bayestopt_.mf;
  %------------------------------------------------------------------------------
  % 3. Initial condition of the Kalman filter
  %------------------------------------------------------------------------------
  if options_.lik_init == 1		% Kalman filter
    Pstar = lyapunov_symm(T,R*Q*R');
    Pinf	= [];
  elseif options_.lik_init == 2	% Old Diffuse Kalman filter
    Pstar = 10*eye(np);
    Pinf	= [];
  elseif options_.lik_init == 3	% Diffuse Kalman filter
    if options_.kalman_algo < 4
      Pstar = zeros(np,np);
      ivs = bayestopt_.restrict_var_list_stationary;
      R1 = R(ivs,:);
      Pstar(ivs,ivs) = lyapunov_symm(T(ivs,ivs),R1*Q*R1');
      %    Pinf  = bayestopt_.Pinf;
      % by M. Ratto
      RR=T(:,bayestopt_.restrict_var_list_nonstationary);
      i=find(abs(RR)>1.e-10);
      R0=zeros(size(RR));
      R0(i)=sign(RR(i));
      Pinf=R0*R0';
      % by M. Ratto
    else
      [QT,ST] = schur(T);
      e1 = abs(ordeig(ST)) > 2-options_.qz_criterium;
      [QT,ST] = ordschur(QT,ST,e1);
      k = find(abs(ordeig(ST)) > 2-options_.qz_criterium);
      nk = length(k);
      nk1 = nk+1;
      Pinf = zeros(np,np);
      Pinf(1:nk,1:nk) = eye(nk);
      Pstar = zeros(np,np);
      B = QT'*R*Q*R'*QT;
      for i=np:-1:nk+2
	if ST(i,i-1) == 0
	  if i == np
	    c = zeros(np-nk,1);
	  else
	    c = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i,i+1:end)')+...
		ST(i,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i);
	  end
	  q = eye(i-nk)-ST(nk1:i,nk1:i)*ST(i,i);
	  Pstar(nk1:i,i) = q\(B(nk1:i,i)+c);
	  Pstar(i,nk1:i-1) = Pstar(nk1:i-1,i)';
	else
	  if i == np
	    c = zeros(np-nk,1);
	    c1 = zeros(np-nk,1);
	  else
	    c = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i,i+1:end)')+...
		ST(i,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i)+...
		ST(i,i-1)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i-1);
	    c1 = ST(nk1:i,:)*(Pstar(:,i+1:end)*ST(i-1,i+1:end)')+...
		 ST(i-1,i-1)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i-1)+...
		 ST(i-1,i)*ST(nk1:i,i+1:end)*Pstar(i+1:end,i);
	  end
	  q = [eye(i-nk)-ST(nk1:i,nk1:i)*ST(i,i) -ST(nk1:i,nk1:i)*ST(i,i-1);...
	       -ST(nk1:i,nk1:i)*ST(i-1,i) eye(i-nk)-ST(nk1:i,nk1:i)*ST(i-1,i-1)];
	  z =  q\[B(nk1:i,i)+c;B(nk1:i,i-1)+c1];
	  Pstar(nk1:i,i) = z(1:(i-nk));
	  Pstar(nk1:i,i-1) = z(i-nk+1:end);
	  Pstar(i,nk1:i-1) = Pstar(nk1:i-1,i)';
	  Pstar(i-1,nk1:i-2) = Pstar(nk1:i-2,i-1)';
	  i = i - 1;
	end
      end
      if i == nk+2
	c = ST(nk+1,:)*(Pstar(:,nk+2:end)*ST(nk1,nk+2:end)')+ST(nk1,nk1)*ST(nk1,nk+2:end)*Pstar(nk+2:end,nk1);
	Pstar(nk1,nk1)=(B(nk1,nk1)+c)/(1-ST(nk1,nk1)*ST(nk1,nk1));
      end
      
      Z = QT(mf,:);
      R1 = QT'*R;
    end
  end
  %------------------------------------------------------------------------------
  % 4. Likelihood evaluation
  %------------------------------------------------------------------------------
  if any(any(H ~= 0)) % should be replaced by a flag
    if options_.kalman_algo == 1
      LIK = DiffuseLikelihoodH1(T,R,Q,H,Pinf,Pstar,data,trend,start);
      if isinf(LIK) & ~estim_params_.ncn %% The univariate approach considered here doesn't 
					 %%	apply when H has some off-diagonal elements.
        LIK = DiffuseLikelihoodH3(T,R,Q,H,Pinf,Pstar,data,trend,start);
      elseif isinf(LIK) & estim_params_.ncn
	LIK = DiffuseLikelihoodH3corr(T,R,Q,H,Pinf,Pstar,data,trend,start);
      end
    elseif options_.kalman_algo == 3
      if ~estim_params_.ncn %% The univariate approach considered here doesn't 
			    %%	apply when H has some off-diagonal elements.
        LIK = DiffuseLikelihoodH3(T,R,Q,H,Pinf,Pstar,data,trend,start);
      else
	LIK = DiffuseLikelihoodH3corr(T,R,Q,H,Pinf,Pstar,data,trend,start);
      end	
    end	  
  else
    if options_.kalman_algo == 1
       %nv = size(bayestopt_.Z,1);
       %LIK = kalman_filter(bayestopt_.Z,zeros(nv,nv),T,R,Q,data,zeros(size(T,1),1),Pstar,'u');
      LIK = DiffuseLikelihood1(T,R,Q,Pinf,Pstar,data,trend,start);
      % LIK = diffuse_likelihood1(T,R,Q,Pinf,Pstar,data-trend,start);
      %if abs(LIK1-LIK)>0.0000000001
      %  disp(['LIK1 and LIK are not equal! ' num2str(abs(LIK1-LIK))])
      %end
      if isinf(LIK)
	LIK = DiffuseLikelihood3(T,R,Q,Pinf,Pstar,data,trend,start);
      end
    elseif options_.kalman_algo == 3
      LIK = DiffuseLikelihood3(T,R,Q,Pinf,Pstar,data,trend,start);
    elseif options_.kalman_algo == 4
      data1 = data - trend;
      LIK = DiffuseLikelihood1_Z(ST,Z,R1,Q,Pinf,Pstar,data1,start);
      if isinf(LIK)
	LIK = DiffuseLikelihood3_Z(ST,Z,R1,Q,Pinf,Pstar,data1,start);
      end
    elseif options_.kalman_algo == 5
      data1 = data - trend;
      LIK = DiffuseLikelihood3_Z(ST,Z,R1,Q,Pinf,Pstar,data1,start);
    end 	
  end
  if imag(LIK) ~= 0
    likelihood = bayestopt_.penalty;
  else
    likelihood = LIK;
  end
  % ------------------------------------------------------------------------------
  % Adds prior if necessary
  % ------------------------------------------------------------------------------
  lnprior = priordens(xparam1,bayestopt_.pshape,bayestopt_.p1,bayestopt_.p2,bayestopt_.p3,bayestopt_.p4);
  fval    = (likelihood-lnprior);