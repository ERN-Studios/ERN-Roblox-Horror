-- Vesper Cathedral: optional, undoable Studio EDIT-MODE setup.
-- The packaged copy contains generated geometry metadata in DATA. This template
-- is not runnable until __CATHEDRAL_DATA__ is replaced during packaging.
-- Select exactly the imported cathedral Model, then paste the packaged script
-- into Studio's Command Bar. This changes only that selected model.
-- It normalizes the complete visual width to the authored stud scale while
-- preserving the model's current pivot position AND orientation. A tiny import
-- is therefore enlarged around its existing pivot, not moved to world origin.
-- It anchors the visual meshes, replaces only its own tagged setup folder,
-- disables visual collisions/touch events, and adds simple invisible colliders.
-- Optional local lights do not change the global Lighting service. No scripts,
-- save, publication, asset upload, or game-service modifications are performed.
-- Keep the imported hierarchy intact; do not independently rotate its pivot,
-- deform it, merge it with other models, or add extra meshes before setup.

local DATA = game:GetService("HttpService"):JSONDecode([=[{"dimensions":[108.0,82.55999994277954,168.0],"center":[0.0,38.22000002861023,3.0],"colliders":[{"name":"Vesper_01_Foundation_solid","position":[0.0,-1.56,3.0],"size":[108.0,3.0,168.0],"rotation":[0,0,0]},{"name":"Vesper_01_Foundation_solid","position":[0.0,0.045,3.0],"size":[106.80000000000001,0.24,166.8],"rotation":[0,0,0]},{"name":"Vesper_01_Foundation_solid","position":[0.0,0.66,0.0],"size":[69.0,1.26,123.0],"rotation":[0,0,0]},{"name":"Vesper_01_Foundation_solid","position":[0.0,0.33,63.900000000000006],"size":[24.0,0.66,6.0],"rotation":[0,0,0]},{"name":"Vesper_01_Foundation_solid","position":[0.0,0.66,62.550000000000004],"size":[21.9,1.32,4.65],"rotation":[0,0,0]},{"name":"Vesper_01_Foundation_solid","position":[0.0,0.99,61.2],"size":[19.799999999999997,1.98,3.3000000000000003],"rotation":[0,0,0]},{"name":"Vesper_02_InteriorFloor_solid","position":[0.0,1.41,0.0],"size":[63.900000000000006,0.42000000000000004,119.69999999999999],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay1_solid","position":[-32.099999999999994,4.800000000000001,45.599999999999994],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay1_solid","position":[-32.099999999999994,21.900000000000002,54.224999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay1_solid","position":[-32.099999999999994,21.900000000000002,36.974999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay2_solid","position":[-32.099999999999994,4.800000000000001,22.799999999999997],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay2_solid","position":[-32.099999999999994,21.900000000000002,31.424999999999997],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay2_solid","position":[-32.099999999999994,21.900000000000002,14.174999999999999],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay3_solid","position":[-32.099999999999994,4.800000000000001,0.0],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay3_solid","position":[-32.099999999999994,21.900000000000002,8.625],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay3_solid","position":[-32.099999999999994,21.900000000000002,-8.625],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay4_solid","position":[-32.099999999999994,4.800000000000001,-22.799999999999997],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay4_solid","position":[-32.099999999999994,21.900000000000002,-14.174999999999999],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay4_solid","position":[-32.099999999999994,21.900000000000002,-31.424999999999997],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay5_solid","position":[-32.099999999999994,4.800000000000001,-45.599999999999994],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay5_solid","position":[-32.099999999999994,21.900000000000002,-36.974999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_West_Bay5_solid","position":[-32.099999999999994,21.900000000000002,-54.224999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-32.099999999999994,17.1,58.5],"size":[1.9500000000000002,34.2,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-32.099999999999994,17.1,-58.5],"size":[1.9500000000000002,34.2,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,57.0],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,34.2],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,11.399999999999999],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,-11.399999999999999],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,-34.2],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_-1_solid","position":[-34.349999999999994,9.0,-57.0],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,54.0],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,54.0],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,32.400000000000006],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,32.400000000000006],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,10.8],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,10.8],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,-10.8],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,-10.8],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,-32.400000000000006],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,-32.400000000000006],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_-1_solid","position":[-16.950000000000003,2.4000000000000004,-54.0],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[-16.950000000000003,12.450000000000001,-54.0],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay1_solid","position":[32.099999999999994,4.800000000000001,45.599999999999994],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay1_solid","position":[32.099999999999994,21.900000000000002,54.224999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay1_solid","position":[32.099999999999994,21.900000000000002,36.974999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay2_solid","position":[32.099999999999994,4.800000000000001,22.799999999999997],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay2_solid","position":[32.099999999999994,21.900000000000002,31.424999999999997],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay2_solid","position":[32.099999999999994,21.900000000000002,14.174999999999999],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay3_solid","position":[32.099999999999994,4.800000000000001,0.0],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay3_solid","position":[32.099999999999994,21.900000000000002,8.625],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay3_solid","position":[32.099999999999994,21.900000000000002,-8.625],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay4_solid","position":[32.099999999999994,4.800000000000001,-22.799999999999997],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay4_solid","position":[32.099999999999994,21.900000000000002,-14.174999999999999],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay4_solid","position":[32.099999999999994,21.900000000000002,-31.424999999999997],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay5_solid","position":[32.099999999999994,4.800000000000001,-45.599999999999994],"size":[1.9500000000000002,9.600000000000001,22.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay5_solid","position":[32.099999999999994,21.900000000000002,-36.974999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_03_East_Bay5_solid","position":[32.099999999999994,21.900000000000002,-54.224999999999994],"size":[1.9500000000000002,24.599999999999998,5.55],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[32.099999999999994,17.1,58.5],"size":[1.9500000000000002,34.2,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[32.099999999999994,17.1,-58.5],"size":[1.9500000000000002,34.2,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,57.0],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,34.2],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,11.399999999999999],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,-11.399999999999999],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,-34.2],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_04_Buttresses_1_solid","position":[34.349999999999994,9.0,-57.0],"size":[4.35,15.299999999999999,3.0],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,54.0],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,54.0],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,32.400000000000006],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,32.400000000000006],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,10.8],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,10.8],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,-10.8],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,-10.8],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,-32.400000000000006],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,-32.400000000000006],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"Vesper_05_Arcade_1_solid","position":[16.950000000000003,2.4000000000000004,-54.0],"size":[3.75,1.5,3.75],"rotation":[0,0,0]},{"name":"NaveColumn","position":[16.950000000000003,12.450000000000001,-54.0],"size":[3.7199999999999998,21.6,3.7199999999999998],"rotation":[0,0,0]},{"name":"EntranceJamb","position":[-13.200000000000001,14.100000000000001,60.0],"size":[10.5,28.200000000000003,2.0999999999999996],"rotation":[0,0,0]},{"name":"EntranceJamb","position":[13.200000000000001,14.100000000000001,60.0],"size":[10.5,28.200000000000003,2.0999999999999996],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_0_solid","position":[-22.5,6.0,-60.0],"size":[22.5,12.0,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_0_solid","position":[-30.375,23.1,-60.0],"size":[6.75,22.200000000000003,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_0_solid","position":[-14.625,23.1,-60.0],"size":[6.75,22.200000000000003,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_1_solid","position":[0.0,6.0,-60.0],"size":[22.5,12.0,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_1_solid","position":[-8.100000000000001,30.974999999999998,-60.0],"size":[6.300000000000001,37.949999999999996,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_1_solid","position":[8.100000000000001,30.974999999999998,-60.0],"size":[6.300000000000001,37.949999999999996,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_2_solid","position":[22.5,6.0,-60.0],"size":[22.5,12.0,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_2_solid","position":[14.625,23.1,-60.0],"size":[6.75,22.200000000000003,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_14_SanctuaryWall_2_solid","position":[30.375,23.1,-60.0],"size":[6.75,22.200000000000003,1.9500000000000002],"rotation":[0,0,0]},{"name":"Vesper_16_BellTower_-1_solid","position":[-26.400000000000002,21.75,54.599999999999994],"size":[13.950000000000001,40.8,14.700000000000001],"rotation":[0,0,0]},{"name":"Vesper_16_BellTower_1_solid","position":[26.400000000000002,21.75,54.599999999999994],"size":[13.950000000000001,40.8,14.700000000000001],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,40.2],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,32.400000000000006],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,24.599999999999998],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,16.799999999999997],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,9.0],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,1.2000000000000002],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,-6.6000000000000005],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,-14.399999999999999],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,-22.200000000000003],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[-10.649999999999999,3.54,-30.0],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,40.2],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,32.400000000000006],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,24.599999999999998],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,16.799999999999997],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,9.0],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,1.2000000000000002],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,-6.6000000000000005],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,-14.399999999999999],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,-22.200000000000003],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Pew","position":[10.649999999999999,3.54,-30.0],"size":[7.98,3.9000000000000004,2.55],"rotation":[0,0,0]},{"name":"Vesper_19_Altar_solid","position":[0.0,1.8900000000000001,-50.099999999999994],"size":[30.0,0.6000000000000001,16.799999999999997],"rotation":[0,0,0]},{"name":"Vesper_19_Altar_solid","position":[0.0,2.4000000000000004,-50.099999999999994],"size":[28.349999999999998,0.6000000000000001,15.45],"rotation":[0,0,0]},{"name":"Vesper_19_Altar_solid","position":[0.0,2.91,-50.099999999999994],"size":[26.700000000000003,0.6000000000000001,14.099999999999998],"rotation":[0,0,0]},{"name":"Vesper_19_Altar_solid","position":[0.0,4.949999999999999,-51.900000000000006],"size":[14.100000000000001,3.0,5.4],"rotation":[0,0,0]}],"lights":[{"name":"Chandelier_-10.8","position":[0.0,26.099999999999998,32.400000000000006],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"Chandelier_3.6","position":[0.0,26.099999999999998,-10.8],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"Chandelier_14.4","position":[0.0,26.099999999999998,-43.2],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"EntryLantern_-1","position":[-15.0,9.3,72.0],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"EntryLantern_1","position":[15.0,9.3,72.0],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"SanctuaryWarm","position":[0.0,16.200000000000003,-48.0],"color":[1,0.64,0.3],"range":30.0,"brightness":1.1},{"name":"WindowWash_-1_-11.4","position":[-25.5,21.0,34.2],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1},{"name":"WindowWash_-1_3.8","position":[-25.5,21.0,-11.399999999999999],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1},{"name":"WindowWash_-1_15.2","position":[-25.5,21.0,-45.599999999999994],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1},{"name":"WindowWash_1_-11.4","position":[25.5,21.0,34.2],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1},{"name":"WindowWash_1_3.8","position":[25.5,21.0,-11.399999999999999],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1},{"name":"WindowWash_1_15.2","position":[25.5,21.0,-45.599999999999994],"color":[0.27,0.58,1],"range":30.0,"brightness":1.1}]}]=])
local ENABLE_LOCAL_LIGHTS = true

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local FOLDER_NAME = "_VesperSetup"
local OWNER_ATTRIBUTE = "VesperSetupOwner"
local OWNER = "vesper-cathedral/v1"

assert(not RunService:IsRunning(), "Run cathedral setup in Studio Edit mode, outside a Play test.")
local selected = Selection:Get()
assert(#selected == 1 and selected[1]:IsA("Model"), "Select exactly one imported cathedral Model first.")
local model = selected[1]
assert(model:IsDescendantOf(workspace), "The selected cathedral Model must be in Workspace.")

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

assert(type(DATA) == "table", "This is an unfilled template; use the packaged setup script.")
local targetDimensions = vector(DATA.dimensions, "dimensions")
local sourceCenter = vector(DATA.center, "center")
assert(math.min(targetDimensions.X, targetDimensions.Y, targetDimensions.Z) > 0, "Invalid authored dimensions.")
assert(type(DATA.colliders) == "table" and #DATA.colliders > 0, "Missing collider metadata.")
assert(type(DATA.lights) == "table", "Missing light metadata.")

-- Validate all metadata and the complete selection before any mutation.
local colliderSpecs = {}
for index, entry in ipairs(DATA.colliders) do
	assert(type(entry.name) == "string" and #entry.name > 0, "Collider has no name.")
	local size = vector(entry.size, "collider size " .. index)
	assert(math.min(size.X, size.Y, size.Z) >= 0.001, "Collider size is too small.")
	colliderSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "collider position " .. index),
		size = size,
		rotation = vector(entry.rotation, "collider rotation " .. index),
	}
end
local lightSpecs = {}
for index, entry in ipairs(DATA.lights) do
	assert(type(entry.name) == "string" and #entry.name > 0, "Light has no name.")
	local color = vector(entry.color, "light color " .. index)
	assert(math.min(color.X, color.Y, color.Z) >= 0 and math.max(color.X, color.Y, color.Z) <= 1, "Invalid light color.")
	assert(finite(entry.range) and entry.range > 0 and entry.range <= 60, "Light range must be within (0, 60].")
	assert(finite(entry.brightness) and entry.brightness >= 0, "Invalid light brightness.")
	lightSpecs[index] = {
		name = entry.name,
		position = vector(entry.position, "light position " .. index),
		color = Color3.new(color.X, color.Y, color.Z),
		range = entry.range,
		brightness = entry.brightness,
	}
end

local previousSetup
for _, child in ipairs(model:GetChildren()) do
	if child.Name == FOLDER_NAME then
		assert(previousSetup == nil, "More than one _VesperSetup exists; resolve the conflicting folders first.")
		assert(child:IsA("Folder") and child:GetAttribute(OWNER_ATTRIBUTE) == OWNER,
			"An unrecognized _VesperSetup exists. It will not be replaced.")
		previousSetup = child
		for _, descendant in ipairs(child:GetDescendants()) do
			assert(descendant:GetAttribute(OWNER_ATTRIBUTE) == OWNER,
				"_VesperSetup contains an unrecognized addition. Move it out before rerunning setup.")
		end
	end
end

local visuals = {}
local savedVisuals = {}
local visualNames = {}
for _, descendant in ipairs(model:GetDescendants()) do
	if not previousSetup or not descendant:IsDescendantOf(previousSetup) then
		assert(not descendant:IsA("LuaSourceContainer") and not descendant:IsA("Humanoid"),
			"The selection contains scripts or a character. Select only the untouched cathedral import.")
		if descendant:IsA("BasePart") then
			assert(descendant:IsA("MeshPart"), "The selection has an extra non-mesh part. Select only the cathedral import.")
			assert(string.match(descendant.Name, "^Vesper_") ~= nil,
				"The selection contains a mesh outside the Vesper import. Move additions out before setup.")
			table.insert(visuals, descendant)
			visualNames[descendant.Name] = true
			savedVisuals[descendant] = {
				Anchored = descendant.Anchored,
				CanCollide = descendant.CanCollide,
				CanTouch = descendant.CanTouch,
			}
		end
	end
end
assert(#visuals > 0, "The selected Model contains no imported MeshParts.")
assert(visualNames.Vesper_01_Foundation and visualNames.Vesper_02_InteriorFloor and visualNames.Vesper_07_NaveRoof,
	"The selected Model is not the complete Vesper Cathedral import. Preserve its supplied mesh names.")
assert(not (previousSetup and model.PrimaryPart and model.PrimaryPart:IsDescendantOf(previousSetup)),
	"The Model's PrimaryPart is inside the replaceable setup folder. Clear that PrimaryPart before rerunning setup.")

-- Use the visual meshes only, so previously installed colliders/lights cannot
-- alter the repeat-run measurement. Bounds are oriented by the model pivot,
-- matching GetBoundingBox's documented model frame. Import exports have applied
-- mesh transforms, so their part boxes match the recorded authored bounds.
local function visualBounds()
	local orientation = model:GetPivot().Rotation
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(visuals) do
		local half = part.Size * 0.5
		for _, x in ipairs({-1, 1}) do
			for _, y in ipairs({-1, 1}) do
				for _, z in ipairs({-1, 1}) do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					local p = orientation:PointToObjectSpace(corner)
					low = Vector3.new(math.min(low.X, p.X), math.min(low.Y, p.Y), math.min(low.Z, p.Z))
					high = Vector3.new(math.max(high.X, p.X), math.max(high.Y, p.Y), math.max(high.Z, p.Z))
				end
			end
		end
	end
	return orientation * CFrame.new((low + high) * 0.5), high - low
end

local _, initialDimensions = visualBounds()
assert(math.min(initialDimensions.X, initialDimensions.Y, initialDimensions.Z) > 0, "The imported visual bounds are empty.")
local resizeFactor = targetDimensions.X / initialDimensions.X
local predictedDimensions = initialDimensions * resizeFactor
local function proportionMatches(actual, expected)
	return math.abs(actual - expected) <= math.max(0.05, expected * 0.03)
end
assert(proportionMatches(predictedDimensions.Y, targetDimensions.Y)
	and proportionMatches(predictedDimensions.Z, targetDimensions.Z),
	"The model proportions do not match Vesper Cathedral. Check selection, export orientation, and added meshes; no changes were made.")

local savedPivot = model:GetPivot()
local savedScale = model:GetScale()
local desiredScale = savedScale * resizeFactor
assert(finite(desiredScale) and desiredScale > 0, "Invalid target model scale.")
local recording = ChangeHistoryService:TryBeginRecording("VesperCathedralSetup", "Set up Vesper Cathedral")
assert(recording, "Studio could not begin an undo recording. Finish the active editing operation and retry.")

local newSetup
local ok, problem = xpcall(function()
	-- Detach the old owned folder during normalization; it is retained by Studio's
	-- undo history rather than destroyed, so undo can restore its exact contents.
	if previousSetup then
		previousSetup.Parent = nil
	end
	model:ScaleTo(desiredScale)
	model:PivotTo(savedPivot)
	local boundsFrame, finalDimensions = visualBounds()
	assert(proportionMatches(finalDimensions.X, targetDimensions.X)
		and proportionMatches(finalDimensions.Y, targetDimensions.Y)
		and proportionMatches(finalDimensions.Z, targetDimensions.Z), "Scale verification failed.")
	assert(math.abs(finalDimensions.X - targetDimensions.X) <= math.max(0.01, targetDimensions.X * 0.0001),
		"Studio did not retain the requested width.")

	newSetup = Instance.new("Folder")
	newSetup.Name = FOLDER_NAME
	newSetup:SetAttribute(OWNER_ATTRIBUTE, OWNER)
	newSetup:SetAttribute("SourceWidthStuds", targetDimensions.X)
	newSetup:SetAttribute("LocalLightsEnabled", ENABLE_LOCAL_LIGHTS)

	local function newInvisiblePart(name)
		local part = Instance.new("Part")
		part.Name = name
		part:SetAttribute(OWNER_ATTRIBUTE, OWNER)
		part.Anchored = true
		part.Transparency = 1
		part.CastShadow = false
		part.CanTouch = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end
	for _, spec in ipairs(colliderSpecs) do
		local part = newInvisiblePart(spec.name)
		part.CanCollide = true
		part.CanQuery = true
		part.Size = spec.size
		part.CFrame = boundsFrame * CFrame.new(spec.position - sourceCenter)
			* CFrame.Angles(spec.rotation.X, spec.rotation.Y, spec.rotation.Z)
		part.Parent = newSetup
	end
	if ENABLE_LOCAL_LIGHTS then
		for _, spec in ipairs(lightSpecs) do
			local part = newInvisiblePart(spec.name)
			part.CanCollide = false
			part.CanQuery = false
			part.Size = Vector3.new(0.1, 0.1, 0.1)
			part.CFrame = boundsFrame * CFrame.new(spec.position - sourceCenter)
			local light = Instance.new("PointLight")
			light.Name = "LocalLight"
			light:SetAttribute(OWNER_ATTRIBUTE, OWNER)
			light.Color = spec.color
			light.Range = spec.range
			light.Brightness = spec.brightness
			light.Shadows = false
			light.Parent = part
			part.Parent = newSetup
		end
	end
	for _, part in ipairs(visuals) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
	end
	newSetup.Parent = model
	model:PivotTo(savedPivot)
end, debug.traceback)

if not ok then
	local restored, restoreProblem = pcall(function()
		if newSetup then newSetup:Destroy() end
		model:ScaleTo(savedScale)
		model:PivotTo(savedPivot)
		for part, values in pairs(savedVisuals) do
			part.Anchored = values.Anchored
			part.CanCollide = values.CanCollide
			part.CanTouch = values.CanTouch
		end
		if previousSetup then previousSetup.Parent = model end
		model:PivotTo(savedPivot)
	end)
	-- If restoration fails, keep the recording available as a user Undo step.
	ChangeHistoryService:FinishRecording(recording,
		if restored then Enum.FinishRecordingOperation.Cancel else Enum.FinishRecordingOperation.Commit)
	if not restored then
		warn("Automatic restoration failed; use Undo before continuing: " .. tostring(restoreProblem))
	end
	error("Cathedral setup failed: " .. tostring(problem))
end

ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
print(string.format("Vesper Cathedral ready: %d visual meshes, %d colliders, %d local lights; width %.2f studs. Undo restores the previous model state.",
	#visuals, #colliderSpecs, if ENABLE_LOCAL_LIGHTS then #lightSpecs else 0, targetDimensions.X))
print("Walk-test entrance, nave, aisles, and altar steps in a separate test place before integrating into a game. Nothing was saved or published.")
