function [T1, T2, A, iter] = CalcT1T2(aTS, aTE, timeToCenter, data, technique, solver, startT1, startT2, flip)
% CalcT1T2  Calculate joint T1/T2 from data with various techniques
% 
% Syntax:
%  [T1, T2, A, iter] = CalcT1T2(aTS, aTE, data, timeToCenter, technique, startT1, startT2)
%
% Description:
%  Inputs:
%   aTS              - saturation recovery time (does NOT include timeToCenter)
%   aTE              - T2 preparation time
%   timeToCenter     - time between T2p and center k-space
%   data             - data at each aTS/TE time (same size as aTS and aTE)
%   technique        - 'mSASHA',      a 3-parameter model for mSASHA
%                    - 'mSASHA_ssfp', a 3-parameter model for mSASHA with T2 effects during recovery
%                      '4p',          a 4-parameter model that assumes imaging effect is an fitted offset
%                      '3p',          a naive 3-parameter model that assumes NO effect from imaging
%   solver           - 'levmar',      mex based Levenberg-Marquardt solver
%                    - 'fminsearch'   MATLAB native non-linear solver
%   startT1, startT2 - starting value for fitting (not provided, empty, or NaN to guess)
%  Outputs:
%   T1               - T1 value
%   T2               - T2 value
%   A                - 1d array: [T1 T2 scale]        for mSASHA and 3p models
%                                [T1 T2 scale offset] for 4p model
%   iter             - number of iterations during fitting (only for levmar)
%
% Revision: 1.0.1  Date: 8 November 2022

    %% Pre-flight
    T1            = nan;
    T2            = nan;
    A             = nan(1,4);
    iter          = nan;

    if all(data == 0) || all(isnan(data))
        return
    end

    % Remove data with NaNs
    indGood = find(~isnan(aTS) & ~isnan(aTE) & ~isnan(data));
    aTS     = aTS( indGood);
    aTE     = aTE( indGood);
    data    = data(indGood);

    % Set default solver
    if ~exist('solver', 'var')
        solver = 'fminsearch';
    end


    % Mex function requires doubles
    if ~isa(aTE, 'double')
        aTE = double(aTE);
    end

    if ~isa(data, 'double')
        data = double(data);
    end

    %% Initial guesses
    % ----- T1 -------------------------------------------------------------------
    if ~exist('startT1', 'var') || isempty(startT1) || isnan(startT1)
        % Assume that we will have some images without any T2p
        % 10,000 ms is a historical flag for non-sat
        sortData = sort(data( (aTS ~= 1e5) & (aTE == 0) ));
        indTest  = find(data == sortData(round(numel(sortData)/2)),1);
        startT1 = -(aTS(indTest)+timeToCenter)/log(1-data(indTest)/max(data));
        if isnan(startT1) || ~isreal(startT1)
            startT1 = 1000;  % Somewhat random intermediate starting value
        end
    end

    % ----- T2 -------------------------------------------------------------------
    if ~exist('startT2', 'var') || isempty(startT2) || isnan(startT2)
        % See if we can find values with TS > 1000, we will assume to be "less" T1 weighted
        indsGood = find(aTS > 1000);
        
        % TODO: Look for values that have the same TS but different TE
        if (numel(indsGood) < 2)
            startT2 = 100;
        else
            indMin = find((aTE == min(aTE)) & (aTS ~= min(aTS)), 1);
            indMax = find(aTE == max(aTE),1);
            % startT2 = -diff(aTE([indMin indMax]))/log(data(indMax)/data(indMin));
            % This (poorly) takes into account the T1 recovery during the timeToCenter phase
            startT2 = -diff(aTE([indMin indMax]))/log(data(indMax)/data(indMin)*exp(-timeToCenter/startT1));
            
            if ~isreal(startT2)
                startT2 = 100; % Somewhat random intermediate starting value
            end
        end
    end

    % ----- Others ---------------------------------------------------------------
    startScale  = max(data);
    startOffset = 0.2;

    %% Actual call to solvers
    if strcmp(solver, 'fminsearch')
        switch technique
            case {'mSASHA'}
                A  = fminsearch(@(x) SseT1T2_mSASHA(x, aTS, aTE, timeToCenter, data), [startT1 startT2 startScale],             struct('Display', 'off'));
            case {'4p'}
                A  = fminsearch(@(x) SseT1T2_4p(    x, aTS, aTE,               data), [startT1 startT2 startScale startOffset], struct('Display', 'off'));
        end
        T1 = A(1);
        T2 = A(2);
    else
        maxIter = 100; % Max iterations for LM
        options = []; % Minimization parameters (empty for default)

        switch technique
            case {'mSASHA'}
                [iter, A] = levmar('lmJointT1T2SashaVFA', 'lmJointT1T2SashaVFAJac', [startT1 startT2 startScale],             data, maxIter, options, aTS, aTE, timeToCenter);
            case {'4p'}
                [iter, A] = levmar('lmJointT1T2_4p',      'lmJointT1T2_4pJac',      [startT1 startT2 startScale startOffset], data, maxIter, options, aTS, aTE);
        end
        T1 = A(1);
        T2 = A(2);
    end
end