function sse = SseT1T2_4p(A, aTS, aTE, y)
% SseT1T2_4p  Cost function for 4-parameter model of joint T1/T2 for fminsearch
% 
% Syntax:
%  sse = SseT1T2_4p(A, aTS, aTE, y)
%
% Description:
%  Inputs:
%   A                - 1d array of fit parameters: [T1 T2 scale offset]
%   aTS              - saturation recovery time (DOES include timeToCenter)
%   aTE              - T2 preparation time
%   y                - data at each aTS/TE time (same size as aTS and aTE)
%  Outputs:
%   sse              - sum squared error between model (with A parameters) and data (y)
%
% Revision: 1.0.1  Date: 8 November 2022

% Simplify by calculating common exponentials
E1 = exp(-aTS          / A(1));
E2 = exp(-aTE          / A(2));

yFit = A(3) * ((1 - E1).*E2 + A(4));

sse = sum((yFit - y).^2);