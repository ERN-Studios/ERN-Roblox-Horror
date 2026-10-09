"""Pure helper checks: no real or temporary Git index/ref mutations."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("stage_task", Path(__file__).with_name("stage_task.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ManifestIsolation(unittest.TestCase):
    def baseline(self):
        rows = [{"file": rel, "studioPath": native, "className": cls, "sha256": "before"}
                for rel, (native, cls) in helper.SOURCES.items()]
        rows.append({"file": "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua", "sha256": "other-staged"})
        return {"items": rows, "capturedAtUtc": "other-developer", "unrelatedMetadata": {"keep": True}}

    def test_replace_only_five_rows_preserves_staged_roundui_and_top_level(self):
        baseline = self.baseline()
        original = copy.deepcopy(baseline)
        replacements = helper.task_rows(baseline)
        for row in replacements.values():
            row["sha256"] = "task-native-verified"
        merged = helper.replace_rows(baseline, replacements)
        self.assertEqual(baseline, original)
        self.assertEqual(merged["items"][-1], baseline["items"][-1])
        self.assertEqual(merged["capturedAtUtc"], baseline["capturedAtUtc"])
        self.assertEqual(merged["unrelatedMetadata"], baseline["unrelatedMetadata"])
        self.assertEqual([r["sha256"] for r in merged["items"][:-1]], ["task-native-verified"] * 5)

    def test_wrong_or_duplicate_native_identity_fails(self):
        for mutation in ("duplicate", "wrong"):
            baseline = self.baseline()
            if mutation == "duplicate":
                baseline["items"].append(copy.deepcopy(baseline["items"][0]))
            else:
                baseline["items"][0]["studioPath"] = "Unrelated.Script"
            with self.assertRaises(RuntimeError):
                helper.task_rows(baseline)

    def test_artifact_scope_rejects_snapshots_candidates_secrets_and_other_tasks(self):
        for bad in ["../secret.json", "artifacts/cleanup-20261009/results.md",
                    helper.TASK + "/candidates/Level1.luau", helper.TASK + "/thing.before.luau",
                    helper.TASK + "/sources.json", helper.TASK + "/credentials.json",
                    helper.TASK + "/__pycache__/thing.py", helper.TASK + "/../other.json"]:
            with self.subTest(bad=bad), self.assertRaises(RuntimeError):
                helper.artifact_paths([bad])
        selected = [helper.TASK + "/results.md", helper.TASK + "/assets-moderation.json", helper.TASK + "/stage_task.py"]
        self.assertEqual(helper.artifact_paths(selected), selected)

    def test_duplicate_artifact_and_non_array_fail(self):
        selected = helper.TASK + "/results.md"
        for bad in ([selected, selected], {"artifacts": [selected]}):
            with self.assertRaises(RuntimeError):
                helper.artifact_paths(bad)

    def test_symbolic_branch_identity_guard_is_read_only(self):
        root = Path("example")
        with patch.object(helper, "git", return_value=b"refs/heads/task\n") as mock:
            helper.require_head_ref(root, "refs/heads/task")
            mock.assert_called_once_with(root, "symbolic-ref", "HEAD")
        with patch.object(helper, "git", return_value=b"refs/heads/other\n"):
            with self.assertRaisesRegex(RuntimeError, "HEAD branch changed"):
                helper.require_head_ref(root, "refs/heads/task")
        with patch.object(helper, "git", return_value=b"HEAD\n"):
            with self.assertRaisesRegex(RuntimeError, "attached local branch"):
                helper.head_ref(root)


if __name__ == "__main__":
    unittest.main()
