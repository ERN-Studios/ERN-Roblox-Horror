#!/usr/bin/env python3
"""Assemble source provenance, Roblox formats, and objective audio QC."""

from __future__ import annotations

import json
import hashlib
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SPECS = {
    "party_hall_ambience": {
        "generation_id": "AxpNKfZxsRv9JeOBfbJl", "node_id": "MI6WCcIT0ioPDEX2sM48",
        "role": "looped ambience: beige party hall and birthday rooms",
        "prompt": "Quiet abandoned 1990s mall birthday party hall at night. A soft fluorescent tube hum, distant HVAC airflow, very occasional ceiling tile tick and loose paper decoration rustle in a tiled room. Restrained eerie realism, subtle stereo depth, even low ambience, no people, no voices, no music, no scream, no digital crackle or hiss.",
    },
    "budget_arcade_ambience": {
        "generation_id": "IbXegJWW4oOAcTXps0JO", "node_id": "E21mnMmNv4WxBnTJrBTJ",
        "role": "looped ambience: budget arcade zone",
        "prompt": "Abandoned budget arcade in a 1990s shopping mall. A few distant coin-op cabinets emit isolated low analog bleeps and short relay ticks over a very soft electrical transformer hum and room air. Sparse irregular events with clear gaps, dusty empty room reverb, no melody, no voices, no music, no exaggerated static or broadband hiss.",
    },
    "maintenance_workshop_ambience": {
        "generation_id": "LuSXm53viloKLhBMxSeF", "node_id": "SHvxN1H4amd7XmJCUzM2",
        "role": "looped ambience: maintenance workshop zone",
        "prompt": "Empty back-of-mall maintenance workshop at night. Old ventilation motor turns steadily at low volume, a pipe pings occasionally and a loose vent flap taps once in the distance. Sparse, ominous physical room tone, realistic perspective, no voices, no music, no electrical static or white noise.",
    },
    "arcade_credit_button": {
        "generation_id": "AvQ6vRECs9bEtzesXpTq", "node_id": "0q4xSInsAkZcY7dJAERs",
        "role": "one-shot: arcade PlayPrompt / credit confirmation",
        "prompt": "One close-up interaction in a 1990s coin-op arcade cabinet: a plastic button depresses with a tactile click, a coin-credit relay clacks, then a brief low two-note synthesized confirmation blip decays into true silence. Dry mechanical detail, no background ambience, no music, no speech, no hiss.",
    },
    "breaker_switch": {
        "generation_id": "qPkp6y7iWo3ZTdTUJLau", "node_id": "fMkrYyTb4W2pXryMjVrO",
        "role": "one-shot: maintenance power-switch interaction candidate",
        "prompt": "One close-up maintenance breaker switch being pulled down and reset: hard plastic lever clack, short electrical contact thunk, a restrained metallic cabinet resonance fading into true silence. Realistic physical sound, no buzz after the action, no ambience, no speech, no music, no hiss.",
    },
}


def probe(path: Path) -> dict:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "stream=codec_name,sample_rate,channels,bits_per_raw_sample:format=duration,size",
         "-of", "json", str(path)], capture_output=True, text=True, check=True,
    )
    data = json.loads(result.stdout)
    stream = data["streams"][0]
    fmt = data["format"]
    return {
        "path": str(path.relative_to(REPO)),
        "codec": stream["codec_name"],
        "sample_rate_hz": int(stream["sample_rate"]),
        "channels": stream["channels"],
        "bits_per_sample": int(stream["bits_per_raw_sample"]) if stream.get("bits_per_raw_sample") else None,
        "duration_seconds_container": float(fmt["duration"]),
        "bytes": int(fmt["size"]),
    }


def main() -> None:
    builds = json.loads((ROOT / "build-results.json").read_text())
    final_qc = json.loads((ROOT / "final-qc.json").read_text())
    raw_qc = json.loads((ROOT / "raw-qc.json").read_text())
    result = {
        "package": "Level 6 Worn Party — offline audio palette",
        "created_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "status": "Offline assets only; no Roblox audio IDs uploaded or bound in Studio.",
        "source": {
            "provider": "ElevenLabs Creative Studio Sound Effects",
            "model_id": "eleven_text_to_sound_v2",
            "flow_id": "Zlw8w6brtdpGTVh66twg",
            "flow_url": "https://elevenlabs.io/app/flows/Zlw8w6brtdpGTVh66twg",
            "generation_settings": {"prompt_influence": 0.75, "variations_per_prompt": 4},
            "license_status": "Workspace subscription tier was not exposed by the connector; verify the ElevenLabs plan permits commercial use before importing into a monetized experience.",
            "license_terms_url": "https://elevenlabs.io/docs/overview/administration/billing",
            "sound_effects_terms_url": "https://elevenlabs.io/sound-effects-terms",
        },
        "roblox_import": {
            "recommended": "Use 48 kHz stereo 24-bit PCM WAV masters for ambience loops and one-shots. 48 kHz stereo 192 kb/s MP3 alternatives are included.",
            "official_requirements_url": "https://create.roblox.com/docs/audio/assets",
            "all_deliverables_under_20_mb": True,
            "transcode_and_in_studio_listening_test_pending": True,
        },
        "assets": [],
    }
    for build in builds:
        name = build["name"]
        spec = SPECS[name]
        selected_raw_qc = next(x for x in raw_qc if x["path"].endswith(
            f"{name}-elevenlabs-take{build['selected_take']}.mp3"))
        wav_qc = next(x for x in final_qc if x["path"].endswith(f"mastered/{name}.wav"))
        mp3_qc = next(x for x in final_qc if x["path"].endswith(f"mastered/{name}.mp3"))
        wav = probe(ROOT / build["wav"])
        mp3 = probe(ROOT / build["mp3"])
        for key, digest in (("raw", "raw_sha256"), ("wav", "wav_sha256"), ("mp3", "mp3_sha256")):
            actual = hashlib.sha256((ROOT / build[key]).read_bytes()).hexdigest()
            assert actual == build[digest], f"Changed audio file: {build[key]}"
        assert wav["sample_rate_hz"] == mp3["sample_rate_hz"] == 48000
        assert wav["channels"] == mp3["channels"] == 2
        assert wav["bytes"] < 20_000_000 and mp3["bytes"] < 20_000_000
        assert not wav_qc["loop_boundary_exceeds_natural_p99_9"]
        assert not mp3_qc["loop_boundary_exceeds_natural_p99_9"]
        if not build["loop"]:
            assert wav_qc["peak_dbfs"] <= -6 and mp3_qc["peak_dbfs"] <= -6
        result["assets"].append({
            "name": name,
            "role": spec["role"],
            "loop": build["loop"],
            "generation_id": spec["generation_id"],
            "flow_node_id": spec["node_id"],
            "prompt": spec["prompt"],
            "selected_take": build["selected_take"],
            "source_mp3": {"path": str((ROOT / build["raw"]).relative_to(REPO)),
                           "sha256": build["raw_sha256"], "qc": selected_raw_qc},
            "master_wav": {**wav, "sha256": build["wav_sha256"], "qc": wav_qc},
            "upload_mp3": {**mp3, "sha256": build["mp3_sha256"], "qc": mp3_qc},
            "processing": {key: build[key] for key in
                           ("filters", "overlap_ms", "fade_in_ms", "fade_out_ms", "gain_db")},
        })
    (ROOT / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Manifest: {len(result['assets'])} assets; all format and objective QC assertions passed")


if __name__ == "__main__":
    main()
