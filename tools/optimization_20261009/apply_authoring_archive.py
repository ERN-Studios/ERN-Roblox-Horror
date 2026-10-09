"""Root-run scoped AuthoringArchive install; default only prepares local source.

--apply --owner-no-backup honors the owner's explicit 2026-10-09 exception.
Prepare and Apply run together in one fresh ModuleScript invocation. This moves
only the two reviewed Imports folders, preserves originals, and never publishes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from native_probe_runner import (LUA_RUNNER, ROOT, TASK, StudioMcpClient,
                                 find_mcp_batch, literal, load_inputs,
                                 read_source, select_studio, sha, utc)


REVIEWED_UTILITY_SHA = "4b2bb9b7b8ddd7542054cdc143003d982e96af60c62aeb9ee4179eddbf309377"


WRAPPER = r'''
assert(type(Archive)=="table" and type(Archive.Prepare)=="function" and type(Archive.Apply)=="function",
 "Reviewed archive utility did not return its API")
return function(dataModel,editorService,exactProbe,verifyOriginals)
 assert(exactProbe==script and exactProbe.ClassName=="ModuleScript","Exact fresh staging module required")
 local plan,report,moves=nil,nil,{}
 local ok,problem=xpcall(function()
  plan=Archive.Prepare(dataModel,editorService,exactProbe)
  assert(#plan.rows==2,"Expected only the two reviewed import roots")
  for _,row in ipairs(plan.rows) do
   assert(row.name=="ZyntraShopUI" or row.name=="ZyntraHUD","Unreviewed archive target")
   table.insert(moves,{id=row.instance:GetDebugId(0),ownerId=row.owner:GetDebugId(0),name=row.name,
    class=row.instance.ClassName,beforePath=row.beforePath,descendants=row.descendantCount})
  end
  verifyOriginals("after-reference-audit-before-archive-apply")
  report=Archive.Apply(plan) -- same invocation and fresh exact source/reference CAS
  verifyOriginals("after-archive-apply")
  assert(plan.archive and plan.archive.Parent==plan.serverStorage and #plan.archive:GetChildren()==2,
   "Archive wrapper identity or membership mismatch")
  local expectedDescendants=2
  for index,row in ipairs(plan.rows) do
   local pin=moves[index]
   assert(row.instance:GetDebugId(0)==pin.id and row.owner:GetDebugId(0)==pin.ownerId,
    "Archived original identity changed")
   assert(row.owner.Parent==plan.replicatedStorage and row.owner:FindFirstChild("Imports")==nil,
    "Old owner changed or still contains Imports")
   assert(row.wrapper and row.wrapper.Parent==plan.archive and row.wrapper.Name==row.name
    and #row.wrapper:GetChildren()==1 and row.instance.Parent==row.wrapper
    and row.instance.Name=="Imports" and row.instance.ClassName==pin.class,
    "Archived root/wrapper identity mismatch")
   assert(#row.instance:GetDescendants()==row.descendantCount,"Archived membership changed")
   for _,member in ipairs(row.identities) do
    assert(member.instance.Parent==member.parent and member.instance.Name==member.name,
     "Original import hierarchy changed")
   end
   pin.afterPath=row.instance:GetFullName()
   expectedDescendants+=row.descendantCount+1
  end
  assert(#plan.archive:GetDescendants()==expectedDescendants,"Unexpected archive content")
 end,debug.traceback)
 if not ok then
  local rollbackOk,rollbackProblem=true,nil
  if plan and plan.archive then rollbackOk,rollbackProblem=pcall(function() Archive.Rollback(plan) end) end
  error(game:GetService("HttpService"):JSONEncode({problem=tostring(problem),
   rollbackPassed=rollbackOk,rollbackError=if rollbackOk then nil else tostring(rollbackProblem)}),0)
 end
 return {applied=true,report=report,moves=moves,archiveId=plan.archive:GetDebugId(0),
  archivePath=plan.archive:GetFullName(),scannedScripts=#plan.scan.scripts,
  scannedInstanceReferences=#plan.scan.references,excludedProbeId=exactProbe:GetDebugId(0),
  sourceReferenceRule="Reject any literal Imports reference in every current Source/editor except exact fresh probe",
  instanceReferenceRule="Reject external references into either import root; verify reference/source pins immediately before parenting",
  sourceAuditPasses=2,originalsDeleted=false}
end
'''


def prepare():
    sources, _ = load_inputs()
    utility = read_source(TASK / "replication/AuthoringArchive.luau")
    assert sha(utility) == REVIEWED_UTILITY_SHA, "Reviewed AuthoringArchive utility changed; reconcile before applying"
    source = "local Archive = (function()\n" + utility + "\nend)()\n" + WRAPPER
    replacements = {"__EXPECTED__": literal(sources), "__NAME__": literal("authoring-archive"),
                    "__FIXTURE__": literal(utility), "__STAGE__": literal(source),
                    "__WRAPPER_PREFIX__": literal(""), "__WRAPPER_SUFFIX__": literal("")}
    code = LUA_RUNNER
    for marker, value in replacements.items():
        code = code.replace(marker, value)
    # Reuse the reviewed isolation/identity/CAS/finally machinery, but invoke
    # the returned installer with the exact new ModuleScript and source guard.
    assert code.count("local contract=run()") == 1
    code = code.replace("local contract=run()", "local contract=run(game,SES,stage,verifyOriginals)")
    code = code.replace('kind="synthetic-native-contract"', 'kind="authoring-archive-install"')
    return code, source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Root only: move the reviewed Imports folders against fresh Edit guards")
    parser.add_argument("--owner-no-backup", action="store_true", help="Record the owner's explicit instruction not to take a native backup")
    parser.add_argument("--emit", type=Path, default=ROOT / "_local/optimization-20261009/authoring-archive")
    parser.add_argument("--receipt", type=Path, default=TASK / "authoring-archive-receipt.json")
    args = parser.parse_args()
    code, source = prepare()
    args.emit.mkdir(parents=True, exist_ok=True)
    (args.emit / "authoring-archive.runner.luau").write_text(code, encoding="utf-8", newline="\n")
    (args.emit / "authoring-archive.module.luau").write_text(source, encoding="utf-8", newline="\n")
    if not args.apply:
        print(f"Prepared exact archive installer in {args.emit}; no Studio connection or mutation.")
        return
    assert args.owner_no_backup, "Record the explicit owner no-backup instruction with --owner-no-backup"
    installation = json.loads((TASK / "source-install-receipt.json").read_text(encoding="utf-8"))
    assert installation["complete"] is True, "Install the five sources before this archive operation"
    probes = json.loads((TASK / "native-probe-receipt.json").read_text(encoding="utf-8"))
    assert probes["complete"] is True and len(probes["probes"]) == 4 and all(row["passed"] for row in probes["probes"]), \
        "Complete the four isolated contracts before applying the archive"
    receipt = {"kind": "authoring-archive-install", "startedUtc": utc(),
               "placeId": 131311258779917, "universeId": 10559217407,
               "studioName": "[UPDATE] BACKROOMS: STAY QUIET", "complete": False,
               "backupPolicy": "Owner explicitly instructed no native backup (2026-10-09)",
               "utilitySha256": REVIEWED_UTILITY_SHA, "stagedSourceSha256": sha(source),
               "gameplay": False, "performance": False, "multiplayer": False, "published": False}
    def save():
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    client = None
    save()
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        receipt["studioId"] = sid
        result = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
        receipt["result"] = result
        assert result["passed"] and result["originalsPreserved"] and result["cleanupPassed"], \
            "Archive install, original preservation or staging cleanup failed; review receipt"
        contract = result["contract"]
        assert contract["applied"] and contract["originalsDeleted"] is False and len(contract["moves"]) == 2
        receipt["complete"] = True
        print(f"Archived {contract['report']['archivedDescendants']} import descendants; originals and probe cleanup verified.")
    except Exception as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finishedUtc"] = utc()
        save()
        if client is not None:
            client.close()


if __name__ == "__main__":
    main()
