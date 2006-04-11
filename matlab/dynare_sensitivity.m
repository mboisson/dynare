function x0=dynare_sensitivity()
% copyright Marco Ratto 2006

global M_ options_ oo_ bayestopt_

fname_ = M_.fname;
lgy_ = M_.endo_names;
x0=[];

options_ = set_default_option(options_,'opt_gsa',1);
options_gsa_ = options_.opt_gsa;

% map stability
options_gsa_ = set_default_option(options_gsa_,'stab',1);
options_gsa_ = set_default_option(options_gsa_,'redform',0);
options_gsa_ = set_default_option(options_gsa_,'pprior',1);
options_gsa_ = set_default_option(options_gsa_,'ppost',0);
options_gsa_ = set_default_option(options_gsa_,'ilptau',1);
options_gsa_ = set_default_option(options_gsa_,'Nsam',2048);
options_gsa_ = set_default_option(options_gsa_,'load_stab',0);
options_gsa_ = set_default_option(options_gsa_,'alpha2_stab',0.3);
options_gsa_ = set_default_option(options_gsa_,'load_mh',0);

if options_gsa_.stab & ~options_gsa_.load_mh,
  x0 = stab_map_(options_gsa_.Nsam, options_gsa_.load_stab, options_gsa_.alpha2_stab, ...
    options_gsa_.redform, options_gsa_.pprior, options_gsa_.ilptau);
end

% reduced form
% redform_map(namendo, namlagendo, namexo, icomp, pprior, ilog, threshold)
options_gsa_ = set_default_option(options_gsa_,'load_redform',0);
options_gsa_ = set_default_option(options_gsa_,'logtrans_redform',0);
options_gsa_ = set_default_option(options_gsa_,'threshold_redform',[]);
options_gsa_ = set_default_option(options_gsa_,'namendo',[]);
options_gsa_ = set_default_option(options_gsa_,'namlagendo',[]);
options_gsa_ = set_default_option(options_gsa_,'namexo',[]);

if options_gsa_.redform & ~isempty(options_gsa_.namendo) & ~options_gsa_.load_mh,
  redform_map(options_gsa_.namendo, options_gsa_.namlagendo, options_gsa_.namexo, ...
    options_gsa_.load_redform, options_gsa_.pprior, options_gsa_.logtrans_redform, options_gsa_.threshold_redform);
end
% RMSE mapping
% function [rmse_MC, ixx] = filt_mc_(vvarvecm, loadSA, pfilt, alpha, alpha2)
options_gsa_ = set_default_option(options_gsa_,'rmse',0);
options_gsa_ = set_default_option(options_gsa_,'var_rmse',options_.varobs);
options_gsa_ = set_default_option(options_gsa_,'load_rmse',0);
options_gsa_ = set_default_option(options_gsa_,'pfilt_rmse',0.1);
options_gsa_ = set_default_option(options_gsa_,'alpha_rmse',0.002);
options_gsa_ = set_default_option(options_gsa_,'alpha2_rmse',0.5);
options_.opt_gsa = options_gsa_;
if options_gsa_.rmse,
  if options_gsa_.pprior
    a=load([fname_,'_prior']);
  else
    a=load([fname_,'_mc']);
  end
  if ~isfield(a,'stock_filter'),
    dynare_MC([]);
    options_gsa_.load_rmse=0;
  end
  filt_mc_(options_gsa_.var_rmse, options_gsa_.load_rmse, options_gsa_.pfilt_rmse, ...
    options_gsa_.alpha_rmse, options_gsa_.alpha2_rmse);
end


options_gsa_ = set_default_option(options_gsa_,'glue',0);
if options_gsa_.glue,
  dr_ = oo_.dr;
  if options_gsa_.ppost
    load([fname_,'_post']);
    DirectoryName = CheckPath('metropolis');
  else
    if options_gsa_.pprior
      load([fname_,'_prior']);
    else
      load([fname_,'_mc']);
    end
  end
  nruns=size(x,1);
  gend = options_.nobs;
  rawdata = read_variables(options_.datafile,options_.varobs,[],options_.xls_sheet,options_.xls_range);
  rawdata = rawdata(options_.first_obs:options_.first_obs+gend-1,:);
  if options_.loglinear == 1
    rawdata = log(rawdata);
  end
  if options_.prefilter == 1
    data = transpose(rawdata-ones(gend,1)*bayestopt_.mean_varobs);
  else
    data = transpose(rawdata);
  end
  
  Obs.data = data;
  Obs.time = [1:gend];
  Obs.num  = gend;
  for j=1:size(options_.varobs,1)
    Obs.name{j} = deblank(options_.varobs(j,:));
    vj=deblank(options_.varobs(j,:));
    
    jxj = strmatch(vj,lgy_(dr_.order_var,:),'exact');
    js = strmatch(vj,lgy_,'exact');
    if ~options_gsa_.ppost
      y0=zeros(gend+1,nruns);
      nb = size(stock_filter,3);
      y0 = squeeze(stock_filter(:,jxj,:)) + ...
        kron(stock_ys(js,:),ones(size(stock_filter,1),1));
      Out(j).data = y0';
      Out(j).time = [1:size(y0,1)];
    else
      Out(j).data = jxj;
      Out(j).time = [pwd,'\',DirectoryName];
    end
    Out(j).name = vj;
    Out(j).ini  = 'yes';
    Lik(j).name = ['rmse_',vj];
    Lik(j).ini  = 'yes';
    Lik(j).isam = 1;
    Lik(j).data = rmse_MC(:,j)';
    
    if ~options_gsa_.ppost
      y0 = squeeze(stock_smooth(:,jxj,:)) + ...
        kron(stock_ys(js,:),ones(size(stock_smooth,1),1));
      Out1(j).name = vj;
      Out1(j).ini  = 'yes';
      Out1(j).time = [1:size(y0,1)];
      Out1(j).data = y0';
    else
      Out1=Out;
    end
    ismoo(j)=jxj;
    
  end
  jsmoo = size(options_.varobs,1);
  for j=1:M_.endo_nbr,
    if ~ismember(j,ismoo),
      jsmoo=jsmoo+1;
      vj=deblank(M_.endo_names(dr_.order_var(j),:));
      if ~options_gsa_.ppost        
        y0 = squeeze(stock_smooth(:,j,:)) + ...
          kron(stock_ys(j,:),ones(size(stock_smooth,1),1));
        Out1(jsmoo).time = [1:size(y0,1)];
        Out1(jsmoo).data = y0';
      else
        Out1(jsmoo).data = j;
        Out1(jsmoo).time = [pwd,'\',DirectoryName];
      end
      Out1(jsmoo).name = vj;
      Out1(jsmoo).ini  = 'yes';
    end
  end
  tit(M_.exo_names_orig_ord,:) = M_.exo_names;
  for j=1:M_.exo_nbr,
      Exo(j).name = deblank(tit(j,:));    
  end
  if ~options_gsa_.ppost
    Lik(size(options_.varobs,1)+1).name = 'logpo';
    Lik(size(options_.varobs,1)+1).ini  = 'yes';
    Lik(size(options_.varobs,1)+1).isam = 1;
    Lik(size(options_.varobs,1)+1).data = -logpo2;
  end
  Sam.name = bayestopt_.name;
  Sam.dim  = [size(x) 0];
  Sam.data = [x];
  
  Rem.id = 'Original';
  Rem.ind= [1:size(x,1)];
  
  if options_gsa_.ppost
    Info.dynare=M_.fname;
    Out=Out1;
    save([fname_,'_post_glue'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem','Info', 'Exo')
    %save([fname_,'_post_glue_smooth'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem','Info')
    
  else
    if options_gsa_.pprior
      save([fname_,'_prior_glue'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem')
      Out=Out1;
      save([fname_,'_prior_glue_smooth'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem')
    else
      save([fname_,'_mc_glue'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem')
      Out=Out1;
      save([fname_,'_mc_glue_smooth'], 'Out', 'Sam', 'Lik', 'Obs', 'Rem')
    end
  end
  
end
