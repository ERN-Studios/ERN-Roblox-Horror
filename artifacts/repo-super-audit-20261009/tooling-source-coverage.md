# Tooling coverage og authoring-grænser

Inventeret: 331 tooling-filer, 275 kodefiler, 258 Python-kilder. Alle Python-kilder er indlæst og AST-parset som hele filer. Dette er strukturel coverage; kun udvalgte konkrete sync/install/test/bot/authoring-forløb er dybt vurderet. Ingen CLI er klassificeret som død alene fordi den ikke importeres af gameplay.

tooling-source-index.json indeholder alle funktioner/classes og loop-counts for hver Python-fil. Tællerne viser struktur, ikke en dokumenteret performancefejl. tooling-nonpython-audit.md supplerer de øvrige scriptfiler. Dato-/historik- og testnavne er ikke et slettebevis.

## Authoring-/værktøjsområder

| Mappe/gruppe | Inventerede filer |
|---|---:|
| plugin/CLI | 2 |
| tools/CLI | 57 |
| tools/discord_trello_bot | 7 |
| tools/leaderboard_backfill | 1 |
| tools/level1_blender | 12 |
| tools/level2_blender | 18 |
| tools/level2_poolrooms | 17 |
| tools/level4_blender | 49 |
| tools/level5_import | 7 |
| tools/luna | 51 |
| tools/purchase_alert_relay | 2 |
| tools/tests | 103 |
| tools/vault | 5 |

## Kodefiler

**D:** målrettet dyb kilde/caller-review af relevante flows. **S:** komplet strukturel læsning/index med afgrænsede hotspots; ikke hver mulig branch manuelt valideret. **N:** se den separate non-Python-rapport. Bevar manuelle authoring/rollback entrypoints indtil deres workflow er valgt.

| Fil | Linjer | Dybde | Structural evidence |
|---|---:|---|---|
| plugin/MasterTuningPlugin.server.lua | 350 | D | inventory/hash; separat review |
| plugin/build_plugin.py | 98 | D | 4 funcs; 0 loops; AST OK |
| tools/apply_to_studio.cmd | 76 | D | inventory/hash; separat review |
| tools/apply_trello_ui_finishing.py | 53 | S | 1 funcs; 2 loops; AST OK |
| tools/bake_actual_hide_pose.py | 76 | S | 0 funcs; 0 loops; AST OK |
| tools/blender_mcp_client.py | 36 | S | 1 funcs; 1 loops; AST OK |
| tools/build_actual_table_hide.py | 83 | S | 0 funcs; 0 loops; AST OK |
| tools/build_corrected_entity_actions.py | 150 | S | 9 funcs; 5 loops; AST OK |
| tools/build_entity_kill_animation.py | 259 | S | 4 funcs; 14 loops; AST OK |
| tools/build_restrained_walk.py | 63 | S | 3 funcs; 2 loops; AST OK |
| tools/build_table_hide_blender.py | 143 | S | 0 funcs; 0 loops; AST OK |
| tools/capture_elevator_90s.py | 96 | S | 2 funcs; 2 loops; AST OK |
| tools/capture_entity_actions.py | 104 | S | 2 funcs; 1 loops; AST OK |
| tools/capture_flashlight_test.py | 148 | S | 2 funcs; 1 loops; AST OK |
| tools/capture_ui_regressions.py | 73 | S | 2 funcs; 1 loops; AST OK |
| tools/discord_trello_bot/bot.py | 177 | D | 15 funcs; 7 loops; AST OK |
| tools/discord_trello_bot/post.py | 40 | S | 1 funcs; 1 loops; AST OK |
| tools/discord_trello_bot/setup_server.py | 141 | S | 6 funcs; 6 loops; AST OK |
| tools/discord_trello_bot/test_bot.py | 21 | S | 0 funcs; 0 loops; AST OK |
| tools/export_entity_animations.py | 96 | S | 1 funcs; 4 loops; AST OK |
| tools/export_entity_keyframes.py | 120 | D | 1 funcs; 4 loops; AST OK |
| tools/export_entity_keyframes_retargeted.py | 377 | S | 8 funcs; 11 loops; AST OK |
| tools/export_level1_facelift_baseline.py | 115 | S | 1 funcs; 3 loops; AST OK |
| tools/export_level1_facelift_verified.py | 300 | S | 6 funcs; 3 loops; AST OK |
| tools/finish_sales_reconciliation.py | 85 | S | 0 funcs; 0 loops; AST OK |
| tools/fit_actual_hide_pose.py | 70 | S | 4 funcs; 3 loops; AST OK |
| tools/inspect_blender_actions.py | 96 | S | 2 funcs; 5 loops; AST OK |
| tools/install_new_scripts.py | 129 | D | 4 funcs; 2 loops; AST OK |
| tools/install_trello_new_scripts.py | 47 | D | 1 funcs; 1 loops; AST OK |
| tools/leaderboard_backfill/generate_backfill.py | 213 | S | 6 funcs; 8 loops; AST OK |
| tools/level1_blender/build.py | 574 | S | 20 funcs; 50 loops; AST OK |
| tools/level1_blender/build_v2.py | 390 | S | 11 funcs; 50 loops; AST OK |
| tools/level1_blender/check_assets.py | 97 | S | 1 funcs; 12 loops; AST OK |
| tools/level1_blender/elevator_inset.py | 345 | S | 12 funcs; 32 loops; AST OK |
| tools/level1_blender/export_fixture_reference.py | 67 | S | 1 funcs; 2 loops; AST OK |
| tools/level1_blender/import_assets.py | 223 | S | 4 funcs; 7 loops; AST OK |
| tools/level1_blender/import_elevator_inset.py | 123 | S | 3 funcs; 1 loops; AST OK |
| tools/level1_blender/install_sources.py | 165 | S | 5 funcs; 6 loops; AST OK |
| tools/level1_blender/prepare_v2_textures.py | 85 | S | 2 funcs; 6 loops; AST OK |
| tools/level1_blender/publish_textures.py | 60 | S | 1 funcs; 1 loops; AST OK |
| tools/level1_blender/verify_native.py | 57 | S | 0 funcs; 4 loops; AST OK |
| tools/level2_arch_rib_obj.py | 160 | S | 10 funcs; 2 loops; AST OK |
| tools/level2_blender/build.py | 46 | S | 1 funcs; 2 loops; AST OK |
| tools/level2_blender/fix_tiles.py | 52 | S | 3 funcs; 1 loops; AST OK |
| tools/level2_blender/import_kit.py | 1464 | S | 46 funcs; 42 loops; AST OK |
| tools/level2_blender/kit.py | 291 | S | 18 funcs; 12 loops; AST OK |
| tools/level2_blender/make_bands.py | 20 | S | 0 funcs; 2 loops; AST OK |
| tools/level2_blender/make_pbr_all.py | 25 | S | 0 funcs; 1 loops; AST OK |
| tools/level2_blender/modules_arch.py | 630 | S | 32 funcs; 63 loops; AST OK |
| tools/level2_blender/modules_extra.py | 585 | S | 29 funcs; 90 loops; AST OK |
| tools/level2_blender/modules_tunnel.py | 624 | S | 23 funcs; 46 loops; AST OK |
| tools/level2_blender/plot_layouts.py | 54 | S | 1 funcs; 3 loops; AST OK |
| tools/level2_blender/props_meshy.py | 422 | S | 12 funcs; 20 loops; AST OK |
| tools/level2_blender/props_small.py | 428 | S | 13 funcs; 40 loops; AST OK |
| tools/level2_blender/review.py | 626 | S | 26 funcs; 78 loops; AST OK |
| tools/level2_blender/rooms_small.py | 645 | S | 37 funcs; 79 loops; AST OK |
| tools/level2_blender/slides.py | 1213 | S | 47 funcs; 90 loops; AST OK |
| tools/level2_blender/smoke.py | 29 | S | 0 funcs; 1 loops; AST OK |
| tools/level2_poolrooms/assemble_level.py | 716 | S | 30 funcs; 55 loops; AST OK |
| tools/level2_poolrooms/backface_check.py | 64 | S | 1 funcs; 4 loops; AST OK |
| tools/level2_poolrooms/build.py | 43 | S | 1 funcs; 3 loops; AST OK |
| tools/level2_poolrooms/collision_audit.py | 1055 | S | 45 funcs; 57 loops; AST OK |
| tools/level2_poolrooms/dump_world.py | 181 | S | 7 funcs; 5 loops; AST OK |
| tools/level2_poolrooms/lattice_audit.py | 1404 | S | 58 funcs; 70 loops; AST OK |
| tools/level2_poolrooms/modules_arch.py | 2400 | S | 156 funcs; 134 loops; AST OK |
| tools/level2_poolrooms/modules_swerve.py | 864 | S | 43 funcs; 71 loops; AST OK |
| tools/level2_poolrooms/modules_tunnel.py | 1763 | S | 70 funcs; 117 loops; AST OK |
| tools/level2_poolrooms/objectives.py | 1709 | S | 83 funcs; 103 loops; AST OK |
| tools/level2_poolrooms/prkit.py | 393 | S | 25 funcs; 14 loops; AST OK |
| tools/level2_poolrooms/render_world.py | 701 | S | 26 funcs; 29 loops; AST OK |
| tools/level2_poolrooms/smoke.py | 29 | S | 0 funcs; 1 loops; AST OK |
| tools/level2_poolrooms/smoke_tmp.py | 0 | S | 0 funcs; 0 loops; AST OK |
| tools/level2_poolrooms/textures.py | 22 | S | 0 funcs; 1 loops; AST OK |
| tools/level2_poolrooms/world_audit.py | 1774 | S | 68 funcs; 85 loops; AST OK |
| tools/level2_poolrooms/world_check.py | 644 | S | 24 funcs; 37 loops; AST OK |
| tools/level4_blender/Level4LightingController.client.lua | 260 | N | inventory/hash; separat review |
| tools/level4_blender/PushDoors.server.lua | 160 | N | inventory/hash; separat review |
| tools/level4_blender/arch_detail.py | 1941 | S | 91 funcs; 149 loops; AST OK |
| tools/level4_blender/audit_final4_delivery_native.py | 54 | S | 0 funcs; 2 loops; AST OK |
| tools/level4_blender/build_all.py | 135 | S | 5 funcs; 2 loops; AST OK |
| tools/level4_blender/build_base.py | 304 | S | 16 funcs; 8 loops; AST OK |
| tools/level4_blender/ceilings.py | 2739 | S | 111 funcs; 235 loops; AST OK |
| tools/level4_blender/collect_final4_delivery.py | 134 | S | 3 funcs; 13 loops; AST OK |
| tools/level4_blender/cull_hidden.py | 1519 | S | 45 funcs; 60 loops; AST OK |
| tools/level4_blender/doors.py | 135 | S | 2 funcs; 11 loops; AST OK |
| tools/level4_blender/doors_v2.py | 1067 | S | 44 funcs; 68 loops; AST OK |
| tools/level4_blender/export_l4.py | 787 | S | 31 funcs; 31 loops; AST OK |
| tools/level4_blender/import_meshy.py | 407 | S | 18 funcs; 14 loops; AST OK |
| tools/level4_blender/layout_edits.py | 609 | S | 27 funcs; 44 loops; AST OK |
| tools/level4_blender/lights_and_camera.py | 97 | S | 5 funcs; 2 loops; AST OK |
| tools/level4_blender/make_pbr.py | 135 | S | 6 funcs; 3 loops; AST OK |
| tools/level4_blender/make_pbr_all.py | 27 | S | 0 funcs; 1 loops; AST OK |
| tools/level4_blender/make_place.py | 418 | S | 18 funcs; 19 loops; AST OK |
| tools/level4_blender/make_textures.py | 42 | S | 2 funcs; 2 loops; AST OK |
| tools/level4_blender/place.luau | 680 | N | inventory/hash; separat review |
| tools/level4_blender/place_driver.py | 87 | S | 3 funcs; 5 loops; AST OK |
| tools/level4_blender/place_phases.luau | 339 | N | inventory/hash; separat review |
| tools/level4_blender/props.py | 564 | S | 35 funcs; 31 loops; AST OK |
| tools/level4_blender/props_decay.py | 1290 | S | 53 funcs; 93 loops; AST OK |
| tools/level4_blender/props_lobby.py | 1529 | S | 82 funcs; 101 loops; AST OK |
| tools/level4_blender/props_rooms.py | 2806 | S | 102 funcs; 237 loops; AST OK |
| tools/level4_blender/round_assets.py | 550 | S | 25 funcs; 39 loops; AST OK |
| tools/level4_blender/serve.py | 61 | S | 5 funcs; 1 loops; AST OK |
| tools/level4_blender/slots.py | 202 | S | 4 funcs; 2 loops; AST OK |
| tools/level4_blender/studio_upload.py | 123 | S | 1 funcs; 8 loops; AST OK |
| tools/level4_blender/upload.luau | 85 | N | inventory/hash; separat review |
| tools/level4_blender/usher_nav.py | 519 | S | 21 funcs; 44 loops; AST OK |
| tools/level5_import/export_l5.py | 225 | S | 9 funcs; 15 loops; AST OK |
| tools/level5_import/make_place.py | 55 | S | 1 funcs; 2 loops; AST OK |
| tools/level5_import/place.luau | 135 | N | inventory/hash; separat review |
| tools/level5_import/serve.py | 60 | S | 5 funcs; 1 loops; AST OK |
| tools/level5_import/upload.luau | 80 | N | inventory/hash; separat review |
| tools/luna/anim/build_all.py | 24 | S | 0 funcs; 4 loops; AST OK |
| tools/luna/anim/check_clips.py | 94 | S | 5 funcs; 5 loops; AST OK |
| tools/luna/anim/clips_belly.py | 1400 | S | 88 funcs; 75 loops; AST OK |
| tools/luna/anim/clips_loco.py | 531 | S | 30 funcs; 13 loops; AST OK |
| tools/luna/anim/clips_sit.py | 673 | S | 51 funcs; 32 loops; AST OK |
| tools/luna/anim/clips_sleep.py | 586 | S | 38 funcs; 35 loops; AST OK |
| tools/luna/anim/lunalib.py | 173 | S | 15 funcs; 11 loops; AST OK |
| tools/luna/anim/render_clip.py | 24 | S | 0 funcs; 1 loops; AST OK |
| tools/luna/anim/sheet.py | 42 | S | 1 funcs; 1 loops; AST OK |
| tools/luna/bed_prep.py | 48 | S | 0 funcs; 4 loops; AST OK |
| tools/luna/build_rig.py | 69 | S | 0 funcs; 4 loops; AST OK |
| tools/luna/export_glb.py | 28 | S | 0 funcs; 3 loops; AST OK |
| tools/luna/glb_to_rbxmx.py | 237 | S | 15 funcs; 11 loops; AST OK |
| tools/luna/inspect_glb.py | 43 | S | 0 funcs; 3 loops; AST OK |
| tools/luna/landmarks.py | 43 | S | 0 funcs; 5 loops; AST OK |
| tools/luna/mcp.py | 40 | S | 0 funcs; 1 loops; AST OK |
| tools/luna/normalize.py | 53 | S | 0 funcs; 1 loops; AST OK |
| tools/luna/overlay.py | 45 | S | 0 funcs; 2 loops; AST OK |
| tools/luna/paint_closed_eyes.py | 390 | S | 13 funcs; 11 loops; AST OK |
| tools/luna/player_pet_anim.luau | 120 | N | inventory/hash; separat review |
| tools/luna/posetest.py | 39 | S | 2 funcs; 3 loops; AST OK |
| tools/luna/render_views.py | 47 | S | 0 funcs; 2 loops; AST OK |
| tools/luna/straighten.py | 42 | S | 0 funcs; 2 loops; AST OK |
| tools/luna/studio.py | 42 | S | 1 funcs; 0 loops; AST OK |
| tools/luna/upload_asset.py | 113 | S | 3 funcs; 2 loops; AST OK |
| tools/playtest_dev_phone.py | 355 | S | 4 funcs; 0 loops; AST OK |
| tools/playtest_devcheats_level2.py | 142 | S | 1 funcs; 0 loops; AST OK |
| tools/playtest_entity_kill.py | 145 | S | 1 funcs; 0 loops; AST OK |
| tools/playtest_fuse_relays.py | 136 | S | 1 funcs; 1 loops; AST OK |
| tools/playtest_level1.py | 517 | S | 1 funcs; 1 loops; AST OK |
| tools/playtest_level1_cleanup.py | 103 | S | 1 funcs; 1 loops; AST OK |
| tools/playtest_level3_hidden_chase.luau | 197 | N | inventory/hash; separat review |
| tools/playtest_level3_table_outcomes.luau | 304 | N | inventory/hash; separat review |
| tools/playtest_lobby_avatar_transition.py | 165 | S | 2 funcs; 1 loops; AST OK |
| tools/playtest_ui_pit_regressions.py | 189 | S | 1 funcs; 1 loops; AST OK |
| tools/pool_slide_rig_to_glb.py | 233 | S | 9 funcs; 15 loops; AST OK |
| tools/prepare_table_hide_pose.py | 108 | S | 7 funcs; 10 loops; AST OK |
| tools/preview_actual_hide_pose.py | 52 | S | 0 funcs; 0 loops; AST OK |
| tools/publish_elevator_textures.py | 77 | S | 2 funcs; 1 loops; AST OK |
| tools/publish_entity_animations.py | 190 | D | 3 funcs; 4 loops; AST OK |
| tools/publish_lobby_concrete_textures.py | 77 | S | 2 funcs; 1 loops; AST OK |
| tools/publish_table_hide_animation.py | 72 | S | 2 funcs; 0 loops; AST OK |
| tools/pull_source_from_studio.py | 377 | D | 7 funcs; 16 loops; AST OK |
| tools/purchase_alert_relay/relay.py | 184 | S | 9 funcs; 3 loops; AST OK |
| tools/push_repo_to_studio.py | 792 | D | 16 funcs; 19 loops; AST OK |
| tools/record_pending_push.py | 124 | S | 2 funcs; 5 loops; AST OK |
| tools/record_synced_source.py | 108 | S | 1 funcs; 3 loops; AST OK |
| tools/restore-live-assets.sh | 37 | N | inventory/hash; separat review |
| tools/restore-poolslide-assets.py | 99 | S | 4 funcs; 5 loops; AST OK |
| tools/restore-slidemouth-assets.sh | 37 | N | inventory/hash; separat review |
| tools/serve_shop_upload.py | 24 | S | 2 funcs; 0 loops; AST OK |
| tools/stage_push_payload.py | 124 | S | 3 funcs; 2 loops; AST OK |
| tools/studio_compile_probe.luau | 69 | N | inventory/hash; separat review |
| tools/studio_parity_probe.luau | 53 | N | inventory/hash; separat review |
| tools/studio_source_contract.py | 157 | D | 11 funcs; 1 loops; AST OK |
| tools/studio_tool_info.py | 33 | S | 1 funcs; 1 loops; AST OK |
| tools/sync_from_studio.py | 694 | D | 30 funcs; 13 loops; AST OK |
| tools/tests/fakestudio.py | 253 | S | 10 funcs; 2 loops; AST OK |
| tools/tests/hud_harness.luau | 580 | N | inventory/hash; separat review |
| tools/tests/test_controller_input.py | 903 | D | 8 funcs; 3 loops; AST OK |
| tools/tests/test_daily_rewards.py | 1209 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_death_advice.py | 485 | S | 4 funcs; 4 loops; AST OK |
| tools/tests/test_death_scream_level1_only.py | 77 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_dev_free_respawn_offer.py | 110 | S | 2 funcs; 1 loops; AST OK |
| tools/tests/test_donation_board_columns.py | 473 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_equipment_hud.py | 1828 | S | 2 funcs; 1 loops; AST OK |
| tools/tests/test_feedback_gift.py | 188 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_first_entry_guide.py | 381 | D | 1 funcs; 0 loops; AST OK |
| tools/tests/test_first_login_flag.py | 233 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_flashlight_player_control.py | 947 | S | 6 funcs; 4 loops; AST OK |
| tools/tests/test_flashlight_profiles.py | 43 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_friend_boost.py | 1390 | D | 3 funcs; 0 loops; AST OK |
| tools/tests/test_full_sync_contract.py | 545 | D | 9 funcs; 3 loops; AST OK |
| tools/tests/test_hud_b6_b7.py | 262 | S | 1 funcs; 1 loops; AST OK |
| tools/tests/test_hud_b8.py | 464 | S | 3 funcs; 3 loops; AST OK |
| tools/tests/test_item_inventory.py | 538 | D | 2 funcs; 0 loops; AST OK |
| tools/tests/test_leaderboard_backfill.py | 517 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_level1_blender_default.py | 53 | S | 2 funcs; 5 loops; AST OK |
| tools/tests/test_level1_blender_import.py | 29 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_level1_cable_current.py | 277 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_level1_entity_animation.py | 317 | S | 1 funcs; 1 loops; AST OK |
| tools/tests/test_level1_light_polish.py | 63 | S | 1 funcs; 1 loops; AST OK |
| tools/tests/test_level1_preview_allocation.py | 109 | S | 3 funcs; 1 loops; AST OK |
| tools/tests/test_level1_quality.py | 238 | S | 2 funcs; 1 loops; AST OK |
| tools/tests/test_level1_quality_qa.py | 102 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_level1_readability.py | 90 | S | 0 funcs; 1 loops; AST OK |
| tools/tests/test_level1_relay_spawns.py | 107 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level1_team_prompts.py | 353 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_level2_blender_preview.py | 445 | S | 3 funcs; 3 loops; AST OK |
| tools/tests/test_level2_blender_preview_access.py | 670 | S | 2 funcs; 2 loops; AST OK |
| tools/tests/test_level2_exit_bore.py | 410 | S | 15 funcs; 27 loops; AST OK |
| tools/tests/test_level2_exit_stair.py | 459 | S | 25 funcs; 28 loops; AST OK |
| tools/tests/test_level2_kit_collision.py | 220 | S | 12 funcs; 10 loops; AST OK |
| tools/tests/test_level2_kit_import.py | 864 | D | 11 funcs; 12 loops; AST OK |
| tools/tests/test_level2_kit_layout.py | 1057 | D | 31 funcs; 53 loops; AST OK |
| tools/tests/test_level2_kit_navigation.py | 358 | S | 4 funcs; 2 loops; AST OK |
| tools/tests/test_level2_kit_world_builder.py | 3495 | S | 93 funcs; 191 loops; AST OK |
| tools/tests/test_level2_newmap_feedback.py | 914 | S | 4 funcs; 1 loops; AST OK |
| tools/tests/test_level2_pool_slide_release.py | 337 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level2_queue_gate.py | 398 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level2_tile_face_culling.py | 305 | S | 4 funcs; 3 loops; AST OK |
| tools/tests/test_level2_tunnel_height.py | 240 | S | 7 funcs; 16 loops; AST OK |
| tools/tests/test_level2_world_audit.py | 425 | S | 16 funcs; 14 loops; AST OK |
| tools/tests/test_level3_first_cd.py | 342 | S | 5 funcs; 2 loops; AST OK |
| tools/tests/test_level3_first_cd_prompt.py | 130 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level3_flashlight_timeline.py | 380 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_level3_hidden_chase.py | 558 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level3_hide_animation.py | 161 | S | 3 funcs; 1 loops; AST OK |
| tools/tests/test_level3_run_in_exit.py | 367 | S | 2 funcs; 1 loops; AST OK |
| tools/tests/test_level3_slide_aperture.py | 318 | S | 13 funcs; 15 loops; AST OK |
| tools/tests/test_level3_square_layout.py | 278 | S | 3 funcs; 0 loops; AST OK |
| tools/tests/test_level3_steering.py | 233 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level3_table_flush.py | 231 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_level4_clear_persistence.py | 185 | D | 4 funcs; 0 loops; AST OK |
| tools/tests/test_level4_note_keypad.py | 234 | S | 4 funcs; 3 loops; AST OK |
| tools/tests/test_level4_queue_choice.py | 537 | D | 4 funcs; 3 loops; AST OK |
| tools/tests/test_lobby_palette.py | 338 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_lobby_shop_display.py | 1189 | S | 3 funcs; 5 loops; AST OK |
| tools/tests/test_lucky_wheel_client.py | 1558 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_no_level3_continue.py | 99 | S | 2 funcs; 1 loops; AST OK |
| tools/tests/test_objective_receivers.py | 253 | S | 4 funcs; 1 loops; AST OK |
| tools/tests/test_pool_foam_audio.py | 225 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_pool_foam_navigation.py | 281 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_pool_foam_separation.py | 673 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_pool_foam_sight_rule.py | 163 | S | 4 funcs; 1 loops; AST OK |
| tools/tests/test_pool_slide_audio_states.py | 426 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_pool_slide_navigation.py | 336 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_purchase_alert_relay.py | 184 | D | 12 funcs; 1 loops; AST OK |
| tools/tests/test_purchase_alerts.py | 400 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_push_repo_to_studio.py | 1133 | S | 41 funcs; 13 loops; AST OK |
| tools/tests/test_queue_barrier.py | 374 | S | 4 funcs; 0 loops; AST OK |
| tools/tests/test_rail_dots_intro.py | 94 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_reentry_dismissal.py | 266 | D | 2 funcs; 0 loops; AST OK |
| tools/tests/test_round_entry_client.py | 297 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_round_exit_hold.py | 12 | S | 0 funcs; 0 loops; AST OK |
| tools/tests/test_round_hud.py | 551 | S | 5 funcs; 2 loops; AST OK |
| tools/tests/test_round_hud_local.py | 867 | S | 7 funcs; 3 loops; AST OK |
| tools/tests/test_round_hud_shared.py | 832 | D | 3 funcs; 3 loops; AST OK |
| tools/tests/test_round_loading_host.py | 485 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_round_loading_notice.py | 262 | S | 2 funcs; 4 loops; AST OK |
| tools/tests/test_route_markers.py | 593 | D | 1 funcs; 0 loops; AST OK |
| tools/tests/test_spectate_audio_gates.py | 103 | D | 2 funcs; 0 loops; AST OK |
| tools/tests/test_spectate_parity.py | 172 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_spectator_count.py | 71 | S | 0 funcs; 0 loops; AST OK |
| tools/tests/test_spectator_vitals.py | 47 | S | 0 funcs; 0 loops; AST OK |
| tools/tests/test_speed_potion.py | 290 | D | 3 funcs; 0 loops; AST OK |
| tools/tests/test_studio_source_contract.py | 304 | D | 2 funcs; 3 loops; AST OK |
| tools/tests/test_support_product_receipts.py | 363 | D | 2 funcs; 0 loops; AST OK |
| tools/tests/test_token_grants.py | 331 | D | 2 funcs; 0 loops; AST OK |
| tools/tests/test_touch_control_plan.py | 383 | S | 1 funcs; 2 loops; AST OK |
| tools/tests/test_ui_regression_shared.py | 497 | D | 4 funcs; 0 loops; AST OK |
| tools/tests/test_ui_style.py | 320 | S | 2 funcs; 0 loops; AST OK |
| tools/tests/test_zyntra_analytics.py | 546 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_zyntra_challenges.py | 183 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_zyntra_detector_client.py | 389 | S | 1 funcs; 1 loops; AST OK |
| tools/tests/test_zyntra_dev_chip.py | 239 | S | 1 funcs; 0 loops; AST OK |
| tools/tests/test_zyntra_store_compact.py | 1623 | S | 5 funcs; 6 loops; AST OK |
| tools/update_backfill_tests.py | 65 | S | 0 funcs; 0 loops; AST OK |
| tools/vault/build_systems.py | 769 | D | 2 funcs; 1 loops; AST OK |
| tools/vault/build_vault.py | 726 | D | 18 funcs; 30 loops; AST OK |
| tools/vault/fix_folders.py | 164 | S | 6 funcs; 12 loops; AST OK |
| tools/vault/graph_cfg.py | 78 | S | 1 funcs; 0 loops; AST OK |
| tools/verify_studio_parity.py | 160 | S | 4 funcs; 5 loops; AST OK |

## Afgrænsning

D er review af de konkrete relevante flows, ikke et løfte om at enhver Blender/operator/testgren har været kørt. De 2.109 historiske kodefiler i artifacts/drafts/extracted er hash-/scopeindekseret i repo-inventory.csv, ikke 2.109 aktive moduler. G:/Blender, eksterne repos, publicerede assetbodies og live Roblox-profiler er uden for dette workspace-auditgrundlag.
