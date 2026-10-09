# WIP board preview, 10 September 2026

The current proposal is still outside the runtime tree. A disposable Builder copy replaced only its ServerLobby lookup/model name with TrelloWipPreview and generated a separate lobby at (10000,30,-760) during Play. Production Builder and the original lobby stayed present. The preview SpawnLocation was disabled immediately. Player position, camera and temporarily hidden ScreenGuis were restored; the preview was destroyed and Play stopped. No publication occurred.

The first preview showed that 34px secondary text was too small at 25 studs in the 770x400 Studio viewport. The proposal now uses 56px status/percentage labels with 0.12-height rows, a 96px title and higher percentage contrast. All fit in the existing canvas. The actual revised proposal was then rebuilt as a fresh module before the final inspection.

All three actual client SurfaceGuis report Title/LevelStatus/ProgressPercent TextFits=true and percentage TextSize=56. Fill widths are 0.600000024, 0.100000001 and 0.050000001, with the exact labels 60% COMPLETE, 10% COMPLETE and 5% COMPLETE. Screenshots from approximately 15 studs and a small oblique offset show the three boards clearly. Level 4 also has a 25-stud comparison.

- ../wip-native-preview-25stud-before.jpg and ../wip-native-preview-25stud-after.jpg show the style comparison; the after image used temporary client property changes to select typography before regenerating source.
- ../wip-native-preview-level4.jpg and ../wip-native-preview-level6.jpg show the rebuilt proposal.
- ../wip-native-preview-level5-corrected.jpg shows Level 5's actual Right face. The first level5 image viewed the wrong side and is not acceptance evidence.

The first preview query ran before the distant parts streamed to the client; moving the test character near the generated preview resolved it. A final doorway-geometry comparison used FindFirstChild by name even though DoorPost is duplicated and failed without a useful mismatched-part report. It is not evidence of either unchanged geometry or a source regression. Before publication, repeat a correct comparison using matched name/position multisets, confirm future collision and normal active queues, and get review of the enlarged typography. No native hardware or published-flow claim is made.

The corrected comparison was subsequently run in a fresh disposable Play build. Matching each named part to its nearest unused translated counterpart verifies all 114 doorway parts: position, size, orientation and CanCollide are unchanged within 0.002 studs. The X=10000 preview introduces float32 rounding (maximum position error 0.0009765625; maximum size error 0.0001163483 in calculated sign cantilevers), explicitly included in that tolerance. All three actual Level4/5/6SealedDoor parts block a 3.5x5x3.5 body sweep. See native-geometry.json. The fresh preview disappeared on Stop. Active queue behavior still awaits final normal-build acceptance.
