-- Generated offline; builds only the five named ServerStorage templates after all mesh imports succeed.
local HS = game:GetService("HttpService")
local SS = game:GetService("ServerStorage")
local AS = game:GetService("AssetService")
local DATA = HS:JSONDecode([==[{"rig":{"version":1,"height":7.6,"metresPerStud":0.28,"axes":"Blender(x,y,z)->Roblox(x,z,-y)","primaryPart":"HumanoidRootPart","bones":[{"bone":"Hips","part":"Hips","chunks":[50000],"center":[-0.0077,4.8934,-0.0669],"size":[0.9547,1.1784,0.7865],"invisible":false},{"bone":"Spine02","part":"Spine02","chunks":[50001],"center":[-0.0032,5.5184,-0.0552],"size":[0.8124,0.7688,0.7171],"invisible":false},{"bone":"Spine01","part":"Spine01","chunks":[50002],"center":[0.0011,5.928,-0.1014],"size":[0.8573,0.9168,0.8218],"invisible":false},{"bone":"Spine","part":"Spine","chunks":[],"center":[0.019,6.0895,-0.2008],"size":[0.05,0.05,0.05],"invisible":true},{"bone":"neck","part":"neck","chunks":[],"center":[0.011,6.3754,-0.2022],"size":[0.05,0.05,0.05],"invisible":true},{"bone":"Head","part":"Head","chunks":[50003],"center":[-0.0155,7.0065,-0.0125],"size":[0.7817,1.1869,0.9722],"invisible":false},{"bone":"head_end","part":"head_end","chunks":[],"center":[0.0858,7.5075,-0.0571],"size":[0.05,0.05,0.05],"mergedInto":"Head","invisible":true},{"bone":"headfront","part":"headfront","chunks":[],"center":[0.0026,6.679,0.0917],"size":[0.05,0.05,0.05],"mergedInto":"Head","invisible":true},{"bone":"LeftShoulder","part":"LeftShoulder","chunks":[50004],"center":[0.294,6.3216,-0.1554],"size":[0.6919,0.749,0.7124],"invisible":false},{"bone":"LeftArm","part":"LeftArm","chunks":[50005],"center":[0.6941,5.8006,-0.1972],"size":[0.7094,1.3403,0.4752],"invisible":false},{"bone":"LeftForeArm","part":"LeftForeArm","chunks":[50006],"center":[1.0965,4.8726,-0.1956],"size":[0.6334,1.0845,0.3747],"invisible":false},{"bone":"LeftHand","part":"LeftHand","chunks":[50007],"center":[1.4336,4.0942,-0.1164],"size":[0.4275,0.7399,0.3698],"invisible":false},{"bone":"RightShoulder","part":"RightShoulder","chunks":[50008],"center":[-0.251,6.3041,-0.1517],"size":[0.7898,0.7853,0.7212],"invisible":false},{"bone":"RightArm","part":"RightArm","chunks":[50009],"center":[-0.683,5.8522,-0.1616],"size":[0.7271,1.2928,0.5682],"invisible":false},{"bone":"RightForeArm","part":"RightForeArm","chunks":[50010],"center":[-1.0795,4.9015,-0.1938],"size":[0.6623,1.0855,0.3793],"invisible":false},{"bone":"RightHand","part":"RightHand","chunks":[50011],"center":[-1.4109,4.1569,-0.1149],"size":[0.478,0.7826,0.3693],"invisible":false},{"bone":"LeftUpLeg","part":"LeftUpLeg","chunks":[50012],"center":[0.2331,3.6052,-0.0926],"size":[0.4599,1.985,0.6115],"invisible":false},{"bone":"LeftLeg","part":"LeftLeg","chunks":[50013],"center":[0.3829,1.607,-0.2407],"size":[0.3669,2.5224,0.5187],"invisible":false},{"bone":"LeftFoot","part":"LeftFoot","chunks":[50014],"center":[0.4587,0.2893,0.0155],"size":[0.3957,0.5787,0.9859],"invisible":false},{"bone":"LeftToeBase","part":"LeftToeBase","chunks":[],"center":[0.4845,0.1635,0.0581],"size":[0.05,0.05,0.05],"mergedInto":"LeftFoot","invisible":true},{"bone":"RightUpLeg","part":"RightUpLeg","chunks":[50015],"center":[-0.2213,3.5841,-0.0914],"size":[0.5213,2.127,0.6108],"invisible":false},{"bone":"RightLeg","part":"RightLeg","chunks":[50016],"center":[-0.4004,1.5352,-0.2347],"size":[0.3619,2.5742,0.5269],"invisible":false},{"bone":"RightFoot","part":"RightFoot","chunks":[50017],"center":[-0.4771,0.3055,0.017],"size":[0.388,0.5981,0.9693],"invisible":false},{"bone":"RightToeBase","part":"RightToeBase","chunks":[],"center":[-0.4455,0.173,0.1654],"size":[0.05,0.05,0.05],"mergedInto":"RightFoot","invisible":true}],"joints":[{"name":"Hips","Part0":"HumanoidRootPart","Part1":"Hips","C0":[0,0,0,1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0],"C1":[0.043,-0.1795,-0.1263,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"Spine02","Part0":"Hips","Part1":"Spine02","C0":[0.0376,0.2745,-0.1288,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0331,-0.3505,-0.1405,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"Spine01","Part0":"Spine02","Part1":"Spine01","C0":[0.0277,0.1034,-0.143,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0234,-0.3062,-0.0968,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"Spine","Part0":"Spine01","Part1":"Spine","C0":[0.0179,0.1615,-0.0994,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"neck","Part0":"Spine","Part1":"neck","C0":[-0.008,0.2859,-0.0014,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"Head","Part0":"neck","Part1":"Head","C0":[-0.0084,0.3036,-0.0014,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0181,-0.3275,-0.1911,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"head_end","Part0":"Head","Part1":"head_end","C0":[0.1013,0.501,-0.0446,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"headfront","Part0":"Head","Part1":"headfront","C0":[0.0181,-0.3275,0.1042,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftShoulder","Part0":"Spine","Part1":"LeftShoulder","C0":[0.1017,0.2359,-0.0058,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[-0.1733,0.0038,-0.0512,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftArm","Part0":"LeftShoulder","Part1":"LeftArm","C0":[0.2654,0.0038,-0.04,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[-0.1347,0.5248,0.0018,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftForeArm","Part0":"LeftArm","Part1":"LeftForeArm","C0":[0.2419,-0.4578,-0.0677,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[-0.1605,0.4702,-0.0693,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftHand","Part0":"LeftForeArm","Part1":"LeftHand","C0":[0.2326,-0.3978,0.0052,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[-0.1045,0.3806,-0.074,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightShoulder","Part0":"Spine","Part1":"RightShoulder","C0":[-0.1178,0.2032,0.0039,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.1522,-0.0114,-0.0452,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightArm","Part0":"RightShoulder","Part1":"RightArm","C0":[-0.2869,-0.0114,-0.0435,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.1451,0.4405,-0.0336,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightForeArm","Part0":"RightArm","Part1":"RightForeArm","C0":[-0.166,-0.5094,-0.0749,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.2305,0.4413,-0.0427,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightHand","Part0":"RightForeArm","Part1":"RightHand","C0":[-0.1953,-0.4267,0.0574,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.1361,0.3179,-0.0215,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftUpLeg","Part0":"Hips","Part1":"LeftUpLeg","C0":[0.2645,-0.5843,-0.1263,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0237,0.7039,-0.1006,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftLeg","Part0":"LeftUpLeg","Part1":"LeftLeg","C0":[0.1134,-0.9155,-0.0194,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[-0.0364,1.0827,0.1287,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftFoot","Part0":"LeftLeg","Part1":"LeftFoot","C0":[0.0766,-1.0465,-0.1321,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0008,0.2712,-0.3883,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"LeftToeBase","Part0":"LeftFoot","Part1":"LeftToeBase","C0":[0.0258,-0.1258,0.0426,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightUpLeg","Part0":"Hips","Part1":"RightUpLeg","C0":[-0.1898,-0.5843,-0.1263,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0238,0.725,-0.1018,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightLeg","Part0":"RightUpLeg","Part1":"RightLeg","C0":[-0.0743,-0.8942,-0.022,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.1048,1.1547,0.1213,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightFoot","Part0":"RightLeg","Part1":"RightFoot","C0":[-0.0064,-0.9745,0.0187,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0.0703,0.2552,-0.233,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]},{"name":"RightToeBase","Part0":"RightFoot","Part1":"RightToeBase","C0":[0.0316,-0.1325,0.1484,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0],"C1":[0,0,0,-1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,-1.0]}],"attachments":[{"name":"Torch","chunks":[50018],"center":[-1.4109,4.1248,-0.0435],"size":[0.1857,0.2071,0.8571],"Part0":"RightHand","kind":"WeldConstraint"},{"name":"Lens","chunks":[50019],"center":[-1.4109,4.114,0.628],"size":[0.2429,0.2429,0.5357],"rotation":[-1,0,0,0,1,0,0,0,-1],"Part0":"Torch","kind":"WeldConstraint","light":{"name":"TicketBeam","class":"SpotLight","face":"Front","color":[1,0,0],"brightness":2.5,"range":28,"angle":32,"enabled":false}}],"templates":{"FilmReel":{"primaryPart":"Canister","parts":[{"name":"Canister","chunks":[50020],"center":[-0.0068,0.3245,0.0074],"size":[2.0075,0.765,1.3781]}]},"Fuse":{"primaryPart":"Glass","parts":[{"name":"Glass","chunks":[50021],"center":[0,0.1786,0],"size":[0.0571,0.2571,0.0571]},{"name":"CapBottom","chunks":[50022],"center":[0,0.025,0],"size":[0.0643,0.05,0.0643]},{"name":"CapTop","chunks":[50023],"center":[0,0.3321,0],"size":[0.0643,0.05,0.0643]},{"name":"Filament","chunks":[50024],"center":[0,0.1786,0],"size":[0.05,0.2786,0.05]}]},"BatteryPack":{"primaryPart":"Case","parts":[{"name":"Case","chunks":[50025],"center":[0,0.2107,0],"size":[0.3214,0.4214,0.1857]},{"name":"RedStripe","chunks":[50026],"center":[0,0.2464,0],"size":[0.3286,0.0643,0.1929]},{"name":"BatteryLabel","chunks":[50027],"center":[0,0.125,0.0957],"size":[0.1964,0.1071,0.05]},{"name":"ContactPositive","chunks":[50028],"center":[-0.075,0.4286,0],"size":[0.0571,0.05,0.0571]},{"name":"ContactNegative","chunks":[50029],"center":[0.075,0.4286,0],"size":[0.0571,0.05,0.0571]}]},"Note":{"primaryPart":"Paper","parts":[{"name":"CrumpledSheet","chunks":[50030],"center":[0,0.0039,0],"size":[0.7506,0.05,0.5357]},{"name":"Paper","chunks":[50031],"center":[0,0.0107,0],"size":[0.6714,0.05,0.4464]}],"pivotOffset":[0,-0.1,0],"surfaceGui":{"part":"Paper","face":"Top","name":"NoteText","textLabel":"Text"}}},"root":{"name":"HumanoidRootPart","center":[0.0353,4.7139,-0.1932],"size":[2,2,1],"rotation":[-1,0,0,0,1,0,0,0,-1],"invisible":true,"anchored":true,"front":"Roblox +Z in authored world; template Root.LookVector matches character face"},"jointAxes":"character aligned: local Y up, local -Z character forward; native bone motion conjugated into this frame"},"chunks":{"50000":{"id":50000,"group":50000,"material":"L4T_Usher","tris":1057,"verts":1222,"center":[-0.0077,4.8934,-0.0669],"size":[0.9547,1.1784,0.7865],"name":"Hips","template":"Usher","h":"a1b1891249ded2e84a447f24450534d861f86fa753677339bdaf9b91e6fffbda","asset":"rbxassetid://90925657684007"},"50001":{"id":50001,"group":50001,"material":"L4T_Usher","tris":312,"verts":321,"center":[-0.0032,5.5184,-0.0552],"size":[0.8124,0.7688,0.7171],"name":"Spine02","template":"Usher","h":"02c690fedab288477946d9a1704efe5c986e257c2d25ac4058510e300f1bf007","asset":"rbxassetid://140438455524462"},"50002":{"id":50002,"group":50002,"material":"L4T_Usher","tris":434,"verts":448,"center":[0.0011,5.928,-0.1014],"size":[0.8573,0.9168,0.8218],"name":"Spine01","template":"Usher","h":"33363369bc8ae34d856cf81b60a8504abbb0ae6121f6c51e65256032f1084116","asset":"rbxassetid://80231020006845"},"50003":{"id":50003,"group":50003,"material":"L4T_Usher","tris":1148,"verts":1289,"center":[-0.0155,7.0065,-0.0125],"size":[0.7817,1.1869,0.9722],"name":"Head","template":"Usher","h":"2a64bef8e2afd7633603b7a1cee0d1be3f8e13eccf0fa640590992607c78af0e","asset":"rbxassetid://115955414206415"},"50004":{"id":50004,"group":50004,"material":"L4T_Usher","tris":434,"verts":492,"center":[0.294,6.3216,-0.1554],"size":[0.6919,0.749,0.7124],"name":"LeftShoulder","template":"Usher","h":"d641d9ad1060e71d961d5507f47970e28582d74b5f5b0812c8553bea022b37e7","asset":"rbxassetid://79354734151859"},"50005":{"id":50005,"group":50005,"material":"L4T_Usher","tris":300,"verts":288,"center":[0.6941,5.8006,-0.1972],"size":[0.7094,1.3403,0.4752],"name":"LeftArm","template":"Usher","h":"000620be91c5b3c7c1f662e7f19db997279206346d7f0153d47b45b63f76743e","asset":"rbxassetid://84688394570690"},"50006":{"id":50006,"group":50006,"material":"L4T_Usher","tris":508,"verts":548,"center":[1.0965,4.8726,-0.1956],"size":[0.6334,1.0845,0.3747],"name":"LeftForeArm","template":"Usher","h":"37cc3848dce07452d60dafce1f6d969235c6c00d71dd012082dab29706b46452","asset":"rbxassetid://136717827057399"},"50007":{"id":50007,"group":50007,"material":"L4T_Usher","tris":452,"verts":492,"center":[1.4336,4.0942,-0.1164],"size":[0.4275,0.7399,0.3698],"name":"LeftHand","template":"Usher","h":"c0b7029643961061194c8c3f943303f6d7c153fb842ffdc6bc386a1051f52a7b","asset":"rbxassetid://106280396694846"},"50008":{"id":50008,"group":50008,"material":"L4T_Usher","tris":376,"verts":388,"center":[-0.251,6.3041,-0.1517],"size":[0.7898,0.7853,0.7212],"name":"RightShoulder","template":"Usher","h":"15706b38edd2f163eecce8a03652daafb843a5bc6b8eb427387e0f62c402120d","asset":"rbxassetid://88280382243528"},"50009":{"id":50009,"group":50009,"material":"L4T_Usher","tris":275,"verts":269,"center":[-0.683,5.8522,-0.1616],"size":[0.7271,1.2928,0.5682],"name":"RightArm","template":"Usher","h":"560910a31b541fd141f00ae6be204e214178a3d3c17fe3095d99afa8ce006fb2","asset":"rbxassetid://111069451631790"},"50010":{"id":50010,"group":50010,"material":"L4T_Usher","tris":506,"verts":547,"center":[-1.0795,4.9015,-0.1938],"size":[0.6623,1.0855,0.3793],"name":"RightForeArm","template":"Usher","h":"10201250a9af2081c3f67d6d8dcd80c4ad7921c3c8eec5d6324a99a87181d5d0","asset":"rbxassetid://84592470440293"},"50011":{"id":50011,"group":50011,"material":"L4T_Usher","tris":503,"verts":585,"center":[-1.4109,4.1569,-0.1149],"size":[0.478,0.7826,0.3693],"name":"RightHand","template":"Usher","h":"ac6d7c5cbb5198b75a11fb1e0c4b0823e14af3c6c12cd698fae71e826a93f46b","asset":"rbxassetid://75047761296378"},"50012":{"id":50012,"group":50012,"material":"L4T_Usher","tris":253,"verts":224,"center":[0.2331,3.6052,-0.0926],"size":[0.4599,1.985,0.6115],"name":"LeftUpLeg","template":"Usher","h":"81c6a6ca29a351f400ee903d47a3e7039deed37b1fade819cfd77158a55fb2db","asset":"rbxassetid://135980025581553"},"50013":{"id":50013,"group":50013,"material":"L4T_Usher","tris":288,"verts":274,"center":[0.3829,1.607,-0.2407],"size":[0.3669,2.5224,0.5187],"name":"LeftLeg","template":"Usher","h":"4b49a0be0262f17d917fc0014b07ad4c7ee19c5fc60723fc34465f4076e02c06","asset":"rbxassetid://74773970093555"},"50014":{"id":50014,"group":50014,"material":"L4T_Usher","tris":371,"verts":395,"center":[0.4587,0.2893,0.0155],"size":[0.3957,0.5787,0.9859],"name":"LeftFoot","template":"Usher","h":"02b0d891ad3ef289bd5e741f6a1de32b2fc2d48f9320c330323ea425918b0625","asset":"rbxassetid://94184672727231"},"50015":{"id":50015,"group":50015,"material":"L4T_Usher","tris":294,"verts":266,"center":[-0.2213,3.5841,-0.0914],"size":[0.5213,2.127,0.6108],"name":"RightUpLeg","template":"Usher","h":"4022c85002d7ea43db54b4278e4ceb4aa13eab4da4c0f7aadff9e31a3339478d","asset":"rbxassetid://75758597918287"},"50016":{"id":50016,"group":50016,"material":"L4T_Usher","tris":289,"verts":272,"center":[-0.4004,1.5352,-0.2347],"size":[0.3619,2.5742,0.5269],"name":"RightLeg","template":"Usher","h":"77381e9a38a73f25456635d2122e4f05e71a2d190269d209da989308d03f3ede","asset":"rbxassetid://115105753394378"},"50017":{"id":50017,"group":50017,"material":"L4T_Usher","tris":371,"verts":379,"center":[-0.4771,0.3055,0.017],"size":[0.388,0.5981,0.9693],"name":"RightFoot","template":"Usher","h":"03b5a0345511d38a3825864e75f9c1f624e0b765419d101b3a88300abba2bb7a","asset":"rbxassetid://102887808330103"},"50018":{"id":50018,"group":50018,"material":"L4T_TorchBlack","tris":568,"verts":296,"center":[-1.4109,4.1248,-0.0435],"size":[0.1857,0.2071,0.8571],"name":"Torch","template":"Usher","h":"46d409cd11c27f4d4423bc91770c60738c9f89b6e7252c775a70d23ef8e53341","asset":"rbxassetid://85051810372389"},"50019":{"id":50019,"group":50019,"material":"L4T_TicketRed","tris":92,"verts":48,"center":[-1.4109,4.114,0.628],"size":[0.2429,0.2429,0.5357],"name":"Lens","template":"Usher","h":"aa9f4c9252e182e622db8dcd1e5e863ad03e8bd720acded03f9873a792403dec","asset":"rbxassetid://93887127828506"},"50020":{"id":50020,"group":50020,"material":"L4T_FilmReel","tris":1477,"verts":1798,"center":[-0.0068,0.3245,0.0074],"size":[2.0075,0.765,1.3781],"name":"Canister","template":"FilmReel","h":"246ba4bd0ffc697377fd7dd783b52caf57da17af451cda5743eb6a3a08ba2091","asset":"rbxassetid://102759614623819"},"50021":{"id":50021,"group":50021,"material":"L4T_FuseGlass","tris":60,"verts":32,"center":[0,0.1786,0],"size":[0.0571,0.2571,0.0571],"name":"Glass","template":"Fuse","h":"1c73d67872db490cbf69f250b31b35fa4e60655d7228ac089bfa34b58770b7db","asset":"rbxassetid://79884368795389"},"50022":{"id":50022,"group":50022,"material":"L4T_Brass","tris":60,"verts":32,"center":[0,0.025,0],"size":[0.0643,0.05,0.0643],"name":"CapBottom","template":"Fuse","h":"e7697abebd2ef0a850e42ddb1750e9e8b1768a9fa6d1b7b864380d67adbefdd7","asset":"rbxassetid://109797378642132"},"50023":{"id":50023,"group":50023,"material":"L4T_Brass","tris":60,"verts":32,"center":[0,0.3321,0],"size":[0.0643,0.05,0.0643],"name":"CapTop","template":"Fuse","h":"fdeac25d26be6ce3a50aa6dbd1afcbef4c6d910c8d098211c9cf1fb683b82481","asset":"rbxassetid://112805172617202"},"50024":{"id":50024,"group":50024,"material":"L4T_FuseWire","tris":28,"verts":16,"center":[0,0.1786,0],"size":[0.05,0.2786,0.05],"name":"Filament","template":"Fuse","h":"01caf00a81c9962468454fe8d5c55258bbea1d65e631d1ae40583ba03b8e8b30","asset":"rbxassetid://107686908670222"},"50025":{"id":50025,"group":50025,"material":"L4T_BatteryBlack","tris":108,"verts":56,"center":[0,0.2107,0],"size":[0.3214,0.4214,0.1857],"name":"Case","template":"BatteryPack","h":"3e94c31dca1577a569049a20426c628d048d77d392c6035b90787a8eb090397f","asset":"rbxassetid://87145326377562"},"50026":{"id":50026,"group":50026,"material":"L4T_BatteryStripe","tris":108,"verts":56,"center":[0,0.2464,0],"size":[0.3286,0.0643,0.1929],"name":"RedStripe","template":"BatteryPack","h":"590d1aa82ac8f6c8dec269f9180d4e0aa8ffdedc6c6486bce608b870bf09c8eb","asset":"rbxassetid://132004923315891"},"50027":{"id":50027,"group":50027,"material":"L4T_BatteryLabel","tris":108,"verts":44,"center":[0,0.125,0.0957],"size":[0.1964,0.1071,0.05],"name":"BatteryLabel","template":"BatteryPack","h":"91ab588bab935cdd3edc46c56fc5342ecbfdf63973bf7a673983e38ec38d86d5","asset":"rbxassetid://93609476158483"},"50028":{"id":50028,"group":50028,"material":"L4T_Brass","tris":60,"verts":32,"center":[-0.075,0.4286,0],"size":[0.0571,0.05,0.0571],"name":"ContactPositive","template":"BatteryPack","h":"3256c4593a9f15a2eee062a505894625b315f9459a6f0174b6b180fb30e5fa15","asset":"rbxassetid://109294464005458"},"50029":{"id":50029,"group":50029,"material":"L4T_Brass","tris":60,"verts":32,"center":[0.075,0.4286,0],"size":[0.0571,0.05,0.0571],"name":"ContactNegative","template":"BatteryPack","h":"72817aca9bc90a6a2d2a4f8a17489d0a9e3da29ade00a0d024101b083d7dea3e","asset":"rbxassetid://89332400243417"},"50030":{"id":50030,"group":50030,"material":"L4T_NotePaper","tris":248,"verts":126,"center":[0,0.0039,0],"size":[0.7506,0.05,0.5357],"name":"CrumpledSheet","template":"Note","h":"3f334ba4ede8faad9d04353b6d693d0907baf8cebb49c704d83bdb580e0fab0d","asset":"rbxassetid://78361505192390"},"50031":{"id":50031,"group":50031,"material":"L4T_NotePaper","tris":12,"verts":8,"center":[0,0.0107,0],"size":[0.6714,0.05,0.4464],"name":"Paper","template":"Note","h":"8ba77243a2397d4f094cb5975a1e27ae9fd1e1e72344107ed2c2b3a91d28c260","asset":"rbxassetid://86962750045856"}},"materials":{"L4T_Usher":{"color":[1.0,1.0,1.0],"material":"SmoothPlastic","alpha":1.0,"maps":{"ColorMap":"rbxassetid://97338223810946","NormalMap":"rbxassetid://114065818026755","RoughnessMap":"rbxassetid://126111315148406","MetalnessMap":"rbxassetid://94962770302104"}},"L4T_TorchBlack":{"color":[0.07450980392156863,0.07450980392156863,0.08627450980392157],"material":"SmoothPlastic","alpha":1.0,"maps":{}},"L4T_TicketRed":{"color":[0.8431372549019608,0.011764705882352941,0.027450980392156862],"material":"Neon","alpha":1.0,"maps":{}},"L4T_FilmReel":{"color":[1.0,1.0,1.0],"material":"SmoothPlastic","alpha":1.0,"maps":{"ColorMap":"rbxassetid://131286430042831","NormalMap":"rbxassetid://86038096367040","RoughnessMap":"rbxassetid://140629859215174","MetalnessMap":"rbxassetid://83687982920687"}},"L4T_Brass":{"color":[0.6666666666666666,0.49411764705882355,0.17647058823529413],"material":"Metal","alpha":1.0,"maps":{}},"L4T_FuseGlass":{"color":[0.792156862745098,0.8705882352941177,0.8784313725490196],"material":"Glass","alpha":0.28,"maps":{}},"L4T_FuseWire":{"color":[0.36470588235294116,0.32941176470588235,0.27058823529411763],"material":"Metal","alpha":1.0,"maps":{}},"L4T_BatteryBlack":{"color":[0.10980392156862745,0.11764705882352941,0.12941176470588237],"material":"SmoothPlastic","alpha":1.0,"maps":{}},"L4T_BatteryStripe":{"color":[0.592156862745098,0.03529411764705882,0.047058823529411764],"material":"SmoothPlastic","alpha":1.0,"maps":{}},"L4T_BatteryLabel":{"color":[0.7450980392156863,0.6823529411764706,0.5254901960784314],"material":"SmoothPlastic","alpha":1.0,"maps":{}},"L4T_NotePaper":{"color":[0.8745098039215686,0.8352941176470589,0.7137254901960784],"material":"SmoothPlastic","alpha":1.0,"maps":{}}}}]==])
local function vec(a) return Vector3.new(a[1], a[2], a[3]) end
local function cf(a) return CFrame.new(table.unpack(a)) end
local function partFrame(entry)
    local r = entry.rotation or {1,0,0,0,1,0,0,0,1}
    return CFrame.new(entry.center[1],entry.center[2],entry.center[3],table.unpack(r))
end
local function physics(part, anchored)
    part.Anchored = anchored == true
    part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
    part.Massless = true
end
local staging = Instance.new("Folder")
staging.Name = "Level 4 Templates Build"
local made = {}
local function mesh(entry, model)
    assert(#entry.chunks == 1, "each exported part must contain exactly one shared-material chunk")
    local chunk = assert(DATA.chunks[tostring(entry.chunks[1])], "missing chunk")
    local ok, part = pcall(AS.CreateMeshPartAsync, AS, Content.fromUri(chunk.asset),
        {CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Automatic})
    assert(ok and part, "mesh import failed: " .. entry.name .. ": " .. tostring(part))
    part.Name = entry.name
    part.Size = vec(chunk.size)
    part.CFrame = partFrame(entry)
    part.DoubleSided = true
    physics(part, false)
    local material = assert(DATA.materials[chunk.material], "missing material")
    part.Material = Enum.Material[material.material]
    part.Color = Color3.new(table.unpack(material.color))
    part.Transparency = 1 - material.alpha
    if next(material.maps) then
        part.Color = Color3.new(1,1,1)
        local sa = Instance.new("SurfaceAppearance")
        for property, asset in pairs(material.maps) do sa[property] = asset end
        sa.Parent = part
    end
    part.Parent = model
    return part
end
local function weld(a, b)
    local joint = Instance.new("WeldConstraint")
    joint.Name = b.Name .. "Weld"
    joint.Part0, joint.Part1 = a, b
    joint.Parent = b
end
local ok, result = pcall(function()
    local rig = DATA.rig
    local model = Instance.new("Model")
    model.Name = "Usher"
    model:SetAttribute("UsherHeight", 7.6)
    model.Parent = staging
    made.Usher = model
    local root = Instance.new("Part")
    root.Name = "HumanoidRootPart"
    root.Size, root.CFrame = vec(rig.root.size), partFrame(rig.root)
    root.Transparency, root.CastShadow = 1, false
    physics(root, true)
    root.Parent = model
    model.PrimaryPart = root
    local parts = {HumanoidRootPart = root}
    for _, entry in ipairs(rig.bones) do
        local part
        if entry.invisible then
            part = Instance.new("Part")
            part.Name = entry.part
            part.Size, part.CFrame = vec(entry.size), CFrame.new(vec(entry.center))
            part.Transparency, part.CastShadow = 1, false
            physics(part, false)
            part.Parent = model
        else
            entry.name = entry.part
            part = mesh(entry, model)
        end
        part:SetAttribute("UsherBone", entry.bone)
        if entry.mergedInto then part:SetAttribute("MergedInto", entry.mergedInto) end
        parts[entry.bone] = part
    end
    for _, entry in ipairs(rig.joints) do
        local joint = Instance.new("Motor6D")
        joint.Name = entry.name
        joint.Part0, joint.Part1 = assert(parts[entry.Part0]), assert(parts[entry.Part1])
        joint.C0, joint.C1 = cf(entry.C0), cf(entry.C1)
        joint.Parent = joint.Part1
    end
    for _, entry in ipairs(rig.attachments) do
        local part = mesh(entry, model)
        parts[entry.name] = part
        weld(assert(parts[entry.Part0]), part)
        if entry.light then
            local light = Instance.new("SpotLight")
            light.Name = "TicketBeam"
            light.Face = Enum.NormalId.Front
            light.Color = Color3.new(1,0,0)
            light.Brightness, light.Range, light.Angle = entry.light.brightness, entry.light.range, entry.light.angle
            light.Enabled, light.Shadows = false, false
            light.Parent = part
        end
    end
    for name, template in pairs(rig.templates) do
        local item = Instance.new("Model")
        item.Name, item.Parent = name, staging
        made[name] = item
        local itemParts = {}
        for _, entry in ipairs(template.parts) do itemParts[entry.name] = mesh(entry, item) end
        local primary = assert(itemParts[template.primaryPart])
        item.PrimaryPart = primary
        primary.Anchored = true
        if template.pivotOffset then primary.PivotOffset = CFrame.new(vec(template.pivotOffset)) end
        for _, part in pairs(itemParts) do if part ~= primary then weld(primary, part) end end
        if template.surfaceGui then
            local gui = Instance.new("SurfaceGui")
            gui.Name = "NoteText"
            gui.Face = Enum.NormalId.Top
            gui.CanvasSize = Vector2.new(420,300)
            gui.LightInfluence = 0.6
            local text = Instance.new("TextLabel")
            text.Name = "Text"
            text.Size = UDim2.fromScale(1,1)
            text.BackgroundTransparency = 1
            text.Font = Enum.Font.PatrickHand
            text.TextColor3 = Color3.fromRGB(40,30,40)
            text.TextScaled, text.TextWrapped = true, true
            text.Text = ""
            text.Parent = gui
            gui.Parent = itemParts.Paper
        end
    end
    -- Every import succeeded. Preserve unrelated templates and replace only the explicitly owned names.
    local target = SS:FindFirstChild("Level 4 Templates")
    if target then assert(target:IsA("Folder"), "Level 4 Templates must be a Folder")
    else target = Instance.new("Folder"); target.Name = "Level 4 Templates"; target.Parent = SS end
    for _, name in ipairs({"Usher","FilmReel","Fuse","BatteryPack","Note"}) do
        local previous = target:FindFirstChild(name)
        if previous then previous:Destroy() end
        made[name].Parent = target
    end
    return "Level 4 Templates built: Usher (24 Motors), FilmReel, Fuse, BatteryPack, Note"
end)
staging:Destroy()
assert(ok, result)
return result
