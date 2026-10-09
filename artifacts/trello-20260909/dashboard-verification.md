# Creator Dashboard-kontrol, 9. september 2026

Read-only kontrol gennem den indloggede browser som mikkelczar og native Roblox Studio, ERN Roblox Studios (1039373905), experience 10559217407. Ingen kontokrav, gebyrer, priser, annoncer eller kommunikationsindstillinger ændret som del af denne kontrol.

## Målgruppe og publiceringskrav

[Audience Reach](https://create.roblox.com/dashboard/creations/experiences/10559217407/audience-reach) viste **Ages 16+ and trusted friends**, Mild: Fear (Repeated/Mild). Gruppe-reach stod All ages. Advarslen “Publishing tier at risk” om næste publicering var stadig vist. Publishing fee stod Not submitted. Kvalificerende højt engagerede spillere: **30/250**, opdateret **8. september 2026**; det er ikke CCU eller almindelige visits. Ekspederet evaluering viste 100.000 Robux. Ingen betaling udført.

Manage kunne denne gang åbnes. [Publishing permissions](https://create.roblox.com/settings/eligibility/publishing-permissions) viste **Your status: Publish to all ages**. Account status, Identity verification, Age check og 2-step verification havde grønne markeringer i denne kolonne; de tre handlingsknapper viste Done og var deaktiverede. Den tidligere owner-only adgangsblokering er dermed afklaret for denne session. Advarslen på oplevelsen er stadig synlig trods opfyldte kontokrav; dens præcise bagvedliggende årsag er ikke dokumenteret alene af disse sider. Spillets egen evaluering/kvalificering er endnu ikke opfyldt. Ingen adgang for yngre spillere kan erklæres leveret.

[Access settings](https://create.roblox.com/dashboard/creations/experiences/10559217407/access) havde All ages valgt, Free to play, desktop/mobile/tablet/VR slået til og console slået fra. Det valgte aldersfilter er ikke bevis for faktisk audience reach. Private servers var slået til med pris **20 Robux**, regional pricing og **to aktive abonnementer**.

[Audience-kortet](https://trello.com/c/iMTZhXMy) er opdateret med disse observationer og forbliver **To Do, complete=false**. Det tidligere afslag for LaverSneglen 6/9 samt tælleren dateret 4/9 er nu markeret som historik; originalbeskrivelsen er bevaret i [Trello-snapshot](../../docs/TRELLO_SNAPSHOT_2026-09-09.json). Kontoens status er ikke udlagt som bevis for opfyldt oplevelsesevaluering, og der er ikke tilskrevet denne audience-kontrol en kritikerscore.

## Voice chat

[Communication settings](https://create.roblox.com/dashboard/creations/experiences/10559217407/communication-settings) viste cross-server text chat slået til og strong language slået fra. Siden viste ingen voice-chat-indstilling; den beviser derfor ikke i sig selv VC-status.

Read-only Roblox Studio Server-probe i den aktuelle Play-session returnerede:

```json
{"UseAudioApi":"Enum.AudioApiRollout.Enabled","RigType":"Enum.HumanoidRigType.R15","EnableDefaultVoice":"true"}
```

Det dokumenterer de to VoiceChatService-egenskaber i denne session og den aktuelle avatars R15-rig. Experience-indstillingen Enable Voice Chat er en særskilt toggle; den blev efterfølgende kontrolleret direkte i native UI som beskrevet nedenfor. Proben dokumenterer hverken to spilleres faktiske mikrofonforbindelse i publiceret spil eller at alle mulige avatarer altid er R15. Virkelig samtaletest er stadig åben.

Efter Stop Play returnerede **Edit** samme `EnableDefaultVoice=true` og `UseAudioApi=Enabled`, samt `Players.MaxPlayers=60`. De to service-egenskaber er altså gemt i Edit og ikke blot testændringer. [Roblox' officielle VC-vejledning](https://create.roblox.com/docs/chat/voice-chat) beskriver den særskilte File → Experience Settings → Communication → Enable Voice Chat-toggle og grænsen på 100 spillere. Det aktuelle maksimum på 60 opfylder spillerloftet; den særskilte aktivering er også visuelt kontrolleret.

**Efterfølgende native UI-kontrol:** File → Experience Settings → Communication viste **Enable Voice Chat slået til** (grøn toggle), også Enable Camera til, Text & Voice Chat group APIs fra. Save var deaktiveret; ingen indstillinger blev ændret. Dialogen blev lukket med Cancel. Den overordnede voice-aktivering er dermed verificeret særskilt.

**Trello-status: Testing, complete=false**, genlæst 9/9. Kritikeren gav den afgrænsede konfigurationsaudit **9/10**. Scoren dokumenterer ikke en gennemført samtaletest, audience-kvalificering eller en ny featurepublicering. To kvalificerede spillere skal stadig mødes i publiceret spil og verificere tale i begge retninger, afstandsdæmpning og Roblox' mute. Se [VC-kortet](https://trello.com/c/echzcDhm).

**Supplerende observation fra Shop-Playtesten, dokumenteret 10/9:** Roblox' native CoreGUI viste **“Not Eligible for Voice — This account is not eligible to use Spatial Voice.”** Det fremgår af Shop-testens desktop-/telefonbilleder, blandt andet `shop-button-desktop.jpg` og `shop-button-phone-portrait.jpg`. Den aktuelle testklient kunne derfor ikke bruges til den krævede samtaletest med to mikrofoner. Dette er en observeret begrænsning for den benyttede konto i testen; årsagen er ikke fastslået, og observationen betyder ikke, at oplevelsens aktiverede voice-konfiguration er forkert. Ingen konto- eller VoiceChatService-/experience-indstillinger blev ændret. Kortet forbliver **Testing, complete=false** med faktisk samtale-/mute-test åben.

## Analytics og release

Overview viste **V1814 is live ved dashboardaflæsningen**. Den senere slide-rettelse er særskilt bekræftet publiceret som **v1816 med mus via File → Publish to Roblox, 9/9 kl. 22:49:48.993 dansk tid**, i native Studio Output; se [slide-verifikation](level3-slide-aperture-validation.md). Det er en senere releaseobservation, ikke en ændring af analyticsperioden.

Snapshot 7-day moving average, **2.–8. september**: DAU **180**, nye brugere **175**, D1 retention **1,45 %**, gennemsnitlig spilletid **12,5 minutter**, daglig revenue **9**. Weekly plays from ads: **888**; der har altså været annoncetrafik. Kortets præcise kampagne-/udgiftsfordeling blev ikke undersøgt.

Separate benchmarkfelter må ikke blandes med dette vindue: spilletid **12,7 min pr. 7/9**, D1 **1,77 % pr. 6/9**, D7 **0,00 % pr. 31/8**, payer conversion **0,04 % pr. 7/9**.

Monetization overview, **Last 7 days**: net Daily Robux Spent **63 i alt**, gennemsnit **9/dag**, Developer Products **63**, Standard DevEx Rate **63**. Gennemsnitlig daglig payer conversion **0,04 %**. Betalende brugere viste **0** efter afrunding; det er ikke bevis for nul køb. Gennemsnit pr. betalende **3,00 Robux**, pr. daglig bruger **0,00761**. Analytics angiver op til to dages forsinkelse. Et separat Hourly Robux Spent-diagram viste 120 (passes 69, products 51) i et andet vindue; dette er ikke lagt til syvdagestotalen.

Ingen af disse aggregerede tal viser priselasticitet, individuelle købsprompts eller årsagen til lav retention. De bruges som observeret grundlag for den reviderede research, ikke som bevis for en bestemt prisstrategi.
