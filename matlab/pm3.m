function pm3(n1,n2,ifil,B,tit1,tit2,tit3,tit_tex,names1,names2,name3,DirectoryName,var_type)

% Copyright (C) 2007-2009 Dynare Team
%
% This file is part of Dynare.
%
% Dynare is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% Dynare is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with Dynare.  If not, see <http://www.gnu.org/licenses/>.

  global options_ M_ oo_

  nn = 3;
  MaxNumberOfPlotsPerFigure = nn^2; % must be square
  varlist = names2;
  if isempty(varlist)
    varlist = names1;
    SelecVariables = (1:M_.endo_nbr)';
    nvar = M_.endo_nbr;
  else
    nvar = size(varlist,1);
    SelecVariables = [];
    for i=1:nvar
      if ~isempty(strmatch(varlist(i,:),names1,'exact'))
	SelecVariables = [SelecVariables;strmatch(varlist(i,:),names1,'exact')];
      end
    end
  end
  if options_.TeX
      % needs to be fixed
    varlist_TeX = [];
    for i=1:nvar
      varlist_TeX = strvcat(varlist_TeX,M_.endo_names_tex(SelecVariables(i),:));
    end
  end
  Mean = zeros(n2,nvar);
  Median = zeros(n2,nvar);
  Std = zeros(n2,nvar);
  Distrib = zeros(9,n2,nvar);
  HPD = zeros(2,n2,nvar);
  fprintf(['MH: ' tit1 '\n']);
  stock1 = zeros(n1,n2,B);
  k = 0;
  for file = 1:ifil
    load([DirectoryName '/' M_.fname var_type int2str(file)]);
    if size(size(stock),2) == 4
        stock = squeeze(stock(1,:,1:n2,:));
    end
    k = k(end)+(1:size(stock,3));
    stock1(:,:,k) = stock;
  end
  clear stock
  tmp =zeros(B,1);
  for i = 1:nvar
    for j = 1:n2
      [Mean(j,i),Median(j,i),Var(j,i),HPD(:,j,i),Distrib(:,j,i)] = ...
          posterior_moments(squeeze(stock1(SelecVariables(i),j,:)),0,options_.mh_conf_sig);
    end
  end
  clear stock1
  for i = 1:nvar
    name = deblank(names1(SelecVariables(i),:));
    eval(['oo_.' name3 '.Mean.' name ' = Mean(:,i);']);
    eval(['oo_.' name3 '.Median.' name ' = Median(:,i);']);
    eval(['oo_.' name3 '.Var.' name ' = Var(:,i);']);
    eval(['oo_.' name3 '.Distribution.' name ' = Distrib(:,:,i);']);
    eval(['oo_.' name3 '.HPDinf.' name ' = HPD(1,:,i);']);
    eval(['oo_.' name3 '.HPDsup.' name ' = HPD(2,:,i);']);
  end
  %%
  %% 	Finally I build the plots.
  %%
  if options_.TeX
    fidTeX = fopen([M_.dname '/Output/' M_.fname '_' name3 '.TeX'],'w');
    fprintf(fidTeX,'%% TeX eps-loader file generated by Dynare.\n');
    fprintf(fidTeX,['%% ' datestr(now,0) '\n']);
    fprintf(fidTeX,' \n');
  end
  %%
  figunumber = 0;
  subplotnum = 0;
  hh = figure('Name',[tit1 ' ' int2str(figunumber+1)]);
  for i=1:nvar
    NAMES = [];
    if options_.TeX 
      TEXNAMES = []; 
    end
    if max(abs(Mean(:,i))) > 10^(-6)
      subplotnum = subplotnum+1;
      set(0,'CurrentFigure',hh)
      subplot(nn,nn,subplotnum);
      plot([1 n2],[0 0],'-r','linewidth',0.5);
      hold on
      for k = 1:9
	plot(1:n2,squeeze(Distrib(k,:,i)),'-g','linewidth',0.5)
      end
      plot(1:n2,Mean(:,i),'-k','linewidth',1)
      xlim([1 n2]);
      hold off
      name = deblank(varlist(i,:));
      NAMES = strvcat(NAMES,name);
      if options_.TeX
	texname = deblank(varlist_TeX(i,:));
	TEXNAMES = strvcat(TEXNAMES,['$' texname '$']);
      end
      title(name,'Interpreter','none')
    end
    if subplotnum == MaxNumberOfPlotsPerFigure | i == nvar  
      eval(['print -depsc2 ' M_.dname '/Output/'  M_.fname '_' name3 '_' deblank(tit3(i,:)) '.eps' ]);
      if ~exist('OCTAVE_VERSION')
          eval(['print -dpdf ' M_.dname '/Output/' M_.fname  '_' name3 '_' deblank(tit3(i,:))]);
          saveas(hh,[M_.dname '/Output/' M_.fname '_' name3 '_' deblank(tit3(i,:)) '.fig']);
      end
      if options_.nograph, close(hh), end
      if options_.TeX
	fprintf(fidTeX,'\\begin{figure}[H]\n');
	for jj = 1:size(TEXNAMES,1)
	  fprintf(fidTeX,['\\psfrag{%s}[1][][0.5][0]{%s}\n'],deblank(NAMES(jj,:)),deblank(TEXNAMES(jj,:)));
	end    
	fprintf(fidTeX,'\\centering \n');
	fprintf(fidTeX,['\\includegraphics[scale=0.5]{%s_' name3 '_%s}\n'],M_.fname,deblank(tit3(i,:)));
	if options_.relative_irf
	  fprintf(fidTeX,['\\caption{' caption '.}']);
	else
	  fprintf(fidTeX,['\\caption{' caption '.}']);
	end
	fprintf(fidTeX,'\\label{Fig:%s:%s}\n',name3,deblank(tit3(i,:)));
	fprintf(fidTeX,'\\end{figure}\n');
	fprintf(fidTeX,' \n');
      end
      subplotnum = 0;
      figunumber = figunumber+1;
      if (i ~= nvar)
        hh = figure('Name',[name3 ' ' int2str(figunumber+1)]);
      end
    end

  end
  %%
  if options_.TeX
    fprintf(fidTeX,'%% End of TeX file.\n');
    fclose(fidTeX);
  end
  fprintf(['MH: ' tit1 ', done!\n']);
