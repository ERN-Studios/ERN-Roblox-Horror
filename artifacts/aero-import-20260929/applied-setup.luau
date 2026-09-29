assert(game.PlaceId==121672571539226)
local baseline=_G.AeroReplaceBaseline
assert(baseline and baseline.house.Parent==workspace and baseline.cathedral.Parent==baseline.cathedralParent)
assert(baseline.house:GetPivot()==baseline.housePivot and #baseline.house:GetDescendants()==baseline.houseCount)
assert(baseline.cathedral:GetPivot()==baseline.cathedralPivot and #baseline.cathedral:GetDescendants()==baseline.cathedralCount)
baseline.house:PivotTo(CFrame.new(0,1,0)*CFrame.Angles(0,math.pi,0))
game:GetService("Selection"):Set({baseline.house})
-- Aero House: select the complete imported Model in Studio Edit mode, then run
-- the packaged SetupAeroHouse.luau in the Command Bar. This template is filled
-- during export. The three named decorative anchors must remain in the import.
-- This changes only the selected house. It does not add scripts, change gravity,
-- create a spawn, save, or publish. Standard Roblox gravity is 196.2 studs/s^2.
-- Setup is one undoable operation. Undo before rerunning; existing data is never
-- replaced. Import at the documented stud scale, then move/rotate the whole house.

local MANIFEST_JSON = [==[{"version":1,"modelName":"Aero House","anchorSizeRoblox":[0.6,0.6,0.6],"authoring":"Blender Z up, 1 unit = 1 Roblox stud","exportMapping":"(x,y,z) -> (x,z,-y), setup derives import yaw from 3 geometry markers","colliders":[{"name":"Site_001","position":[0,-0.45,0],"size":[118,0.7,102],"rotation":[0,0.0,0]},{"name":"GroundFloor_002","position":[0,0.45,0],"size":[102,1.1,80],"rotation":[0,0.0,0]},{"name":"FrontPorch_003","position":[0,0.4,41],"size":[86,1.2,6],"rotation":[0,0.0,0]},{"name":"RearEdge_004","position":[0,0.4,-42],"size":[86,1.2,7],"rotation":[0,0.0,0]},{"name":"WestEdge_005","position":[-51,0.4,0],"size":[7,1.2,70],"rotation":[0,0.0,0]},{"name":"EastEdge_006","position":[51,0.4,0],"size":[7,1.2,70],"rotation":[0,0.0,0]},{"name":"Entry__path_007","position":[0,0.06,49],"size":[14,0.24,10],"rotation":[0,0.0,0]},{"name":"Entry__step_008","position":[0,0.18,45.0],"size":[14,0.36,1.6],"rotation":[0,0.0,0]},{"name":"Entry__step_009","position":[0,0.41000000000000003,44.35],"size":[14,0.8200000000000001,1.6],"rotation":[0,0.0,0]},{"name":"FrontLeftG__glass_010","position":[-38.16666793823242,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontLeftG__glass_011","position":[-26.5,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontLeftG__glass_012","position":[-14.833333969116211,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontRightG__glass_013","position":[14.833333969116211,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontRightG__glass_014","position":[26.5,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontRightG__glass_015","position":[38.166664123535156,9.3,43.0],"size":[11.666666666666666,14.4,0.28],"rotation":[0,0.0,0]},{"name":"WestG__glass_016","position":[-53.0,9.3,29.16666603088379],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestG__glass_017","position":[-53.0,9.3,17.5],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestG__glass_018","position":[-53.0,9.3,5.833333969116211],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestG__glass_019","position":[-53.0,9.3,-5.833332061767578],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestG__glass_020","position":[-53.0,9.3,-17.5],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestG__glass_021","position":[-53.0,9.3,-29.166671752929688],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_022","position":[53.0,9.3,29.16666603088379],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_023","position":[53.0,9.3,17.5],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_024","position":[53.0,9.3,5.833333969116211],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_025","position":[53.0,9.3,-5.833332061767578],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_026","position":[53.0,9.3,-17.5],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastG__glass_027","position":[53.0,9.3,-29.166671752929688],"size":[0.28,14.4,11.666666666666666],"rotation":[0,0.0,0]},{"name":"RearG__glass_028","position":[-37.71428680419922,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_029","position":[-25.14285659790039,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_030","position":[-12.571428298950195,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_031","position":[0.0,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_032","position":[12.571426391601562,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_033","position":[25.142852783203125,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"RearG__glass_034","position":[37.71428680419922,9.3,-43.0],"size":[12.571428571428571,14.4,0.28],"rotation":[0,0.0,0]},{"name":"FrontLeftU__glass_035","position":[-38.16666793823242,25.75,43.0],"size":[11.666666666666666,15.5,0.28],"rotation":[0,0.0,0]},{"name":"FrontLeftU__glass_036","position":[-26.5,25.75,43.0],"size":[11.666666666666666,15.5,0.28],"rotation":[0,0.0,0]},{"name":"FrontLeftU__glass_037","position":[-14.833333969116211,25.75,43.0],"size":[11.666666666666666,15.5,0.28],"rotation":[0,0.0,0]},{"name":"WestU__glass_041","position":[-53.0,25.75,29.16666603088379],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestU__glass_042","position":[-53.0,25.75,17.5],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestU__glass_043","position":[-53.0,25.75,5.833333969116211],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestU__glass_044","position":[-53.0,25.75,-5.833332061767578],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestU__glass_045","position":[-53.0,25.75,-17.5],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"WestU__glass_046","position":[-53.0,25.75,-29.166671752929688],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_047","position":[53.0,25.75,29.16666603088379],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_048","position":[53.0,25.75,17.5],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_049","position":[53.0,25.75,5.833333969116211],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_050","position":[53.0,25.75,-5.833332061767578],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_051","position":[53.0,25.75,-17.5],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"EastU__glass_052","position":[53.0,25.75,-29.166671752929688],"size":[0.28,15.5,11.666666666666666],"rotation":[0,0.0,0]},{"name":"RearU__glass_053","position":[-37.71428680419922,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_054","position":[-25.14285659790039,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_055","position":[-12.571428298950195,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_056","position":[0.0,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_057","position":[12.571426391601562,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_058","position":[25.142852783203125,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"RearU__glass_059","position":[37.71428680419922,25.75,-43.0],"size":[12.571428571428571,15.5,0.28],"rotation":[0,0.0,0]},{"name":"CornerShell_060","position":[-47.5,17.1,37.5],"size":[9.5,32.4,9.5],"rotation":[0,0.0,0]},{"name":"CornerShell_061","position":[-47.5,17.1,-37.5],"size":[9.5,32.4,9.5],"rotation":[0,0.0,0]},{"name":"CornerShell_062","position":[47.5,17.1,37.5],"size":[9.5,32.4,9.5],"rotation":[0,0.0,0]},{"name":"CornerShell_063","position":[47.5,17.1,-37.5],"size":[9.5,32.4,9.5],"rotation":[0,0.0,0]},{"name":"Entry__jamb_064","position":[-8.4,8.8,43],"size":[1.2,15.4,1.8],"rotation":[0,0.0,0]},{"name":"Entry__jamb_065","position":[8.4,8.8,43],"size":[1.2,15.4,1.8],"rotation":[0,0.0,0]},{"name":"Entry__header_066","position":[0,14.5,43],"size":[16,4.2,1.8],"rotation":[0,0.0,0]},{"name":"EntrySide_067","position":[-6.6,6.4,43],"size":[2.1,10.5,0.3],"rotation":[0,0.0,0]},{"name":"EntrySide_068","position":[6.6,6.4,43],"size":[2.1,10.5,0.3],"rotation":[0,0.0,0]},{"name":"UpperFloorEast_069","position":[33,17.5,0],"size":[40,1,86],"rotation":[0,0.0,0]},{"name":"UpperFloorRear_070","position":[-19.5,17.5,-30],"size":[65,1,26],"rotation":[0,0.0,0]},{"name":"UpperBridge_071","position":[0,17.5,26],"size":[26,1,34],"rotation":[0,0.0,0]},{"name":"EntryUpper__glass_072","position":[0.0,25.75,43.0],"size":[16.0,15.5,0.28],"rotation":[0,0.0,0]},{"name":"GuestWall_073","position":[-39.5,8.75,-17],"size":[13.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"GuestWall_074","position":[-19.5,8.75,-17],"size":[11.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"GuestWall_075","position":[-29.0,14.0,-17],"size":[8.0,5.0,0.7],"rotation":[0,0.0,0]},{"name":"StudyWall_076","position":[20.0,8.75,-17],"size":[10.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"StudyWall_077","position":[39.5,8.75,-17],"size":[13.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"StudyWall_078","position":[29.0,14.0,-17],"size":[8.0,5.0,0.7],"rotation":[0,0.0,0]},{"name":"BathFront_079","position":[-7.75,8.75,-22],"size":[8.5,15.5,0.7],"rotation":[0,0.0,0]},{"name":"BathFront_080","position":[7.75,8.75,-22],"size":[8.5,15.5,0.7],"rotation":[0,0.0,0]},{"name":"BathFront_081","position":[0.0,14.0,-22],"size":[7.0,5.0,0.7],"rotation":[0,0.0,0]},{"name":"GuestSide_082","position":[-14,8.75,-30.0],"size":[0.7,15.5,26],"rotation":[0,0.0,0]},{"name":"StudySide_083","position":[15,8.75,-30.0],"size":[0.7,15.5,26],"rotation":[0,0.0,0]},{"name":"BathSideL_084","position":[-12,8.75,-32.5],"size":[0.7,15.5,21],"rotation":[0,0.0,0]},{"name":"BathSideR_085","position":[12,8.75,-32.5],"size":[0.7,15.5,21],"rotation":[0,0.0,0]},{"name":"MasterFront_086","position":[-39.5,25.75,-21.5],"size":[13.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"MasterFront_087","position":[-19.5,25.75,-21.5],"size":[11.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"MasterFront_088","position":[-29.0,31.0,-21.5],"size":[8.0,5.0,0.7],"rotation":[0,0.0,0]},{"name":"UpperGuestFront_089","position":[20.0,25.75,-21.5],"size":[10.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"UpperGuestFront_090","position":[39.5,25.75,-21.5],"size":[13.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"UpperGuestFront_091","position":[29.0,31.0,-21.5],"size":[8.0,5.0,0.7],"rotation":[0,0.0,0]},{"name":"UpperMasterSide_092","position":[-14,25.75,-32.25],"size":[0.7,15.5,21.5],"rotation":[0,0.0,0]},{"name":"UpperGuestSide_093","position":[15,25.75,-32.25],"size":[0.7,15.5,21.5],"rotation":[0,0.0,0]},{"name":"ReadingWall_094","position":[20.0,25.75,-1],"size":[8.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"ReadingWall_095","position":[40.0,25.75,-1],"size":[12.0,15.5,0.7],"rotation":[0,0.0,0]},{"name":"ReadingWall_096","position":[29.0,31.25,-1],"size":[10.0,4.5,0.7],"rotation":[0,0.0,0]},{"name":"RoofBack_097","position":[0.0,34.75,-30.0],"size":[108,0.9,28],"rotation":[0,0.0,0]},{"name":"RoofFront_098","position":[0.0,34.75,30.75],"size":[108,0.9,26.5],"rotation":[0,0.0,0]},{"name":"RoofLeft_099","position":[-47.5,34.75,0.75],"size":[13,0.9,33.5],"rotation":[0,0.0,0]},{"name":"RoofRight_100","position":[25.25,34.75,0.75],"size":[57.5,0.9,33.5],"rotation":[0,0.0,0]},{"name":"Terrace_101","position":[31,17.5,49],"size":[36,1,12],"rotation":[0,0.0,0]},{"name":"TerraceRail__guard_102","position":[31.0,20.0,54.0],"size":[36.0,4,0.4],"rotation":[0,0.0,0]},{"name":"TerraceRail__guard_103","position":[49.0,20.0,49.0],"size":[0.4,4,10.0],"rotation":[0,0.0,0]},{"name":"AtriumRearRail__guard_104","position":[-31.5,20.0,-17.0],"size":[35.0,4,0.4],"rotation":[0,0.0,0]},{"name":"AtriumBridgeRail__guard_105","position":[-13.0,20.0,22.0],"size":[0.4,4,32.0],"rotation":[0,0.0,0]},{"name":"StairFlightA_106","position":[6.5,1.25,15.192307692307692],"size":[7,0.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_107","position":[6.5,1.5,13.576923076923077],"size":[7,1.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_108","position":[6.5,1.75,11.961538461538462],"size":[7,1.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_109","position":[6.5,2.0,10.346153846153847],"size":[7,2.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_110","position":[6.5,2.25,8.73076923076923],"size":[7,2.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_111","position":[6.5,2.5,7.115384615384615],"size":[7,3.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_112","position":[6.5,2.75,5.5],"size":[7,3.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_113","position":[6.5,3.0,3.884615384615385],"size":[7,4.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_114","position":[6.5,3.25,2.26923076923077],"size":[7,4.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_115","position":[6.5,3.5,0.6538461538461533],"size":[7,5.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_116","position":[6.5,3.75,-0.9615384615384599],"size":[7,5.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_117","position":[6.5,4.0,-2.5769230769230766],"size":[7,6.0,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairFlightA_118","position":[6.5,4.25,-4.192307692307693],"size":[7,6.5,1.6303846153846153],"rotation":[0,0.0,0]},{"name":"StairTurn_119","position":[4.677944801512114,4.5,-5.731588707560481],"size":[4.0,7.0,2.267837196810132],"rotation":[0,11.25,0]},{"name":"StairTurn_120","position":[8.110693282923421,4.5,-6.41440483461693],"size":[4.0,7.0,3.7110063220529432],"rotation":[0,11.25,0]},{"name":"StairTurn_121","position":[4.118011046134544,4.75,-7.083388373823508],"size":[4.0,7.5,2.267837196810132],"rotation":[0,33.75,0]},{"name":"StairTurn_122","position":[7.028154689193453,4.75,-9.027884189392115],"size":[4.0,7.5,3.7110063220529432],"rotation":[0,33.75,0]},{"name":"StairTurn_123","position":[3.0833883738235084,5.0,-8.118011046134544],"size":[4.0,8.0,2.267837196810132],"rotation":[0,56.25,0]},{"name":"StairTurn_124","position":[5.0278841893921165,5.0,-11.028154689193453],"size":[4.0,8.0,3.7110063220529432],"rotation":[0,56.25,0]},{"name":"StairTurn_125","position":[1.7315887075604812,5.25,-8.677944801512114],"size":[4.0,8.5,2.267837196810132],"rotation":[0,78.75,0]},{"name":"StairTurn_126","position":[2.4144048346169305,5.25,-12.110693282923421],"size":[4.0,8.5,3.7110063220529432],"rotation":[0,78.75,0]},{"name":"StairTurn_127","position":[0.2684112924395192,5.5,-8.677944801512114],"size":[4.0,9.0,2.267837196810132],"rotation":[0,101.25,0]},{"name":"StairTurn_128","position":[-0.41440483461692934,5.5,-12.110693282923421],"size":[4.0,9.0,3.7110063220529432],"rotation":[0,101.25,0]},{"name":"StairTurn_129","position":[-1.0833883738235075,5.75,-8.118011046134544],"size":[4.0,9.5,2.267837196810132],"rotation":[0,123.74999999999999,0]},{"name":"StairTurn_130","position":[-3.027884189392114,5.75,-11.028154689193453],"size":[4.0,9.5,3.7110063220529432],"rotation":[0,123.74999999999999,0]},{"name":"StairTurn_131","position":[-2.118011046134545,6.0,-7.083388373823508],"size":[4.0,10.0,2.267837196810132],"rotation":[0,146.25,0]},{"name":"StairTurn_132","position":[-5.028154689193454,6.0,-9.027884189392115],"size":[4.0,10.0,3.7110063220529432],"rotation":[0,146.25,0]},{"name":"StairTurn_133","position":[-2.677944801512114,6.25,-5.7315887075604826],"size":[4.0,10.5,2.267837196810132],"rotation":[0,168.75,0]},{"name":"StairTurn_134","position":[-6.110693282923421,6.25,-6.414404834616932],"size":[4.0,10.5,3.7110063220529432],"rotation":[0,168.75,0]},{"name":"StairFlightB_135","position":[-4.5,6.5,-4.461538461538462],"size":[7,11.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_136","position":[-4.5,6.75,-3.3846153846153846],"size":[7,11.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_137","position":[-4.5,7.0,-2.3076923076923075],"size":[7,12.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_138","position":[-4.5,7.25,-1.2307692307692308],"size":[7,12.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_139","position":[-4.5,7.5,-0.1538461538461542],"size":[7,13.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_140","position":[-4.5,7.75,0.9230769230769234],"size":[7,13.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_141","position":[-4.5,8.0,2.0],"size":[7,14.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_142","position":[-4.5,8.25,3.0769230769230766],"size":[7,14.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_143","position":[-4.5,8.5,4.153846153846153],"size":[7,15.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_144","position":[-4.5,8.75,5.23076923076923],"size":[7,15.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_145","position":[-4.5,9.0,6.307692307692308],"size":[7,16.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_146","position":[-4.5,9.25,7.384615384615385],"size":[7,16.5,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairFlightB_147","position":[-4.5,9.5,8.461538461538462],"size":[7,17.0,1.096923076923077],"rotation":[0,0.0,0]},{"name":"StairVoidEast__guard_148","position":[13.0,20.0,-5.050000190734863],"size":[0.4,4,21.100000520679053],"rotation":[0,0.0,0]},{"name":"StairVoidRear__guard_149","position":[0.25,20.0,-17.0],"size":[24.5,4,0.4],"rotation":[0,0.0,0]},{"name":"FrontRightU__glass_147","position":[16.5,25.75,43.0],"size":[15.0,15.5,0.28],"rotation":[0,0.0,0]},{"name":"FrontRightU__glass_148","position":[38.5,25.75,43.0],"size":[11.0,15.5,0.28],"rotation":[0,0.0,0]},{"name":"TerraceDoorHeader_149","position":[28.5,31.0,43],"size":[9,5,0.7],"rotation":[0,0.0,0]},{"name":"Lounge__Sofa_150","position":[-29.5,3.1,4.0],"size":[20.0,4.2,5.2],"rotation":[0,0.0,0]},{"name":"Lounge__EasyChairA_151","position":[-36.8,3.4,23.5],"size":[4.7,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Lounge__EasyChairB_152","position":[-22.3,3.4,23.5],"size":[4.7,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Lounge__CoffeeTable_153","position":[-29.5,2.3,14.3],"size":[10.2,2.6,5.3],"rotation":[0,0.0,0]},{"name":"Lounge__EndTable_154","position":[-38.6,2.5,14.5],"size":[2.2,3,2.2],"rotation":[0,0.0,0]},{"name":"Lounge__PalmPot_155","position":[-18.3,1.9,24],"size":[2.16,1.8,2.16],"rotation":[0,0.0,0]},{"name":"Kitchen__Cabinets_156","position":[26.2,3.0,11.4],"size":[13.7,4.0,4.3],"rotation":[0,0.0,0]},{"name":"Kitchen__Fridge_157","position":[37.05,5.4,11.6],"size":[4.9,8.8,4.6],"rotation":[0,0.0,0]},{"name":"Dining__Table_158","position":[28.3,2.9,21],"size":[8.5,3.8,4.45],"rotation":[0,0.0,0]},{"name":"Dining__ChairWest_159","position":[21.7,3.4,21.0],"size":[3.3,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Dining__ChairEast_160","position":[34.9,3.4,21.0],"size":[3.3,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Dining__ChairFront_161","position":[28.3,3.4,25.0],"size":[3.3,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Dining__ChairRear_162","position":[28.3,3.4,16.2],"size":[3.3,4.8,3.3],"rotation":[0,0.0,0]},{"name":"GuestBedroom__BedBedside0_163","position":[-37.7,2.4,-29.0],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"GuestBedroom__BedBedside1_164","position":[-24.3,2.4,-29.0],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"GuestBedroom__Bed_165","position":[-31,2.5,-26.8],"size":[10.649999999999999,3.0,8.35],"rotation":[0,0.0,0]},{"name":"GuestBedroom__BedHeadboard_166","position":[-31,3.82,-30.650000000000002],"size":[10.549999999999999,4.25,0.65],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__BedBedside0_167","position":[-37.7,19.4,-33.2],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__BedBedside1_168","position":[-24.3,19.4,-33.2],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__Bed_169","position":[-31,19.5,-31],"size":[10.649999999999999,3.0,8.35],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__BedHeadboard_170","position":[-31,20.82,-34.85],"size":[10.549999999999999,4.25,0.65],"rotation":[0,0.0,0]},{"name":"UpperLimeBedroom__BedBedside0_171","position":[24.65,19.4,-33.2],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"UpperLimeBedroom__BedBedside1_172","position":[37.35,19.4,-33.2],"size":[2.2,2.8,2.15],"rotation":[0,0.0,0]},{"name":"UpperLimeBedroom__Bed_173","position":[31,19.5,-31],"size":[9.95,3.0,8.35],"rotation":[0,0.0,0]},{"name":"UpperLimeBedroom__BedHeadboard_174","position":[31,20.82,-34.85],"size":[9.85,4.25,0.65],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__PlantPot_175","position":[-21.4,18.9,-24.1],"size":[2.16,1.8,2.16],"rotation":[0,0.0,0]},{"name":"Bathroom__Vanity_176","position":[-3.5,2.85,-29.3],"size":[4.75,3.7,3.3],"rotation":[0,0.0,0]},{"name":"Bathroom__Toilet_177","position":[2.4,2.85,-29.0],"size":[2.1,3.7,3.1],"rotation":[0,0.0,0]},{"name":"Study__DeskChair_178","position":[32,3.4,-24.0],"size":[3.8,4.8,3.3],"rotation":[0,0.0,0]},{"name":"Study__Desk_179","position":[32,3.0,-28.7],"size":[11.8,4.7,3.9],"rotation":[0,0.0,0]},{"name":"Study__PlantPot_180","position":[26.1,1.9,-23.8],"size":[2.16,1.8,2.16],"rotation":[0,0.0,0]},{"name":"UpperReading__Sofa_181","position":[31,20.1,14.6],"size":[14.6,4.2,5.2],"rotation":[0,0.0,0]},{"name":"UpperReading__Table_182","position":[31,19.4,22],"size":[6.4,2.8,3.4],"rotation":[0,0.0,0]},{"name":"UpperReading__SideTable_183","position":[38.5,19.5,21.3],"size":[2.2,3,2.2],"rotation":[0,0.0,0]},{"name":"GuestBedroom__Wardrobe_184","position":[-47.4,5.7,-26.8],"size":[3.8,9.4,8.0],"rotation":[0,0.0,0]},{"name":"UpperCyanBedroom__Wardrobe_185","position":[-47.4,22.7,-28.0],"size":[3.8,9.4,8.0],"rotation":[0,0.0,0]},{"name":"UpperLimeBedroom__Wardrobe_186","position":[47.4,22.7,-28.0],"size":[3.8,9.4,8.0],"rotation":[0,0.0,0]},{"name":"Lounge__MediaConsole_187","position":[-29.5,2.44,35.8],"size":[14,2.9,2.95],"rotation":[0,0.0,0]},{"name":"Lounge__TV_188","position":[-29.5,6.55,35.7],"size":[8.4,4.7,0.86],"rotation":[0,0.0,0]},{"name":"Study__Shelf_189","position":[43.6,5.0,-26.0],"size":[2.3,8.0,6.8],"rotation":[0,0.0,0]},{"name":"TerraceFurniture__ChairWest_190","position":[37.4,20.4,49.4],"size":[3.3,4.8,3.6],"rotation":[0,0.0,0]},{"name":"TerraceFurniture__ChairEast_191","position":[45.0,20.4,49.4],"size":[3.3,4.8,3.6],"rotation":[0,0.0,0]},{"name":"TerraceFurniture__RoundTable_192","position":[41.2,19.5,49.4],"size":[2.2,3,2.2],"rotation":[0,0.0,0]}],"lights":[{"name":"Lounge","position":[-28,13,9],"color":[0.65,0.95,1],"range":32,"brightness":1.2},{"name":"Kitchen","position":[30,13,13],"color":[0.92,1,0.7],"range":27,"brightness":1},{"name":"Hall","position":[0,14,-18],"color":[0.8,1,1],"range":24,"brightness":1},{"name":"Reading","position":[28,29,17],"color":[0.9,1,0.75],"range":26,"brightness":1}],"meshReport":[{"name":"Aero_Site_Palette","triangles":140,"vertices":72,"material":"Aero_Palette"},{"name":"Aero_GroundFloor_Palette","triangles":140,"vertices":72,"material":"Aero_Palette"},{"name":"Aero_Entry_Palette","triangles":1708,"vertices":872,"material":"Aero_Palette"},{"name":"Aero_MiddleRibbon_Palette","triangles":288,"vertices":144,"material":"Aero_Palette"},{"name":"Aero_MiddleAccent_Palette","triangles":288,"vertices":144,"material":"Aero_Palette"},{"name":"Aero_RoofRibbon_Palette","triangles":288,"vertices":144,"material":"Aero_Palette"},{"name":"Aero_RoofAccent_Palette","triangles":288,"vertices":144,"material":"Aero_Palette"},{"name":"Aero_FrontLeftG_Glass","triangles":36,"vertices":24,"material":"Aero_Glass"},{"name":"Aero_FrontLeftG_Palette","triangles":648,"vertices":336,"material":"Aero_Palette"},{"name":"Aero_FrontRightG_Glass","triangles":36,"vertices":24,"material":"Aero_Glass"},{"name":"Aero_FrontRightG_Palette","triangles":648,"vertices":336,"material":"Aero_Palette"},{"name":"Aero_WestG_Glass","triangles":72,"vertices":48,"material":"Aero_Glass"},{"name":"Aero_WestG_Palette","triangles":972,"vertices":504,"material":"Aero_Palette"},{"name":"Aero_EastG_Glass","triangles":72,"vertices":48,"material":"Aero_Glass"},{"name":"Aero_EastG_Palette","triangles":972,"vertices":504,"material":"Aero_Palette"},{"name":"Aero_RearG_Glass","triangles":84,"vertices":56,"material":"Aero_Glass"},{"name":"Aero_RearG_Palette","triangles":1080,"vertices":560,"material":"Aero_Palette"},{"name":"Aero_FrontLeftU_Glass","triangles":36,"vertices":24,"material":"Aero_Glass"},{"name":"Aero_FrontLeftU_Palette","triangles":648,"vertices":336,"material":"Aero_Palette"},{"name":"Aero_WestU_Glass","triangles":72,"vertices":48,"material":"Aero_Glass"},{"name":"Aero_WestU_Palette","triangles":972,"vertices":504,"material":"Aero_Palette"},{"name":"Aero_EastU_Glass","triangles":72,"vertices":48,"material":"Aero_Glass"},{"name":"Aero_EastU_Palette","triangles":972,"vertices":504,"material":"Aero_Palette"},{"name":"Aero_RearU_Glass","triangles":84,"vertices":56,"material":"Aero_Glass"},{"name":"Aero_RearU_Palette","triangles":1080,"vertices":560,"material":"Aero_Palette"},{"name":"Aero_CornerShell_Palette","triangles":2352,"vertices":1184,"material":"Aero_Palette"},{"name":"Aero_Entry_Glass","triangles":24,"vertices":16,"material":"Aero_Glass"},{"name":"Aero_UpperFloorEast_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_UpperFloorRear_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_UpperBridge_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_EntryUpper_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_EntryUpper_Palette","triangles":432,"vertices":224,"material":"Aero_Palette"},{"name":"Aero_GuestWall_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_StudyWall_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_BathFront_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_GuestSide_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_StudySide_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_BathSideL_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_BathSideR_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_MasterFront_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_UpperGuestFront_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_UpperMasterSide_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_UpperGuestSide_Palette","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_ReadingWall_Palette","triangles":700,"vertices":360,"material":"Aero_Palette"},{"name":"Aero_RoofBack_Palette","triangles":76,"vertices":40,"material":"Aero_Palette"},{"name":"Aero_RoofFront_Palette","triangles":76,"vertices":40,"material":"Aero_Palette"},{"name":"Aero_RoofLeft_Palette","triangles":12,"vertices":8,"material":"Aero_Palette"},{"name":"Aero_RoofRight_Palette","triangles":12,"vertices":8,"material":"Aero_Palette"},{"name":"Aero_Skylight_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_SkylightFrame_Palette","triangles":752,"vertices":384,"material":"Aero_Palette"},{"name":"Aero_Terrace_Palette","triangles":376,"vertices":216,"material":"Aero_Palette"},{"name":"Aero_TerraceRail_Palette","triangles":364,"vertices":200,"material":"Aero_Palette"},{"name":"Aero_TerraceRail_Glass","triangles":24,"vertices":16,"material":"Aero_Glass"},{"name":"Aero_AtriumRearRail_Palette","triangles":204,"vertices":112,"material":"Aero_Palette"},{"name":"Aero_AtriumRearRail_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_AtriumBridgeRail_Palette","triangles":204,"vertices":112,"material":"Aero_Palette"},{"name":"Aero_AtriumBridgeRail_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_RoofFin_Palette","triangles":1128,"vertices":576,"material":"Aero_Palette"},{"name":"Aero_StairFlightA_Palette","triangles":572,"vertices":312,"material":"Aero_Palette"},{"name":"Aero_StairNosingA_Palette","triangles":156,"vertices":104,"material":"Aero_Palette"},{"name":"Aero_StairTurn_Palette","triangles":96,"vertices":64,"material":"Aero_Palette"},{"name":"Aero_StairFlightB_Palette","triangles":572,"vertices":312,"material":"Aero_Palette"},{"name":"Aero_StairNosingB_Palette","triangles":156,"vertices":104,"material":"Aero_Palette"},{"name":"Aero_StairRails_Palette","triangles":3672,"vertices":1888,"material":"Aero_Palette"},{"name":"Aero_StairVoidEast_Palette","triangles":160,"vertices":88,"material":"Aero_Palette"},{"name":"Aero_StairVoidEast_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_StairVoidRear_Palette","triangles":160,"vertices":88,"material":"Aero_Palette"},{"name":"Aero_StairVoidRear_Glass","triangles":12,"vertices":8,"material":"Aero_Glass"},{"name":"Aero_LowerRibbon_Palette","triangles":940,"vertices":480,"material":"Aero_Palette"},{"name":"Aero_FrontRightU_Glass","triangles":24,"vertices":16,"material":"Aero_Glass"},{"name":"Aero_FrontRightU_Palette","triangles":864,"vertices":448,"material":"Aero_Palette"},{"name":"Aero_TerraceDoorHeader_Palette","triangles":188,"vertices":96,"material":"Aero_Palette"},{"name":"Aero_Lounge_Palette","triangles":4284,"vertices":2248,"material":"Aero_Palette"},{"name":"Aero_Kitchen_Palette","triangles":1832,"vertices":968,"material":"Aero_Palette"},{"name":"Aero_Dining_Palette","triangles":2140,"vertices":1112,"material":"Aero_Palette"},{"name":"Aero_GuestBedroom_Palette","triangles":1704,"vertices":888,"material":"Aero_Palette"},{"name":"Aero_UpperCyanBedroom_Palette","triangles":2260,"vertices":1200,"material":"Aero_Palette"},{"name":"Aero_UpperLimeBedroom_Palette","triangles":1704,"vertices":888,"material":"Aero_Palette"},{"name":"Aero_Bathroom_Palette","triangles":1328,"vertices":690,"material":"Aero_Palette"},{"name":"Aero_Study_Palette","triangles":2776,"vertices":1478,"material":"Aero_Palette"},{"name":"Aero_UpperReading_Palette","triangles":2444,"vertices":1256,"material":"Aero_Palette"},{"name":"Aero_TerraceFurniture_Palette","triangles":836,"vertices":440,"material":"Aero_Palette"},{"name":"Aero_Lounge_Glow","triangles":320,"vertices":160,"material":"Aero_Glow"},{"name":"Aero_Dining_Glow","triangles":320,"vertices":160,"material":"Aero_Glow"},{"name":"Aero_UpperReading_Glow","triangles":320,"vertices":160,"material":"Aero_Glow"},{"name":"Aero_Anchor_Entry","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_Anchor_RearRight","triangles":108,"vertices":56,"material":"Aero_Palette"},{"name":"Aero_Anchor_RearLeft","triangles":108,"vertices":56,"material":"Aero_Palette"}],"triangleCount":53128,"meshCount":88,"expectedBoundsRoblox":{"size":[124.0,37.650001525878906,109.0],"min":[-62.0,-0.75,-54.0],"max":[62.0,36.900001525878906,55.0]},"playModeVerified":false}]==]
local ENABLE_LOCAL_LIGHTS = true

local HttpService = game:GetService("HttpService")
local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local RUNTIME_NAME = "AeroRuntime"
local OWNER = "aero-house"

assert(not RunService:IsRunning(), "Run Aero House setup in Edit mode, outside a Play test.")
local selected = Selection:Get()
assert(#selected == 1 and selected[1]:IsA("Model"), "Select exactly the complete imported Aero House Model.")
local model = selected[1]
assert(model:IsDescendantOf(workspace), "The selected house must be in Workspace.")
assert(not model:FindFirstChild(RUNTIME_NAME, true), "AeroRuntime already exists. Undo the previous setup before rerunning.")

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function vector(values, label)
	assert(type(values) == "table" and #values == 3, label .. " must have three numbers.")
	for _, n in ipairs(values) do
		assert(finite(n), label .. " contains an invalid number.")
	end
	return Vector3.new(values[1], values[2], values[3])
end

local function validName(name)
	return type(name) == "string" and #name > 0 and #name <= 120
end

local DATA = HttpService:JSONDecode(MANIFEST_JSON)
assert(type(DATA) == "table" and DATA.modelName == "Aero House", "Use the packaged Aero House setup file.")
assert(type(DATA.version) == "string" or finite(DATA.version), "Invalid manifest version.")
assert(type(DATA.colliders) == "table" and #DATA.colliders > 0, "Missing collision metadata.")
assert(type(DATA.lights) == "table" and #DATA.lights <= 5, "Invalid local-light metadata.")

-- Validate every generated specification before changing the selected model.
local colliderSpecs, lightSpecs = {}, {}
local names = {}
for index, entry in ipairs(DATA.colliders) do
	assert(validName(entry.name) and not names[entry.name], "Missing or duplicate collider name.")
	names[entry.name] = true
	local size = vector(entry.size, "Collider size " .. index)
	assert(math.min(size.X, size.Y, size.Z) >= 0.01, "Collider size is too small.")
	colliderSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "Collider position " .. index),
		size = size,
		rotation = vector(entry.rotation, "Collider rotation " .. index),
	}
end
for index, entry in ipairs(DATA.lights) do
	assert(validName(entry.name) and not names[entry.name], "Missing or duplicate local-light name.")
	names[entry.name] = true
	local color = vector(entry.color, "Light color " .. index)
	assert(math.min(color.X, color.Y, color.Z) >= 0 and math.max(color.X, color.Y, color.Z) <= 1,
		"Light colors must be in the range 0 to 1.")
	assert(finite(entry.range) and entry.range > 0 and entry.range <= 60, "Invalid light range.")
	assert(finite(entry.brightness) and entry.brightness >= 0 and entry.brightness <= 10, "Invalid light brightness.")
	lightSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "Light position " .. index),
		color = Color3.new(color.X, color.Y, color.Z),
		range = entry.range,
		brightness = entry.brightness,
	}
end

local markerNames = {
	Aero_Anchor_Entry = true,
	Aero_Anchor_RearRight = true,
	Aero_Anchor_RearLeft = true,
}
local markers, visuals, baseline = {}, {}, {}
local originalParent, originalName = model.Parent, model.Name
local originalPivot, originalPrimaryPart = model:GetPivot(), model.PrimaryPart
local previousVersion = model:GetAttribute("AeroSetupVersion")
local previousManifest = model:GetAttribute("AeroSetupManifest")
local previousAuthoredFrame = model:GetAttribute("AeroAuthoredFrame")
assert(previousVersion == nil and previousManifest == nil and previousAuthoredFrame == nil,
	"This house already has setup metadata. Undo the previous setup before rerunning.")

for _, instance in ipairs(model:GetDescendants()) do
	assert(not instance:IsA("LuaSourceContainer") and not instance:IsA("Humanoid"),
		"The selection contains a script or character. Select only the untouched house import.")
	local snapshot = { Parent = instance.Parent, Name = instance.Name }
	baseline[instance] = snapshot
	if instance:IsA("BasePart") then
		assert(instance:IsA("MeshPart") and string.match(instance.Name, "^Aero_"),
			"The selection contains a part outside the house export. Select only the intact import.")
		table.insert(visuals, instance)
		for _, property in ipairs({ "CFrame", "Size", "Anchored", "CanCollide", "CanTouch", "CanQuery",
			"Transparency", "CastShadow", "RenderFidelity", "CollisionFidelity", "MeshId", "TextureID" }) do
			snapshot[property] = instance[property]
		end
	end
	if markerNames[instance.Name] then
		assert(instance:IsA("MeshPart") and not markers[instance.Name], "The three anchors must be unique MeshParts.")
		markers[instance.Name] = instance
	end
end
assert(#visuals > 3, "The selected Model is not the complete Aero House import.")
for name in pairs(markerNames) do
	assert(markers[name], "Missing " .. name .. ". Keep all three anchors and original mesh names during import.")
end

-- The front of the authored house is Roblox +Z. Derive the import frame from
-- real mesh centers, not the model pivot; Studio may rotate/recenter that pivot.
local entry = markers.Aero_Anchor_Entry.Position
local rearRight = markers.Aero_Anchor_RearRight.Position
local rearLeft = markers.Aero_Anchor_RearLeft.Position
local rearSpan = rearRight - rearLeft
local frontSpan = entry - (rearRight + rearLeft) * 0.5
assert(rearSpan.Magnitude > 0.01 and frontSpan.Magnitude > 0.01, "The import anchors overlap.")
local right = rearSpan.Unit
local forwardComponent = frontSpan - right * frontSpan:Dot(right)
assert(forwardComponent.Magnitude > 0.01, "The import anchors are collinear.")
local front = forwardComponent.Unit
local up = front:Cross(right).Unit
front = right:Cross(up).Unit
local scale = rearSpan.Magnitude / 80
local depthScale = forwardComponent.Magnitude / 78
assert(math.abs(scale - 1) <= 0.01,
	"Import scale is incorrect. Use the documented stud scale; this setup does not resize your model.")
assert(math.abs(depthScale / scale - 1) <= 0.01 and math.abs(frontSpan:Dot(right)) <= 0.78 * scale,
	"The house has uneven scaling or distorted anchors. Reimport with the documented uniform scale.")
assert(up:Dot(Vector3.yAxis) >= 0.999,
	"Keep the house upright. Whole-house translation and yaw rotation are supported.")
local origin = entry - up * (2 * scale) - front * (42 * scale)
local frame = CFrame.fromMatrix(origin, right, up, front)

-- If present, marker dimensions also detect vertical-only scaling, which three
-- coplanar marker centers cannot measure. The exporter uses identical anchors.
if DATA.anchorSizeRoblox then
	local anchorSize = vector(DATA.anchorSizeRoblox, "Authored anchor size")
	assert(math.min(anchorSize.X, anchorSize.Y, anchorSize.Z) > 0, "Invalid authored anchor size.")
	for name, marker in pairs(markers) do
		local localSize = marker.Size
		assert(math.abs(localSize.X / (anchorSize.X * scale) - 1) <= 0.01
			and math.abs(localSize.Y / (anchorSize.Y * scale) - 1) <= 0.01
			and math.abs(localSize.Z / (anchorSize.Z * scale) - 1) <= 0.01,
			name .. " has uneven scaling. Reimport the untouched house.")
	end
end

local function assertFreshBaseline()
	assert(model.Parent == originalParent and model.Name == originalName
		and model:GetPivot() == originalPivot and model.PrimaryPart == originalPrimaryPart,
		"The selected model changed during setup. Rerun against its current state.")
	assert(model:GetAttribute("AeroSetupVersion") == previousVersion
		and model:GetAttribute("AeroSetupManifest") == previousManifest
		and model:GetAttribute("AeroAuthoredFrame") == previousAuthoredFrame,
		"Setup metadata changed during preparation. Rerun against the current model.")
	local count = 0
	for _, instance in ipairs(model:GetDescendants()) do
		local snapshot = baseline[instance]
		assert(snapshot, "An instance was added during preparation. Rerun against the current model.")
		for property, value in pairs(snapshot) do
			assert(instance[property] == value, instance.Name .. " changed during preparation. Rerun setup.")
		end
		count += 1
	end
	local originalCount = 0
	for _ in pairs(baseline) do originalCount += 1 end
	assert(count == originalCount, "An instance was removed during preparation. Rerun setup.")
	local currentSelection = Selection:Get()
	assert(#currentSelection == 1 and currentSelection[1] == model, "Selection changed during setup.")
end

-- Studio MCP owns this undo recording.
local runtime
local changedVisuals = {}
local metadataWritten = false
local ok, problem = xpcall(function()
	-- Recheck inside the write, before touching any authoritative Studio data.
	assertFreshBaseline()
	runtime = Instance.new("Model")
	runtime.Name = RUNTIME_NAME
	runtime:SetAttribute("Owner", OWNER)
	runtime:SetAttribute("SetupVersion", tostring(DATA.version))
	runtime:SetAttribute("ImportScale", scale)
	runtime:SetAttribute("LocalLightsEnabled", ENABLE_LOCAL_LIGHTS)

	local function invisiblePart(name)
		local part = Instance.new("Part")
		part.Name = name
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part:SetAttribute("Owner", OWNER)
		return part
	end
	for _, spec in ipairs(colliderSpecs) do
		local part = invisiblePart(spec.name)
		part.Size = spec.size * scale
		part.CFrame = frame * CFrame.new(spec.position * scale)
			* CFrame.Angles(math.rad(spec.rotation.X), math.rad(spec.rotation.Y), math.rad(spec.rotation.Z))
		part.CanCollide = true
		part.CanQuery = true
		part.Parent = runtime
	end
	if ENABLE_LOCAL_LIGHTS then
		for _, spec in ipairs(lightSpecs) do
			local fixture = invisiblePart(spec.name)
			fixture.Size = Vector3.new(0.1, 0.1, 0.1) * scale
			fixture.CFrame = frame * CFrame.new(spec.position * scale)
			fixture.CanCollide = false
			fixture.CanQuery = false
			local light = Instance.new("PointLight")
			light.Name = "LocalLight"
			light.Color = spec.color
			light.Range = spec.range * scale
			light.Brightness = spec.brightness
			light.Shadows = false
			light.Parent = fixture
			fixture.Parent = runtime
		end
	end
	for _, part in ipairs(visuals) do
		table.insert(changedVisuals, part)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = true
		part.RenderFidelity = Enum.RenderFidelity.Automatic
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		if string.find(part.Name, "Glass", 1, true) then
			part.Transparency = 0.35
			part.CastShadow = false
		end
	end
	runtime.Parent = model
	metadataWritten = true
	model:SetAttribute("AeroSetupVersion", tostring(DATA.version))
	model:SetAttribute("AeroSetupManifest", MANIFEST_JSON)
	model:SetAttribute("AeroAuthoredFrame", frame)
end, debug.traceback)

if not ok then
	-- Cancel discards the recording; explicitly restore only properties this
	-- operation touched. Never delete or replace a pre-existing Studio instance.
	local restored, restoreProblem = pcall(function()
		if runtime then runtime:Destroy() end
		for _, part in ipairs(changedVisuals) do
			for _, property in ipairs({ "Anchored", "CanCollide", "CanTouch", "CanQuery",
				"Transparency", "CastShadow", "RenderFidelity", "CollisionFidelity" }) do
				part[property] = baseline[part][property]
			end
		end
		if metadataWritten then
			model:SetAttribute("AeroSetupVersion", previousVersion)
			model:SetAttribute("AeroSetupManifest", previousManifest)
			model:SetAttribute("AeroAuthoredFrame", previousAuthoredFrame)
		end
	end)
	assert(restored, tostring(problem) .. "\nRollback needs attention: " .. tostring(restoreProblem))
	error(problem)
end

print(string.format("Aero House ready: %d anchored visual meshes, %d simple colliders, %d local lights. Gravity unchanged (%g).",
	#visuals, #colliderSpecs, ENABLE_LOCAL_LIGHTS and #lightSpecs or 0, workspace.Gravity))
print("Test the house in Play mode after adding your normal player spawn. Undo once to remove this setup.")
