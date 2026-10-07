"""The promo batch of 2026-10-07: what every picture is, which references it gets, which Codex job makes it.

    python3 tools/promo/make_briefs.py        # writes brief_<job>.md and images.json into artifacts/promo-20261007

Codex makes the pictures without lettering; `finish.py` crops them to size and sets the lettering.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts' / 'promo-20261007'
R = 'artifacts/promo-20261007/refs/'

PF, PB = 'player_suit_front.jpg', 'player_suit_back.jpg'
L1A, L1B, L1C, L1D, L1E = ('l1_01_elevator_arrival_yellow_maze_red_floor_line.jpg', 'l1_02_player_in_maze_elevator_behind.jpg',
                           'l1_03_the_entity_closeup_walking_at_camera_amber_eyes.jpg', 'l1_04_the_entity_full_body_corridor_wall_graffiti.jpg',
                           'l1_05_zyntra_fuse_relay_wall_cabinet.jpg')
L2 = {0: 'l2new_00_start_stairs.jpg', 1: 'l2new_01_area1_flooded_pillar_hall.jpg', 2: 'l2new_02_area3_colossal_column_nave.jpg',
      3: 'l2new_03_area4_stair_tower_from_below.jpg', 4: 'l2new_04_area4_great_stepwell.jpg', 5: 'l2new_05_area2_blue_gold_mosaic_rotunda.jpg',
      6: 'l2new_06_area5_lap_pool_hall_desert_windows.jpg', 7: 'l2new_07_area6_door_galleries_spiral_stair.jpg',
      8: 'l2new_08_area6_drained_pool_atrium_of_yellow_doors.jpg'}
L3A, L3B, L3C, L3D = ('l3_01_player_in_orange_party_room_confetti_carpet.jpg', 'l3_02_mall_manager_look_reference_bind_pose_red_balloon_head.jpg',
                      'l3_03_mall_manager_upper_body_striped_shirt_name_tag.jpg', 'l3_04_party_room_road_carpet_cd_on_folding_table_player.jpg')
L4A, L4B, L4C = ('l4_01_round_start_power_off_red_emergency_light_player.jpg', 'l4_02_the_usher_look_reference_in_red_emergency_light.jpg',
                 'l4_03_the_usher_true_colours_test_lamp_red_uniform_black_faceless_head.jpg')
L5 = {1: 'l5_01_rose_start_player_from_behind.jpg', 2: 'l5_02_blue_player_on_ledge_over_drop.jpg', 3: 'l5_03_orange_spiral_room_player_on_ledge.jpg',
      4: 'l5_04_crimson_spiral_stair_round_great_pillar.jpg', 5: 'l5_05_teal_pillar_field_player_on_pillar_top.jpg',
      6: 'l5_06_ivory_tower_spiral_stair_missing_treads.jpg', 8: 'l5_08_finale_closing_corridor_door_at_far_end.jpg',
      9: 'l5_09_mint_room_player_on_block_over_drop.jpg'}
L6 = {1: 'l6_01_spawn_tunnel_padded_vinyl_play_zone_gate.jpg', 2: 'l6_02_arena_court_counter_at_post_galleries_all_round.jpg',
      3: 'l6_03_the_counter_side_full_body_at_post.jpg', 4: 'l6_04_the_counter_face_closeup_party_hat.jpg',
      5: 'l6_05_looking_down_on_court_through_netting.jpg', 6: 'l6_06_top_down_overpass_bridges_court_far_below.jpg',
      7: 'l6_07_inside_a_gallery_floor_and_ceiling.jpg', 8: 'l6_08_post_ring_and_hatch_closeup.jpg',
      9: 'l6_09_exit_room_green_mouldy_padding_exit_door.jpg'}
BOARD6, BOARD4, BOARDP = 'board_six_levels.jpg', 'board_four_entities.jpg', 'board_player.jpg'


def K(n):
    return f'krille/krille_{n:02d}.png'


SPACE = {
    'gallery': 'Leave the LOWER-LEFT corner (about a third of the width, a fifth of the height) calm and darker for a small "LEVEL" line.',
    'thumb': 'Leave the UPPER-LEFT third calm and darker for the game title.',
    'ad_landscape': 'Leave the UPPER-LEFT third calm and darker for the game title.',
    'ad_square': 'Leave the TOP fifth calm and darker for the game title.',
    'ad_portrait': 'Leave the TOP fifth calm and darker for the game title, and keep the bottom tenth free of anything important.',
    'icon': 'GAME ICON. It is shown 150 pixels wide and often 64: ONE subject that fills the square, big simple shapes, a '
            'strong rim light, two or three colours, a face or eyes where there is one, nothing that needs a second look. '
            'Keep everything that matters inside the middle 80 percent (Roblox rounds the corners). No calm space is '
            'needed: nothing is written on an icon.',
}

# name, job, set, shape, level, references, scene
IMAGES = [
    # ---------------------------------------------------------------- Level 1 (job A)
    ('G01_level1_it_hears_you', 'A', 'gallery', 'landscape', 1, [L1C, L1D, K(2), PF, PB],
     'Two players crouch side by side behind the corner of a yellow partition in the foreground, seen three-quarters '
     'from behind and the side, one with a hand raised to hold the other back. Past the corner, twelve metres down the '
     'carpeted corridor under a fluorescent ceiling panel, the Entity walks across the opening in profile, hunched, long '
     'arms hanging, amber eyes. Warm yellow light, the players in half shadow.'),
    ('G02_level1_pull_the_fuse', 'A', 'gallery', 'landscape', 1, [L1E, L1B, L1D, PF, PB],
     'A player stands at the ZYNTRA RELAY wall cabinet of the reference (cream metal box on the yellow wallpaper, glass '
     'front, a white cylindrical fuse with copper caps, the small black display reading ZYNTRA RELAY) and pulls the fuse '
     'out with both gloves. A second player stands behind with a hand torch, looking back over the shoulder down the '
     'long corridor, where far away in the dim two amber eyes and the hunched outline of the Entity can just be made out.'),
    ('T01_hero_office_hide', 'A', 'thumb', 'landscape', 1, [L1C, L1D, K(2), PF, PB],
     'The main thumbnail. Low camera. Two players press themselves against a yellow partition in the right foreground, '
     'large in frame, one holding a finger of its glove up to the gas mask. In the left middle distance, in a lit '
     'opening of the maze, the Entity stands hunched and whole, facing the camera, amber eyes glowing, its black shape '
     'against the bright yellow wall behind it. Deep one-point perspective of ceiling panels.'),
    ('T04_hero_shh', 'A', 'thumb', 'landscape', 1, [PF, PB, L1C, K(5)],
     'Close portrait of one player from the chest up on the RIGHT half of the frame, facing us, holding one black '
     'mitten finger upright in front of the gas mask: the "be quiet" sign. A teammate just behind its shoulder. Behind '
     'them a dark yellow corridor falls away, out of focus, and in it the tall blurred shape of the Entity with two '
     'sharp amber eyes. Rim light on the yellow hoods.'),
    ('A01_ad_office_run', 'A', 'ad_landscape', 'landscape', 1, [L1D, L1C, K(5), PF],
     'A player sprints straight at the camera down a yellow corridor, hand torch swinging, the suit creasing with the '
     'run. Eight metres behind, filling the corridor, the Entity lunges after it, arms spread wide, eyes burning RED '
     '(it is hunting). The ceiling lights behind the Entity are dark; the ones ahead of the player are lit. Motion in '
     'the carpet and walls, the player sharp.'),
    ('A10_ad_entity_reach', 'A', 'ad_square', 'square', 1, [L1C, L1D, K(4)],
     'The Entity alone, close: its hooded head and heavy shoulders fill the upper middle of the square, two small '
     'round amber eyes in the black of the hood, and one enormous long-fingered black hand reaches toward the lens in '
     'the lower right, out of focus. Yellow wallpaper and one fluorescent panel behind. No players.'),
    # ---------------------------------------------------------------- Level 2 (job B): the new map, no entity
    ('G03_level2_the_stepwell', 'B', 'gallery', 'landscape', 2, [L2[4], L2[3], PB, PF],
     'The immense stepwell of the reference, looking down and across it: cream plaster walls of zig-zag stair flights '
     'with glass rails and arched doorways, tier under tier, down to a still green pool far below; the slender round '
     'pillar and the stair tower at one side. Two tiny players walk down a flight in the middle distance, one behind '
     'the other. Soft warm daylight from above, long shadows. Nothing else alive.'),
    ('G04_level2_a_thousand_doors', 'B', 'gallery', 'landscape', 2, [L2[8], L2[7], PB],
     'The ten-storey atrium of the reference from the floor of its drained pool: pale mint and white pool tiles, a '
     'steel ladder, and on both sides gallery upon gallery of identical yellow doors with small lit windows behind '
     'thin blue rails, converging to a far wall of the same doors, a strip of skylight overhead. Two small players '
     'stand in the empty pool looking up. Bright, clean, wrong.'),
    ('A02_ad_poolrooms_hall', 'B', 'ad_landscape', 'landscape', 2, [L2[1], L2[2], PB],
     'One player seen from behind, small, standing ankle-deep at the edge of the vast flooded hall of the reference: '
     'rows of round tiled columns and low vaults reflected in flat turquoise water, receding in every direction, '
     'daylight falling in shafts between the columns. Ripples spread from its boots. Silence.'),
    ('A08_ad_poolrooms_rotunda', 'B', 'ad_landscape', 'landscape', 2, [L2[5], PB],
     'The domed rotunda of the reference: walls and dome of deep blue and gold mosaic, a round pool, a small island '
     'with a golden gong, a single deck chair. One player wades toward the gong, waist deep, seen from behind and '
     'above. Light from an oculus makes a bright disc on the water.'),
    ('A16_ad_poolrooms_stairs_down', 'B', 'ad_square', 'square', 2, [L2[3], L2[4], PB],
     'Looking straight down the stair tower of the reference from its top landing: flight under flight of cream stairs '
     'with glass rails turning round a square well, to green water at the very bottom. One tiny player on a landing '
     'far below, looking up. Strong geometry, daylight.'),
    ('A20_ad_poolrooms_doors_tall', 'B', 'ad_portrait', 'portrait', 2, [L2[8], L2[7], PB],
     'Tall picture of the atrium of yellow doors of the reference, from the drained pool floor looking up and along: '
     'the galleries of identical yellow doors rise out of frame on both sides to a bright slot of skylight. One player '
     'stands small in the lower middle, back to us, head tilted up. Pale tiles under its boots.'),
    # ---------------------------------------------------------------- Level 3 (job C)
    ('G05_level3_under_the_table', 'C', 'gallery', 'landscape', 3, [L3D, L3B, L3C, K(12), PF],
     'Camera at floor level in the road-map-carpet party room of the reference. In the right foreground two players '
     'lie flat on their fronts UNDER a cream folding table, heads together, perfectly still. Past the table legs, four '
     'metres away, the Mall Manager walks slowly through the room: seen whole, stooping a little, its red balloon head '
     'turning toward the table, red-gloved hands hanging at the ends of its long arms. Dim ceiling panels, paper cups '
     'on the table above them.'),
    ('G06_level3_find_the_cds', 'C', 'gallery', 'landscape', 3, [L3D, K(13), L3C, PF, PB],
     'A player leans over the folding table of the reference and picks up the CD in its clear jewel case with one '
     'glove; paper cups and plates beside it, a teal and a green plastic chair. A teammate stands guard with a hand '
     'torch. Road-map play carpet, cream walls with a toy-train sticker, balloons on strings. In the dark doorway at '
     'the back of the room: the tall thin outline of the Mall Manager, its red balloon head just catching the light.'),
    ('T06_hero_party_rooms', 'C', 'thumb', 'landscape', 3, [L3C, L3B, L3D, K(14), PF],
     'The orange party room of the reference (orange walls, black lower band, dark confetti carpet, balloons). On the '
     'right the Mall Manager bends forward from the waist into the picture, large, its red balloon head tilted, one '
     'red-gloved hand reaching down toward a folding table. Under that table, lower left of centre, two players hide, '
     'gas-mask lenses catching the light.'),
    ('A03_ad_table_check', 'C', 'ad_landscape', 'landscape', 3, [L3C, L3B, L3D, PF],
     'From under the folding table, between two hiding players seen from behind in the near foreground: the edge of '
     'the table top above, and beyond it the Mall Manager crouched right down on its long legs, its red balloon head '
     'lowered to table height and tilted, looking straight in at them, one red glove gripping the table edge. '
     'Road-map carpet, dim room behind.'),
    ('A13_ad_manager_balloon', 'C', 'ad_square', 'square', 3, [L3C, L3B, K(14)],
     'The Mall Manager from the chest up in the orange party room, head and shoulders leaning in from the upper right: '
     'the glossy red balloon head with a single highlight, the orange and cream striped shirt collar and white name '
     'tag (blank). Around it float ordinary party balloons on strings in red, green and blue, so for a moment its head '
     'is one more balloon. No players.'),
    ('A17_ad_hand_under_table', 'C', 'ad_square', 'square', 3, [L3D, L3C, PF],
     'Tight on two players huddled under a folding table, facing us, lenses wide. From the top edge of the picture a '
     'long thin pale arm ending in a RED glove reaches down past the table edge toward them, fingers spread. '
     'Road-map carpet under them, shadow of the table across their hoods.'),
    # ---------------------------------------------------------------- Level 4 (job D)
    ('G07_level4_the_lobby', 'D', 'gallery', 'landscape', 4, [K(15), K(16), K(18), PB],
     'The cinema foyer of the references with the power ON: navy walls, magenta and cyan neon bands, the carpet of '
     'pink and blue triangles on a dotted grid, a starlight ceiling, a round neon-rimmed concession island, a row of '
     'glowing arcade cabinets down one side. Two players walk in, seen from behind, small against the neon. Empty and '
     'humming. No entity.'),
    ('G08_level4_the_usher', 'D', 'gallery', 'landscape', 4, [L4C, L4B, K(17), K(21), PF],
     'Inside a dark auditorium of the reference: rows of red seats, a pale glowing screen. A player in the left '
     'foreground, seen from behind, holds a hand torch out; its beam cuts across the seats and lands on the Usher, '
     'standing whole in the aisle ten rows down, frozen mid-step: crimson bellhop uniform and gold buttons lit by the '
     'beam, black faceless head, white gloves glowing. Outside the beam everything is nearly black.'),
    ('T05_hero_cinema', 'D', 'thumb', 'landscape', 4, [L4C, K(18), K(15), PF, PB],
     'The long neon corridor of the reference (orange and magenta neon lines, triangle carpet, star ceiling). The '
     'Usher stands tall in the middle distance on the right, whole, head nearly at the ceiling, one glowing white '
     'glove raised with a finger to where its mouth would be. Two players in the left foreground back away from it, '
     'torch beams crossing on its crimson uniform.'),
    ('A04_ad_usher_torch', 'D', 'ad_landscape', 'landscape', 4, [L4C, L4A, PF, PB],
     'Power off: the cinema in black and deep red emergency light, the triangle carpet glowing dull red (as the '
     'reference). Two players stand back to back in the middle; one torch beam points left at nothing, the other points '
     'right and catches the Usher three metres away, frozen, bending down toward them, white gloves spread.'),
    ('A14_ad_usher_shh', 'D', 'ad_square', 'square', 4, [L4C, L4B, K(18)],
     'The Usher from the waist up, facing us, close: glossy black featureless head under the crimson pillbox cap, the '
     'double row of gold buttons, and one glowing white-gloved hand raised with the index finger upright in front of '
     'the blank face. Magenta neon and star ceiling out of focus behind. No players.'),
    ('A22_ad_cinema_corridor_tall', 'D', 'ad_portrait', 'portrait', 4, [K(18), L4C, PB],
     'Tall picture down the neon corridor of the reference: star ceiling above, neon lines converging, triangle carpet '
     'below. A player in the lower foreground seen from behind, torch lowered. At the far end of the corridor, small '
     'but unmistakable, the Usher stands in the middle of the carpet, white gloves glowing.'),
    # ---------------------------------------------------------------- Level 5 (job E): no entity
    ('G09_level5_over_the_void', 'E', 'gallery', 'landscape', 5, [L5[2], L5[1], K(24), PB, PF],
     'The blue room of the reference: a line of narrow blue block tops leading away over a black drop between huge '
     'rounded blue walls, a lamp globe on a long thin rod. One player stands on the near ledge, seen from behind; a '
     'second is in mid-jump across the gap ahead, arms out, nothing under it. Dark blue balls rest on a far ledge.'),
    ('G10_level5_the_tower', 'E', 'gallery', 'landscape', 5, [L5[6], L5[4], PB],
     'The ivory room of the reference: a white spiral stair winding round a great white column, treads missing so the '
     'stair is a broken ring of small steps over blackness. Three tiny players at different heights on it, one about to '
     'jump a gap. The column rises out of frame and sinks into the dark. Cold soft light from above.'),
    ('A05_ad_void_pillars', 'E', 'ad_landscape', 'landscape', 5, [L5[5], PB, PF],
     'The teal room of the reference from above and behind: a field of tall square teal pillars of different heights '
     'standing out of blackness, only their small flat tops to stand on. A player is caught in the air between two '
     'tops, legs tucked, a second waits on the pillar behind. The far pillars fade into the dark.'),
    ('A15_ad_void_ledge_above', 'E', 'ad_square', 'square', 5, [L5[1], L5[2], PB],
     'Straight down from above onto a narrow rose-pink walkway crossing the square on a diagonal, a player on it seen '
     'from directly overhead (yellow hood, black backpack), two dark blue balls beside it. On both sides of the '
     'walkway: the smooth pink walls falling away into pure black.'),
    ('A19_ad_void_crimson_tall', 'E', 'ad_portrait', 'portrait', 5, [L5[4], L5[6], PB],
     'Tall picture of the crimson room of the reference: a single stair of red treads fixed to the side of an enormous '
     'round red pillar, winding up out of frame and down into black. One small player on the stair in the middle of '
     'the picture, hand on the pillar. Everything is the one red; soft highlights on the curved surfaces.'),
    ('A24_ad_void_the_fall', 'E', 'ad_portrait', 'portrait', 5, [L5[5], L5[2], PB],
     'Tall picture, looking down past the edge of a blue ledge in the lower foreground where a player kneels and '
     'reaches down. Below, already small, a second player falls backward into the black, arms and legs spread, looking '
     'up. Blue walls narrow toward the darkness. No impact, no blood, just the drop.'),
    # ---------------------------------------------------------------- Level 6 (job F)
    ('G11_level6_it_is_counting', 'F', 'gallery', 'landscape', 6, [L6[2], L6[4], L6[5], K(33), PB],
     'From inside a netted gallery four storeys up: two players crouch in the near foreground behind black knotted '
     'netting and a yellow padded post, seen from behind. Through the net, down in the round court of blue-and-green '
     'foam mats with its yellow ring, the Counter stands at the red post with both hands pressed over its eyes, '
     'counting. Galleries rise all round, cold strip lights.'),
    ('G12_level6_the_way_out', 'F', 'gallery', 'landscape', 6, [L6[9], L6[8], PB, PF],
     'The small exit room of the reference: walls and ceiling of mouldy dark green quilted padding, foam-mat floor, a '
     'strip light, the end of a big padded slide funnel on the left, lost plastic balls, and in the far wall an open '
     'door under a glowing green sign reading EXIT. One player has just tumbled out of the slide onto the floor; a '
     'second is already running for the door.'),
    ('T03_hero_playground', 'F', 'thumb', 'landscape', 6, [L6[4], L6[3], L6[2], PF],
     'The Counter close in the right foreground, head and shoulders, turned three-quarters toward us with its hands '
     'just coming down from its eyes: cracked white porcelain, dark glass eyes, striped paper party hat. Behind it the '
     'round court and the wall of netted galleries; in one gallery two small players duck behind a red bubble-window '
     'panel.'),
    ('A06_ad_playground_looking_up', 'F', 'ad_landscape', 'landscape', 6, [L6[6], L6[5], L6[4]],
     'Vertigo: from a rope bridge high over the court, looking straight down. Our own two black-gloved hands grip the '
     'yellow rope rail at the bottom of the frame. Far below on the blue-and-green court with its yellow ring, tiny '
     'beside the red post, the Counter stands with its white face tilted straight UP at us. Galleries and tube slides '
     'ring the drop.'),
    ('A11_ad_counter_peek', 'F', 'ad_square', 'square', 6, [L6[4], L6[3], L6[2]],
     'The Counter peeks round the left side of the red padded post: half its cracked porcelain face, one large dark '
     'glass eye, the striped paper party hat, the fingers of one jointed hand curled round the post. Blue-and-green '
     'foam floor and netted galleries out of focus behind. No players.'),
    ('A18_ad_playground_tall', 'F', 'ad_portrait', 'portrait', 6, [L6[2], L6[6], L6[4], PB],
     'Tall picture from the court floor: the wall of netted galleries rises twelve storeys out of frame, tube slides '
     'hanging down its face, a rope bridge crossing high above. Small in the lower middle the Counter stands at the '
     'red post in the yellow ring, hands over its eyes. In the lower foreground one player, seen from behind, creeps '
     'away on the foam mats.'),
    # ---------------------------------------------------------------- everything (job G)
    ('T02_hero_six_levels', 'G', 'thumb', 'landscape', 0, [BOARD6, BOARD4, BOARDP],
     'Six tall vertical slices side by side with thin black gaps, slightly slanted, one per level in order, each '
     'showing that level\'s place and, where it has one, its entity: 1 yellow office corridor with the black hunched '
     'Entity and its amber eyes; 2 the cream stepwell and green pool, empty; 3 the party room with road-map carpet and '
     'the balloon-headed Mall Manager; 4 the neon cinema corridor with the crimson Usher; 5 a single-colour void room '
     'with a player jumping between ledges; 6 the soft-play arena court with the doll Counter at the red post. '
     'Follow the two boards exactly for looks. The upper third of every slice is darker.'),
    ('A07_ad_squad_back_to_back', 'G', 'ad_landscape', 'landscape', 1, [PF, PB, L1B, K(5)],
     'Four players stand back to back in a tight ring at a crossing of four dark yellow corridors, each pointing a hand '
     'torch down a different corridor. Three beams show empty carpet. In the fourth corridor, behind the nearest '
     'player\'s shoulder, just beyond the reach of its beam: two amber eyes and the hunched outline of the Entity.'),
    ('A09_ad_meet_the_staff', 'G', 'ad_landscape', 'landscape', 0, [BOARD4, L1C, L3C, L4C, L6[4]],
     'The four entities standing in a row on a bare dark floor under four separate overhead spots, facing us, each '
     'whole, each exactly as on the board, left to right: the black hunched Entity with amber eyes; the Mall Manager '
     'with red balloon head, striped shirt and red gloves, arms at its sides; the Usher in crimson uniform with black '
     'faceless head and glowing white gloves; the porcelain doll Counter with party hat, much smaller. In the centre '
     'foreground one small player seen from behind, looking up at them. Black background.'),
    ('A12_ad_player_shh', 'G', 'ad_square', 'square', 0, [PF, PB],
     'Icon-like portrait of one player, head and shoulders, facing us against a plain dark mustard-yellow backrooms '
     'wall: yellow hood, black twin-lens gas mask, one black mitten finger held upright in front of the filter. A '
     'second ceiling light reflected small in both lenses. Nothing else.'),
    ('A21_ad_office_shadow_tall', 'G', 'ad_portrait', 'portrait', 1, [L1D, L1C, PF, K(3)],
     'Tall picture of a yellow corridor. In the lower foreground a player stands flat against the wall just inside a '
     'side opening, head turned, holding its breath. Along the opposite wall and floor falls the long distorted shadow '
     'of the Entity (hunched head, long arms, spread fingers), thrown from round the corner; one black hand is just '
     'coming into view at the corner\'s edge.'),
    ('A23_ad_party_hall_tall', 'G', 'ad_portrait', 'portrait', 3, [K(14), L3B, L3C, PB],
     'Tall picture down a long orange party room hung with bunches of party balloons on strings. A player in the lower '
     'foreground, seen from behind, stands still. At the far end among the balloons one red balloon is higher than the '
     'rest and has a striped shirt under it: the Mall Manager, standing motionless, whole, facing us.'),
    ('A25_ad_six_levels_tall', 'G', 'ad_portrait', 'portrait', 0, [BOARD6, BOARD4, BOARDP],
     'Six horizontal bands stacked top to bottom with thin black gaps, one per level in order from the top, each a '
     'wide slice of that level and its entity where it has one: yellow office and the Entity; cream poolrooms '
     'stepwell, empty; party room and the balloon-headed Mall Manager; neon cinema and the crimson Usher; '
     'single-colour void with a jumping player; soft-play arena and the doll Counter. Follow the boards exactly. The '
     'top band is darker in its upper half.'),
    # ---------------------------------------------------------------- game icons (jobs H, I, K), added 2026-10-08
    ('I01_icon_shh_eyes_in_the_lenses', 'H', 'icon', 'square', 1, [PF, PB, L1C],
     'One player, head and shoulders, facing us, filling the square: yellow hood, black twin-lens gas mask, one black '
     'mitten finger held upright in front of the filter. In EACH round lens, small and sharp, the reflection of the '
     'Entity: a black hunched shape with two amber eyes. Dark mustard background, warm rim light on the hood.'),
    ('I02_icon_it_is_behind_you', 'H', 'icon', 'square', 1, [PF, L1C, L1D],
     'A player\'s hooded head and shoulders in the lower half of the square, facing us, lenses wide. Directly behind '
     'and above it, filling the upper half, the Entity looms out of the dark: black hood, heavy shoulders, two glowing '
     'amber eyes, one long-fingered black hand coming down toward the player\'s shoulder. Yellow wallpaper glimpsed at '
     'the edges, one ceiling light behind the Entity\'s head.'),
    ('I03_icon_entity_round_the_corner', 'H', 'icon', 'square', 1, [L1C, L1D],
     'The Entity leans out from behind the corner of a yellow-wallpapered wall that fills the left third of the square: '
     'its black hooded head tilted, two round glowing amber eyes, and four long black fingers wrapped round the '
     'corner\'s edge. Bright fluorescent yellow room behind it so the black shape reads at any size. No players.'),
    ('I04_icon_split_face', 'H', 'icon', 'square', 1, [PF, L1C],
     'One face made of two halves, split straight down the middle of the square. LEFT half: the player, half of the '
     'yellow hood and the black gas mask with one round lens, lit warm. RIGHT half: the Entity, half of the black '
     'hood with one glowing amber eye, lit from behind. The two halves line up as one head. Plain dark background.'),
    ('I05_icon_balloon_manager', 'I', 'icon', 'square', 3, [L3C, L3B, K(14)],
     'The Mall Manager from the chest up, leaning into the square from above and tilting its head at us: the glossy red '
     'balloon head with one white highlight and no face, the collar of the orange and cream striped shirt, a blank '
     'white name tag, and one red-gloved hand raised with the fingers spread. Deep orange party-room wall behind, two '
     'ordinary balloons out of focus.'),
    ('I06_icon_usher_shh', 'I', 'icon', 'square', 4, [L4C, L4B, K(18)],
     'The Usher, head and shoulders, facing us: glossy black featureless mannequin head under the crimson pillbox cap '
     'with its gold band, crimson collar and gold buttons, and one glowing white-gloved index finger held upright in '
     'front of the blank face. Magenta rim light on one side and cyan on the other, black background with a few '
     'pin-point ceiling stars.'),
    ('I07_icon_counter_peeking', 'I', 'icon', 'square', 6, [L6[4], L6[3], K(33)],
     'The Counter\'s face filling the square, both jointed porcelain hands held over its eyes, and between two parted '
     'fingers ONE large dark glass eye looking straight at us. Cracked white porcelain, rosy cheek, small closed smile, '
     'the striped paper party hat on top. Dark soft-play netting and one cold strip light out of focus behind.'),
    ('I08_icon_squad_looking_up', 'K', 'icon', 'square', 1, [PF, PB, L1D],
     'Four players huddled shoulder to shoulder seen from slightly above, all four gas masks tilted up at us, lit from '
     'below by one hand torch. Across their yellow hoods falls the shadow of a huge hand with long spread fingers. '
     'Dark yellow carpet round them. Nothing else.'),
    ('I09_icon_void_jump', 'K', 'icon', 'square', 5, [L5[2], L5[1], PB],
     'A player in mid-jump, seen from the side and a little below, large in the square: yellow suit, black backpack, '
     'arms flung out, between the edges of two rose-pink blocks at the left and right borders. Under it and behind it '
     'pure black. A single small lamp globe on a thin rod above. Three colours only: pink, yellow, black.'),
    ('I10_icon_poolrooms_alone', 'K', 'icon', 'square', 2, [L2[1], L2[2], PB],
     'A player seen from behind, waist up in the lower middle of the square, standing in flat turquoise water. In front '
     'of it two rows of huge round tiled columns and a low vault recede to one bright point of daylight. Cream and '
     'turquoise, the yellow hood the only strong colour. Nothing alive but the player.'),
]

# what finish.py prints on each picture
LEVEL_NAMES = {1: 'THE OFFICE', 2: 'THE POOLROOMS', 3: 'THE PARTY ROOMS', 4: 'THE CINEMA', 5: 'THE VOID', 6: 'THE PLAYGROUND'}
TAGLINES = {
    'A01_ad_office_run': 'IT HEARD YOU.', 'A02_ad_poolrooms_hall': 'NOBODY IS HERE. KEEP WALKING.',
    'A03_ad_table_check': 'DON\'T. MOVE.', 'A04_ad_usher_torch': 'KEEP THE LIGHT ON IT.',
    'A05_ad_void_pillars': 'DON\'T LOOK DOWN.', 'A06_ad_playground_looking_up': 'IT FOUND YOU.',
    'A07_ad_squad_back_to_back': 'BRING FRIENDS. YOU WILL NEED THEM.', 'A08_ad_poolrooms_rotunda': 'SIX LEVELS. ONE WAY OUT.',
    'A09_ad_meet_the_staff': 'THEY ARE ALL LISTENING.', 'A10_ad_entity_reach': 'IT HEARS EVERYTHING.',
    'A11_ad_counter_peek': 'READY OR NOT.', 'A12_ad_player_shh': 'SHHH.', 'A13_ad_manager_balloon': 'THE PARTY NEVER ENDED.',
    'A14_ad_usher_shh': 'ENJOY THE SHOW.', 'A15_ad_void_ledge_above': 'ONE WRONG STEP.',
    'A16_ad_poolrooms_stairs_down': 'HOW DEEP DOES IT GO?', 'A17_ad_hand_under_table': 'HOLD YOUR BREATH.',
    'A18_ad_playground_tall': '...EIGHT, NINE, TEN.', 'A19_ad_void_crimson_tall': 'KEEP CLIMBING.',
    'A20_ad_poolrooms_doors_tall': 'A THOUSAND DOORS. NONE OF THEM YOURS.', 'A21_ad_office_shadow_tall': 'DON\'T MAKE A SOUND.',
    'A22_ad_cinema_corridor_tall': 'THE LAST SHOW IS STARTING.', 'A23_ad_party_hall_tall': 'ONE OF THESE IS NOT A BALLOON.',
    'A24_ad_void_the_fall': 'DON\'T LET GO.', 'A25_ad_six_levels_tall': 'SIX LEVELS. ONE RULE.',
}


def main():
    names = [i[0] for i in IMAGES]
    assert len(names) == len(set(names)) == 53, len(names)
    for name, job, kind, shape, level, refs, scene in IMAGES:
        assert len(refs) <= 5, name
        for r in refs:
            assert (OUT / 'refs' / r).exists(), (name, r)
        assert (kind.startswith('ad') and name in TAGLINES) or not kind.startswith('ad'), name
    jobs = sorted({i[1] for i in IMAGES})
    for job in jobs:
        mine = [i for i in IMAGES if i[1] == job]
        lines = [f'Read `artifacts/promo-20261007/brief_common.md` first and follow it. Job name: {job}. {len(mine)} images.',
                 f'Write `artifacts/promo-20261007/prompts_{job}.json` at the end. Make the images one after another.', '']
        for name, _, kind, shape, level, refs, scene in mine:
            lines.append(f'Image `{name}` ({shape}; references: ' + ', '.join('refs/' + r for r in refs) + ')')
            lines.append(scene)
            lines.append(SPACE[kind] + ' No lettering.' if 'EXIT' not in scene and 'ZYNTRA RELAY' not in scene and 'PLAY ZONE' not in scene
                         else SPACE[kind] + ' No lettering except the sign named above, spelled exactly.')
            lines.append('')
        (OUT / f'brief_{job}.md').write_text('\n'.join(lines))
    (OUT / 'images.json').write_text(json.dumps([
        dict(name=n, job=j, set=k, shape=s, level=l, references=[R + r for r in refs], scene=scene,
             level_name=LEVEL_NAMES.get(l), tagline=TAGLINES.get(n)) for n, j, k, s, l, refs, scene in IMAGES], indent=1))
    by = {}
    for i in IMAGES:
        by.setdefault(i[2], 0)
        by[i[2]] += 1
    print(len(IMAGES), 'images;', by, '; jobs', {j: sum(1 for i in IMAGES if i[1] == j) for j in jobs})


if __name__ == '__main__':
    main()
