# Testliste til ejeren — Wheel / Shop / Rewards / Friend Boost (udkast, opdateres når koden er pushet)

Kør hvert punkt på desktop OG i Device Simulator (iPhone 13, portræt og landskab). I emulatoren
ligger UI'et i pointer-tier medmindre `workspace:SetAttribute("ForceTouchUI", true)` sættes i
command bar'en (emulatoren melder stadig mus + tastatur); sæt den før du tester touch-layouts.

## Lucky Wheel
- [ ] Tryk på Wheel-sideknappen: ALT andet UI forsvinder (sideknapper, valuta, shop-kort, Rewards,
      titler, paneler). Kun: hjulskive med tekstur, fast pil ved randen øverst, SPIN i navet, ét X
      øverst til højre, diskret mørk baggrund. Ingen rektangulær ramme.
- [ ] X lukker på desktop og mobil (mindst 44x44). Escape lukker. Efter luk er alt UI tilbage.
- [ ] Respawn (nulstil karakter) mens hjulet er åbent: hjulet lukker og HUD'en er korrekt igen.
- [ ] SPIN: hjulet drejer, pilen står stille, felter + tal drejer med. Resultatet vises kort i
      navet, derefter "SPUN" + nedtælling. Præmien matcher det felt pilen peger på.
- [ ] Alle fem præmier lander i det rigtige felt (Token1/Token3/Potion1/Potion2/Shield1 —
      Claude verificerer dette matematisk i Studio med `WheelLast.Key` mod pilens vinkel).
- [ ] Teksturen loader (ingen grå/blank skive). Tal i felterne: 1 token, 3 tokens, 1/2 speed
      potion, 1 entity shield + diskrete odds.
- [ ] Dobbelt-tryk på SPIN, luk under spin, genåbn: kun ét spin, kun én udbetaling.

## Daily Rewards
- [ ] Rewards-sideknap åbner det nye panel: varm header med gaveikon, "DAILY REWARDS", stort X.
- [ ] Tre store farvede kort (5 / 15 / 35 min) med store ikoner (token, potion, shield), tydelig
      status/nedtælling, CLAIM når klar, grønt check når modtaget.
- [ ] Claim virker og bliver husket efter genstart af Play (persistence).
- [ ] Ingen Rewards-plakat, tekst eller prompt i den fysiske shop.
- [ ] Shop, Wheel og Rewards kan ikke være åbne samtidig.

## Shop langs væggen
- [ ] Gammel shopbod/terminal, SHOP-skilt, fascia, sokler, navneplader og Daily Rewards-plakat er
      væk. Ingen "Zyntra Supply"/"ZYNTRA // SUPPLY" nogen steder i shoppen.
- [ ] Otte svævende hologram-bokse jævnt fordelt fra Level 2-gaten til Level 4-gaten, med
      tydeligt mere luft imellem; produktgrafik på alle seks sider; rolig op/ned-bevægelse med
      forskudt fase; gateåbninger og gangareal frie.
- [ ] Gå hen foran en boks: købskortet åbner automatisk (overskrift "SHOP"). BUY er eneste
      købsvej. CLOSE lukker uden at genåbne, mens man står stille. Gå til naboboksen: kortet
      skifter produkt. Gå væk: kortet lukker. Priser uændrede.

## Friend Boost
- [ ] I lobbyen: kompakt "FRIEND BOOST +X%"-chip med antal venner på serveren og en INVITE
      FRIENDS-knap, der åbner Roblox' invitationsflow. 0 venner = +0%.
- [ ] Med en ven på serveren (test med to konti, der er Roblox-venner): +10%; når vennen
      forlader serveren: tilbage til +0%. Chippen er skjult, når hjulet er åbent og i runder.
- [ ] Gennemfør et level sammen med vennen: beskeden viser "+N ... (Friend Boost +10%)" og
      brøkrest gemmes (1 ven: hel bonus-token ved 5. gennemførsel). Uden ven: +2 som før.
