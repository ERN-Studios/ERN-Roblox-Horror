# Read-only dokumentation til den senere native test

`native-readonly.server.luau` læser de eksisterende instanser og attributter fra den faktiske Studio-playserver. Den kræver Studio, kørende session og serverside; den er ikke kørt eller installeret som en del af kodeforberedelsen. Den kalder ingen moduler, remotes eller gameplay-mutationer.

Gem JSON-output ved de relevante trin i de to delsystemers runbooks: før død, efter død, efter en anden spillers faktiske pickup, efter gentaget død/genoplivning og efter cleanup. Bevar observationerne som separate snapshots sammen med screenshots. Serverens private sikringsantal er ikke eksponeret her; tilstedeværelsen af en håndvisual beviser ikke et bestemt antal. CD-attributter og fem identiteter kan sammenlignes direkte med de eksisterende drops og faktisk pickup.

Snapshotet viser model-/delpositioner, anchored/collision, antal/identitet, promptindstillinger og markeringsindhold. Det beviser ikke spillerens synlighed, fri gulvplads, læsbarhed, netværkstransport eller en gennemført pickup. De forhold skal ses/udføres i det virkelige klientforløb. En tom liste kan være korrekt før død/efter cleanup og er ikke i sig selv et test-pass. Manglende attributter betyder utilgængelige oplysninger, ikke nul.
