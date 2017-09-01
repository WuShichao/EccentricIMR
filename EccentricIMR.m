
BeginPackage["EccentricIMR`", 
  {"EccentricPN`", "CircularMergerModel`"}];

EccentricIMRWaveform;
EccentricPNSolution;

Begin["`Private`"];

$maxPNX = 0.11;
$blendStartX = 0.12;
$circularisationTime = -30;

etaOfq[q_] :=
 q/(1 + q)^2;

pnSolnToAssoc[soln_List, q_] :=
    Join[Association@Table[ToString[var[[1]]] -> var[[2]], {var,soln}],Association["q"->q]];

EccentricPNSolution[params_Association, {t1_, t2_}] :=
  Module[{pnSolnRules, dt=1.0},
    pnSolnRules = EccentricSoln[xeModel, N@etaOfq[params["q"]],
      {N@params["x0"], N@params["e0"], N@params["l0"], N@params["phi0"]},
      N@params["t0"], N/@{t1, t2, dt}];
    pnSolnToAssoc[pnSolnRules, params["q"]]];

timeToMergerFunction[] :=
  Function[{qq, ee, 
  ll}, 391.1958112997977 + 
  3.133913420161147*ee - 
  2492.9450481148215*ee^2 + 
  2.772121863176699*qq - 
  17.91996245212786*ee*qq + 
  8.118416384384208*qq^2 + 
  76.49439836997179*ee*
   Cos[63.45850634016995 - ll] + 
  1.154966280839567*qq*
   Cos[1.0227481831786127 + ll]];

timeOfPeak[h_List] :=
  Module[{d, tMax, fMax, l, maxFind, fn, t1, t2, t, tMax2},
    a = Transpose[{h[[All,1]], Abs[h[[All,2]]]}];
    {t1, t2} = {a[[1,1]], a[[-1,1]]};
    fMax = -Infinity;
    maxFind[{time_, f_}] :=
    If[f > fMax, fMax = f; tMax = time];
    Scan[maxFind, a];
    fn = Interpolation[a,InterpolationOrder->8];
    tMax2 = 
    t /. FindMaximum[{fn[t], {t > tMax - 50, t < tMax + 50}}, {t, 
      tMax}][[2]];
    tMax2];

shifted[d_List, delta_?NumericQ] :=
  Transpose[{d[[All,1]] + delta, d[[All,2]]}];

unwrapPhaseVectorInt := unwrapPhaseVectorInt = Compile[{{data, _Real, 1}},
 Module[{diffs, corr, cumulcorr},
  (* Compute the differences between successive points *)
  diffs = Differences[data];

  (* Add a jump of 2 Pi each time the difference is between
     successive points is greater than Pi *)
  corr = Round[diffs/(2 Pi)];
  cumulcorr = (- 2 Pi) Accumulate[corr];

  (* Add the corrections to the original data *)
  Join[data[[{1}]], data[[2 ;; -1]] + cumulcorr]
 ], CompilationTarget -> "C", RuntimeOptions -> "Speed"];

unwrapPhaseVector[data_List] :=
  Switch[Length[data],
    0, {},
    1, data,
    _, unwrapPhaseVectorInt[data]];

nderivative[derivs__][d_List, opts___] :=
 Module[{grid, data, deriv},
  grid = d[[All,1]];
  data = d[[All,2]];
  deriv = NDSolve`FiniteDifferenceDerivative[Derivative[derivs], grid, data, opts];
  Transpose[{grid, deriv}]];

frequency[d_List] :=
  nderivative[1][phase[d]];

phase[d_List] :=
  Transpose[{d[[All,1]], unwrapPhaseVector[Arg[d[[All,2]]]]}]

resampled[d1_List, times_List] :=
  Module[{f},
    f = Interpolation[d1, InterpolationOrder -> 8];
    Table[{t, f[t]}, {t, times}]];

planckTaperFunction[coords_List, {t1_, t2_}] :=
  Module[{f},
    f[t_] :=
    Piecewise[
      {{0., t <= t1},
        {1., t >= t2},
        {If[Abs[t - t1] < 10^-9 || Abs[t - t2] < 10^-9,
          0., Chop[1./(1 + Exp[(t2 - t1) (1/(t - t1) + 1/(t - t2))])]], 
          t1 < t < t2}}];
    SetAttributes[f, {Listable, NumericFunction}];
    f[coords]];

planckTaperData[d_List, {t1_, t2_}] :=
  Transpose[{d[[All,1]],planckTaperCoords[d[[All,1]], {t1, t2}] d[[All,2]]}];

planckTaperData[d_List, {{t1_, t2_}, {t3_, t4_}}] :=
  Transpose[{d[[All,1]],
    planckTaperFunction[d[[All,1]], {t1, t2}] *
    (1 - planckTaperFunction[d[[All,1]], {t3, t4}]) d[[All,2]]}];

error[msg_String] :=
  Module[{},
    Print[msg];
    Abort[]];

(* Compute a list consisting of f1 for time < t, f2 for time > t+tau, and a
   Planck blend of the two for intermediate times *)
blend[f1_List, f2_List, tau_?NumericQ, t_?NumericQ] :=
  Module[{g1, g2, t1Max, t2Min, g1Fn, g2Fn, ts1, ts2, ts, large},
    large=10000000;
    g1 = planckTaperData[f1, {{-large, -large+100}, {t,t+tau}}];
    g2 = planckTaperData[f2, {{t,t+tau},{large,large+100}}];

    t1Max = g1[[-1,1]];
    t2Min = g2[[1,1]];

    If[t1Max < t+tau, error["blend: First list does not cover the blend region"]];
    If[t2Min > t, error["blend: Second list does not cover the blend region"]];

    g1Fn = Interpolation[g1];
    g2Fn = Interpolation[g2];
    
    ts1 = Select[g1[[All,1]], # < t &];
    ts2 = Select[g2[[All,1]], # > t &];

    If[Length[ts1] === 0, error["blend: No points in first list"]];
    If[Length[ts2] === 0, error["blend: No points in second list"]];
    ts = Join[ts1, ts2];
    
    Table[{tt, 
      If[tt <= t1Max, g1Fn[tt], 0.] + 
      If[tt >= t2Min, g2Fn[tt], 0.]}, {tt, ts}]];

blendWaveforms[{h1_List, h2_List}, {t1_, t2_}] := 
 Module[{freqBlend, ampBlend, ampBlendRes, freqBlendFn, phiBlendFn, 
   phiBlend, hBlend, phiFn, tPhi},
  freqBlend = blend[frequency[h1], frequency[h2], t2 - t1, t1];
  ampBlend = blend[MapAt[Abs,h1,{All,2}], MapAt[Abs,h2,{All,2}], t2 - t1, t1];
  ampBlendRes = resampled[ampBlend, freqBlend[[All,1]]];
  freqBlendFn = Interpolation[freqBlend];
  tPhi = t1;
  phiBlendFn = 
   phiFn /. 
    NDSolve[{phiFn'[t] == freqBlendFn[t], 
       phiFn[tPhi] == Interpolation[phase[h1]][tPhi]}, {phiFn}, {t, 
       freqBlend[[1,1]], freqBlend[[-1,1]]}][[1]];
  phiBlend = 
    Table[{t, phiBlendFn[t]}, {t, freqBlend[[All,1]]}];
  hBlend = Transpose[{ampBlendRes[[All,1]], ampBlendRes[[All,2]] Exp[I phiBlend[[All,2]]]}]];

EccentricIMRWaveform[params_Association, {t1_, t2_}] :=
  Module[{pnSoln, hCirc, ttm},
    pnSoln = EccentricPNSolution[params, {t1, t2}];
    hCirc = CircularWaveform[params["q"], 0.];
    ttm = timeToMergerFunction[];
    EccentricIMRWaveform[pnSoln, hCirc, params["q"], ttm]];

EccentricIMRWaveform[pnSoln_Association, hCirc_List, q_, ttm_] :=
 Module[{xFn, xRef, tRef, t, eRef, ttpCal, tPeakEcc, tPeakCirc, hCircShifted, hFn, 
   hPN, tBlendWindow, ePN, lPN, tBlendStart, xPN, tPN},

  xFn = pnSoln["x"];
  xPN = $maxPNX;

  tPN = t /. FindRoot[xFn[t] == xPN, {t, xFn[[1, 1, 2]] - 100}];
  tBlendStart = t /. FindRoot[xFn[t] == $blendStartX, {t, xFn[[1, 1, 2]] - 100}];
  ePN = pnSoln["e"][tPN];
  lPN = pnSoln["l"][tPN];
  ttpCal = ttm[q,ePN,lPN]; 
  tPeakEcc = tPN + ttpCal;
  tPeakCirc = timeOfPeak[hCirc];
  
  hCircShifted = shifted[hCirc, -tPeakCirc + tPeakEcc];
  hFn = pnSoln["h"];
  hPN = Table[{t, hFn[t]}, {t, hFn[[1, 1, 1]], hFn[[1, 1, 2]], 1}];
  tBlendWindow = {tBlendStart, tPeakEcc + $circularisationTime};
  blendWaveforms[{hPN, hCircShifted}, tBlendWindow]];

End[];

EndPackage[];
