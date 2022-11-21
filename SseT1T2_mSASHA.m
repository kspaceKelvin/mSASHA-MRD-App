function sse = SseT1T2_mSASHA(A, aTS, aTE, timeToCenter, y)
% SseT1T2_mSASHA  Cost function for mSASHA 3-parameter model of T1/T2 for fminsearch
% 
% Syntax:
%  sse = SseT1T2_mSASHA(A, aTS, aTE, timeToCenter, y)
%
% Description:
%  Inputs:
%   A                - 1d array of fit parameters: [T1 T2 scale]
%   aTS              - saturation recovery time (does NOT include timeToCenter)
%   aTE              - T2 preparation time
%   timeToCenter     - time between T2p and center k-space
%   y                - data at each aTS/TE time (same size as aTS and aTE)
%  Outputs:
%   sse              - sum squared error between model (with A parameters) and data (y)
%
% Revision: 1.0.1  Date: 8 November 2022

% Simplify by calculating common exponentials
E1 = exp(-aTS          / A(1));
E2 = exp(-aTE          / A(2));
Ed = exp(-timeToCenter / A(1));

yFit = A(3) * (1 - Ed*(1 - E2 + E1.*E2) );
sse = sum((yFit - y).^2);