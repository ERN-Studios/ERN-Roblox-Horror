"""Offline wrapper compilation and receipt-parser checks; never connects to Studio."""
from pathlib import Path
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
import native_compatibility_runner as runner


def main():
    sources, budget, fixtures = runner.reviewed_inputs()
    emit = runner.ROOT / "_local/optimization-20261009/native-compatibility-probes"
    compiler = str(Path(os.environ["LUAU_BIN"]).with_name("luau-compile.exe"))
    compiled = []
    for name, filename, expected in runner.PROBES:
        for suffix in ("runner", "module"):
            path = emit / f"{name}.{suffix}.luau"
            result = subprocess.run([compiler, str(path)], capture_output=True, text=True)
            assert result.returncode == 0, result.stderr + result.stdout
            compiled.append({"name":path.name, "sha256":runner.sha(runner.read_source(path))})
    count = 0
    def valid(name, contract, expected):
        nonlocal count
        assert runner.assertion_count(name, {"contract":contract}) == expected
        count += 1
    def invalid(name, contract):
        nonlocal count
        try:
            runner.assertion_count(name, {"contract":contract})
        except (AssertionError, KeyError):
            count += 1
        else:
            raise AssertionError("Malformed native result was accepted")
    valid("streaming-lifecycle-contract", {"result":True,"output":["STREAMING_LIFECYCLE_CHECKS=841"]}, 841)
    invalid("streaming-lifecycle-contract", {"result":False,"output":["STREAMING_LIFECYCLE_CHECKS=841"]})
    invalid("streaming-lifecycle-contract", {"result":True,"output":[]})
    invalid("streaming-lifecycle-contract", {"result":True,"output":["STREAMING_LIFECYCLE_CHECKS=841"]*2})
    valid("streaming-native-instances", {"result":{"nativeFixtureChecks":10,"realStreamingGameplayPerformancePass":False}}, 10)
    invalid("streaming-native-instances", {"result":True})
    invalid("streaming-native-instances", {"result":{"nativeFixtureChecks":10,"realStreamingGameplayPerformancePass":True}})
    invalid("streaming-native-instances", {"result":{"realStreamingGameplayPerformancePass":False}})
    receipt = {"offlineOnly":True, "studioMutation":False, "nativeExecutedByThisCheck":False,
        "compiler":compiler, "compiled":compiled, "receiptParserChecks":count,
        "productionFixtureHelpersVerified":True, "expectedInstalledSources":len(sources),
        "fixtures":{name:runner.sha(source) for name,source in fixtures.items()}}
    (runner.HERE / "runner-preparation-result.json").write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    print(f"Compiled {len(compiled)} emitted wrappers; {count} receipt parser checks; seven exact source and fixture helper pins.")


if __name__ == "__main__":
    main()
