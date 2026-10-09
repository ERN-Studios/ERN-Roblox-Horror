# CD-forsøg 1 — input stoppet før pickup

A forsøgte faktisk E på Birthday Music CD01. Klient og fuld serverrecord matcher: ActualTriggered0, CDCount0/mask0,100HP og Releasedtrue efter.05081s af planlagt.35hold. ServerSameContext=true. Readinesskontrollen stoppede med `context-or-prompt-changed`; den specifikke underbetingelse logges ikke.

Den faktiske serverfejl kl.15:30:53.582UTC er `Actual E pickup/context failed` i accept, så dødssekvensen blev ikke kørt. To komplette chunkexports er bevaret; den afkortede CHANNEL_RESULT rålinje er ikke repareret eller skjult. Dette er et bevaret input/setup-afslag, ikke bevis for defekt CD-pickup eller death-drop.
