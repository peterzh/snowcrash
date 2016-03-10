classdef Q
    properties (Access=public)
        expRef;
        data;
        N;
    end
    
    properties (Access=private)
        guess_bpt;
    end
    
    methods
        function obj = Q(expRefs)
            obj.data=struct;
            
            obj.expRef = cell(length(expRefs),1);
            for b = 1:length(expRefs)
                obj.expRef{b} = expRefs{b};
                block = dat.loadBlock(expRefs{b});
                trials = block.trial;
                d = struct;
                
                for t=1:block.numCompletedTrials
                    d.stimulus(t,:) = trials(t).condition.visCueContrast';
                    d.action(t,1) = trials(t).responseMadeID';
                    d.repeatNum(t,1) = trials(t).condition.repeatNum;
                    d.reward(t,1) = trials(t).feedbackType==1;
                    d.session(t,1) = b;
                    
                    try
                        d.DA(t,1) = trials(t).condition.rewardVolume(2)>0 & trials(t).feedbackType==1;
                    catch
                        d.DA(t,1)= nan;
                    end
                end
                obj.data = addstruct(obj.data,d);
            end
            
            if max(obj.data.action) == 3
                error('Not implemented for 3 choice task');
            end
            
            if any(isnan(obj.data.DA))
                warning('No dopamine in these blocks. Setting to zero DA');
                expRefs(unique(obj.data.session(isnan(obj.data.DA))))
            end
            badIdx = isnan(obj.data.DA);
            obj.data.DA(badIdx)=0;
            %             obj.data = getrow(obj.data,~badIdx);
            
            obj.N = ones(length(obj.data.action),1)*0.5;
            
            tab = tabulate(obj.data.action);
            tab = tab(:,3)/100;
            obj.guess_bpt=sum(tab.*log2(tab));
        end
        
        function obj = fit(obj)
            figure; %to prevent plotting over any old plots
            options = optiset('solver','NOMAD','display','final');
            Opt = opti('fun',@obj.objective,...
                'bounds',[0 0 0],[1 1 1],...
                'x0',[0.5 0.5 0.5],'options',options);
            [p_est,~,exitflag,~] = Opt.solve;
            %             p_est = fmincon(@obj.objective,[0.1 1 1],[],[],[],[],[0 0 0],[1 100 100]);
            
            alpha = [p_est(1) 0; 0 p_est(2)];
%             beta = p_est(3);
            beta = 1;
            gamma = p_est(3);
            
            obj.plot(alpha,beta,gamma);
            
        end
        
        function plot(obj,alpha,beta,gamma)
            p.alpha = alpha;
            p.beta = beta;
            p.gamma = gamma;
            
            w_init = obj.fitWINIT(p.alpha,p.gamma);
            p.sL_init = w_init(1);
            p.bL_init = w_init(2);
            p.sR_init = w_init(3);
            p.bR_init = w_init(4);
            w = obj.calculateWT(p);
            ph = obj.calculatePHAT(w,p.beta);
            bpt = obj.calculateLOGLIK(ph)/length(obj.data.action);
            
            figure;
            h(1)=subplot(4,1,1);
            plot([w{1};w{2}]','LineWidth',2);
            legend({'sL','bL','sR','bR'});
            grid on;
            
            title(['\alphaS: ' num2str(p.alpha(1,1)) ,...
                   ' \alphaB: ' num2str(p.alpha(2,2)) ,...
                   ' \beta: ' num2str(p.beta) ,...
                   ' \gamma: ' num2str(p.gamma)])
            xt = obj.x;
            numTrials = length(obj.data.action);
            
            for n = 1:numTrials
                QL(n) = w{1}(:,n)'*xt{1}(:,n);
                QR(n) = w{2}(:,n)'*xt{2}(:,n);
            end
            
            h(2)=subplot(4,1,2);
            trialDot = obj.data.action-1;
            trialDot((diff(obj.data.stimulus,[],2))==0)=nan;
%             trialDot(obj.data.reward==0)=nan;
%             trialDot(obj.data.DA==0)=nan;
            plot(trialDot,'k.','markersize',10);

            hold on;
            plot((diff(obj.data.stimulus,[],2)>0),'o')
            trialDot(obj.data.DA==0)=nan;
            plot(trialDot,'.','markersize',10);
            hold off;
            ylim([-1 2]);
            set(gca,'box','off','YTick',{});
            trialAx=gca;
            legend('action','target');

            h(3)=subplot(4,1,3);
            ax=plot(QR-QL);
%             ax=plotyy(1:numTrials,QR-QL,1:numTrials,trialDot);            
%             set(get(ax(2),'children'),'linestyle','none','marker','.','markersize',5)
            ylabel('QR - QL');
            line([0 numTrials],[ 0 0]);
%             ax.YTickLabel={'L+DA','R+DA'}; ax.YTick=[0 1];
%             ax.YLim=[-0.1 1.1];
            xlabel('Trial number');

            title(['loglik_{model} - loglik_{guess} = ' num2str(bpt - obj.guess_bpt)]);
            
            linkaxes(h,'x');
            xlim([0 length(obj.data.action)]);
            subplot(4,3,10);
            plot(QL(obj.data.action==1),QR(obj.data.action==1),'bo',...
                QL(obj.data.action==2),QR(obj.data.action==2),'ro')
            %             scatter(QL,QR,[],obj.data.action,'filled'); colorbar; caxis([1 2]);
            legend({'Chose L','Chose R'});
            axis square;
            hold on;
            ezplot('y=x',[min(QL) max(QL)]);
            xlabel('QL');ylabel('QR');
            hold off;
            
            %             try
            %             exitFlag = 0;
            %             xDiv = [];
            PADDING = 50;
            %             while exitFlag == 0
            %                 [x,~,button] = ginput(1);
            %                 if button == 3 || length(xDiv) > 10
            %                     exitFlag=1;
            %                 else
            %                     xDiv = [xDiv;x];
            %                     line([x x],[-1 2]);
            %                     line([x x]-PADDING,[0 1]);
            %                     line([x x]+PADDING,[0 1]);
            %                     line([x-PADDING x+PADDING],[0.5 0.5]);
            %                 end
            %             end
            %             xDiv = round(sort(xDiv));
            xDiv = round([0.25 0.5 0.75]*numTrials);
            
            pLdat = cell(length(xDiv),1);
            pLdatErr = cell(length(xDiv),1);
            
            pL = cell(length(xDiv),1);
            for d = 1:length(xDiv)
                %                  trials=round([numTrials*divisions(d,1)+1 numTrials*divisions(d,2)]);
                trials = [xDiv(d)-PADDING xDiv(d)+PADDING];
                stim = obj.data.stimulus(trials(1):trials(2),:);
                act = obj.data.action(trials(1):trials(2));
                nPower = mean(obj.N(trials(1):trials(2)));
                
                c1d=diff(stim,[],2);
                [uniqueC,~,IC] = unique(c1d);
                for c = 1:length(uniqueC)
                    choices=act(IC==c);
                    %                         pLdat{d}(c,1) = sum(choices==1)/length(choices);
                    [p,ci] = binofit(sum(choices==1),length(choices));
                    pLdat{d}(c,1)=p;
                    pLdatErr{d}(c,:)=[p-ci(1) ci(2)-p];
                end
                
                midTrial = xDiv(d);
                contrasts = linspace(0,1,200);
                ql = w{1}(1,midTrial)*(contrasts.^nPower) + w{1}(2,midTrial);
                qr = w{2}(1,midTrial)*(contrasts.^nPower) + w{2}(2,midTrial);
                dQ=beta*[ql-w{2}(2,midTrial), w{1}(2,midTrial)-qr];
                pL{d} = [exp(dQ)./(1+exp(dQ))]';
                

                line([xDiv(d) xDiv(d)],[-0.5 1.5],'Parent',trialAx);
%                 line([xDiv(d) xDiv(d)]-PADDING,[0 1],'Parent',trialAx);
%                 line([xDiv(d) xDiv(d)]+PADDING,[0 1],'Parent',trialAx);
%                 line([xDiv(d)-PADDING xDiv(d)+PADDING],[0.5 0.5],'Parent',trialAx);

            end
            
            M = [[-contrasts contrasts]' cell2mat(pL')];
            M = sortrows(M,1);
            subplot(4,3,[11 12]); %psychometric curves
            plot(M(:,1),M(:,2:end),'-');
            hold on;
            set(gca, 'ColorOrderIndex', 1);
%             plot(uniqueC,cell2mat(pLdat'),'s');
            for d = 1:length(xDiv)
                ax=errorbar(uniqueC,pLdat{d},pLdatErr{d}(:,1),pLdatErr{d}(:,2));
                ax.LineStyle='none';
                ax.Marker='s';
                uniqueC = uniqueC + 0.004;
            end
            hold off;
            legend(cellfun(@(c)num2str(c),num2cell([xDiv]),'uni',0),'location','BestOutside')
            %             legend({'first half model','second half model','first half data','second half data'});
            ylabel('pL'); title('psych from w compared to data');
            xlim([min(c1d)-0.1 max(c1d)+0.1]);
            
            %             catch
            %             end
        end
        
        function obj = fitContrastFcn(obj)
            for b = 1:max(obj.data.session)
                g = GLM(obj.expRef{b}).setModel('C^N-subset-2AFC').fit;
%                 g.plotFit; keyboard;
                obj.N(obj.data.session==b,1) = g.parameterFits(end);
            end
        end
    end
    
    methods (Access=public)
        function negLogLik = objective(obj,p_vec)
            p.alpha = [p_vec(1) 0; 0 p_vec(2)];
%             p.beta = p_vec(3);
            p.gamma = p_vec(3);
            p.beta = 1;
            
            w_init = obj.fitWINIT(p.alpha,p.gamma);
            p.sL_init = w_init(1);
            p.bL_init = w_init(2);
            p.sR_init = w_init(3);
            p.bR_init = w_init(4);
            
            w = obj.calculateWT(p);
            
            ph = obj.calculatePHAT(w,p.beta);
            negLogLik = -obj.calculateLOGLIK(ph);
            plot([w{1}',w{2}']);
            bpt = -negLogLik/length(obj.data.action);
            title([num2str(bpt - obj.guess_bpt)]); 
            drawnow;

        end
        %
        function xt = x(obj)
            numTrials = length(obj.data.action);
            xt = {[(obj.data.stimulus(:,1).^obj.N)'; ones(1,numTrials)];
                [(obj.data.stimulus(:,2).^obj.N)'; ones(1,numTrials)]};
        end
        
        function [W_init] = fitWINIT(obj,alpha,gamma)
            numTrials = size(obj.data.action,1);
            rt = (1-gamma)*obj.data.reward + gamma*obj.data.DA;
            at = obj.data.action;
            xt = obj.x;
            
            Vt = {nan(2,numTrials),nan(2,numTrials)};
            Bt = {nan(2,2,numTrials),nan(2,2,numTrials)};
            
            Bt{1}(:,:,1) = eye(2);
            Bt{2}(:,:,1) = eye(2);
            Vt{1}(:,1) = [0;0];
            Vt{2}(:,1) = [0;0];
            
            offset=nan(numTrials,1);
            regressors=nan(numTrials,4);
            
            offset(1) = Vt{1}(:,1)'*xt{1}(:,1) - Vt{2}(:,1)'*xt{2}(:,1);
            regressors(1,:) = [xt{1}(:,1)'*Bt{1}(:,:,1) -xt{2}(:,1)'*Bt{2}(:,:,1)];
            
            for t = 2:numTrials
                prev.rt = rt(t-1);
                prev.at = at(t-1);
                
                if prev.at==1
                    prev.xt = xt{1}(:,t-1);
                    prev.nt = alpha*prev.rt*prev.xt;
                    prev.Mt = eye(2) - alpha*prev.xt*prev.xt';
                    
                    Vt{1}(:,t) = prev.nt + prev.Mt*Vt{1}(:,t-1);
                    Bt{1}(:,:,t) = prev.Mt*Bt{1}(:,:,t-1);
                    
                    Vt{2}(:,t) = Vt{2}(:,t-1);
                    Bt{2}(:,:,t) = Bt{2}(:,:,t-1);
                elseif prev.at==2
                    prev.xt = xt{2}(:,t-1);
                    prev.nt = alpha*prev.rt*prev.xt;
                    prev.Mt = eye(2) - alpha*prev.xt*prev.xt';
                    
                    Vt{2}(:,t) = prev.nt + prev.Mt*Vt{2}(:,t-1);
                    Bt{2}(:,:,t) = prev.Mt*Bt{2}(:,:,t-1);
                    
                    Vt{1}(:,t) = Vt{1}(:,t-1);
                    Bt{1}(:,:,t) = Bt{1}(:,:,t-1);
                end
                
                offset(t) = Vt{1}(:,t)'*xt{1}(:,t) - Vt{2}(:,t)'*xt{2}(:,t);
                regressors(t,:) = [xt{1}(:,t)'*Bt{1}(:,:,t), -xt{2}(:,t)'*Bt{2}(:,:,t)];
                
                
            end
            
            X = regressors;
            Y = obj.data.action;
            Y(Y==2)=0;
            g = fitglm(X,Y,'Distribution','binomial','intercept',false,'offset',offset);
            W_init = table2array(g.Coefficients(:,1));
            
        end
        %
        function wt = calculateWT(obj,p)
            numTrials = size(obj.data.action,1);
            wt = {nan(2,numTrials),nan(2,numTrials)};
            at = obj.data.action;
            wt{1}(:,1) = [p.sL_init; p.bL_init];
            wt{2}(:,1) = [p.sR_init; p.bR_init];
            
            xt = obj.x;
            
            
            for t = 2:numTrials
                prev.rt = (1-p.gamma)*obj.data.reward(t-1) + p.gamma*obj.data.DA(t-1);
                prev.at = at(t-1);
                
                if prev.at==1
                    prev.xt = xt{1}(:,t-1);
                    wt{1}(:,t) = wt{1}(:,t-1) + p.alpha*(prev.rt - prev.xt'*wt{1}(:,t-1))*prev.xt;
                    wt{2}(:,t) = wt{2}(:,t-1);
                elseif prev.at==2
                    prev.xt = xt{2}(:,t-1);
                    wt{2}(:,t) = wt{2}(:,t-1) + p.alpha*(prev.rt - prev.xt'*wt{2}(:,t-1))*prev.xt;
                    wt{1}(:,t) = wt{1}(:,t-1);
                end
                
            end
            
        end
        %
        function phat = calculatePHAT(obj,wt,beta)
            xt = obj.x;
            
            numTrials = length(obj.data.action);
            
            for n = 1:numTrials
                QL(n) = wt{1}(:,n)'*xt{1}(:,n);
                QR(n) = wt{2}(:,n)'*xt{2}(:,n);
            end
            
            Z = beta*(QL-QR);
            
            pL = exp(Z)./(1+exp(Z));
            pR = 1-pL;
            
            phat = [pL; pR];
            %             phat(phat==0)=0.0001;
        end
        
        function nloglik = calculateLOGLIK(obj,phat)
            
            if size(phat,1) > size(phat,2)
                phat = phat';
            end
            
            for t = 1:length(obj.data.action)
                r =  obj.data.action(t);
                p(t) = phat(r,t);
            end
            nloglik = sum(log2(p));
        end
    end
end