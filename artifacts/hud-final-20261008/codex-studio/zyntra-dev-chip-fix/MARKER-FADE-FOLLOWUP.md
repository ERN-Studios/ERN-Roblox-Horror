# Marker fade-in race

RoundHud.fadeTo sets CanvasGroup.Visible=true before its tween advances GroupTransparency from 1. Store's existing Visible/size/position subscriptions run while the marker is still fully transparent; its alpha guard rejected the marker. Since tween alpha was not observed, the chip stayed on its incoming bounds. This explains first hiding failure and subsequent hiding-plus-reader pass without blaming measurement timing.

Store now reserves every Visible marker, including its incoming and outgoing transition. The existing Visible=false signal releases the slot after Attention finishes hiding. No per-frame opacity subscriptions are needed.

61 direct DEV runtime checks, 777 compact Store checks, compile PASS. The updated fixture uses an actual CanvasGroup shape at alpha1, then changes only alpha to .45; the frozen baseline fails its collision check. Root owns real native installation/retest. Exact hash/diff alongside. No Studio or UIRegression writes.
