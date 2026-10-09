# Engine-noter til QA

Kontrolleret 2026-10-08 i officielle Roblox-kilder; ingen ændring af spillet.

- [Raycasting](https://create.roblox.com/docs/workspace/raycasting) dokumenterer CanQuery og muligheden for at filtrere parts. [RaycastParams.RespectCanCollide](https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams/RespectCanCollide) bestemmer, om operationen prioriterer CanCollide over CanQuery. En transparent part er derfor ikke automatisk udelukket fra flashlightens geometriske clamp.
- [Technology](https://create.roblox.com/docs/reference/engine/enums/Technology) er afløst af LightingStyle og PrioritizeLightingQuality. QA skal aflæse aktuelle properties og faktisk grafikkvalitet, ikke alene den ældre Future/ShadowMap-label.
- [Global lighting](https://create.roblox.com/docs/environment/lighting) forklarer, at PrioritizeLightingQuality vælger mellem lys-/skyggekvalitet og synsafstand, når renderkvaliteten falder. Det gør grafikkvalitet til en kontrolvariabel i flicker-QA; det beviser ikke et shadow-budgetproblem i dette spil.
- [Improve performance](https://create.roblox.com/docs/performance-optimization/improve) beskriver automatisk nedskalering af skygger ved lavere grafikkvalitet og risiko for skyggeartefakter. Siden foreslår færre/kortere lys som performancegreb. Det er ikke tilladelse til at ændre flashlightens udseende uden målt årsag.
- [Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting) beskriver nu altid en maksimumrange på 120 studs. Repoets profilspecifikation og eksisterende test nævner stadig 60. Denne forskel er uden for flicker-fixets scope og må ikke føre til en tuningændring her; den aktuelle Studio-version og effektive Range skal måles.

Der blev ikke fundet et aktuelt, officielt præcist antal samtidige shadow-kastende SpotLights i de gennemgåede kilder. Ingen fast budgetgrænse er antaget eller rapporteret som fakta.
