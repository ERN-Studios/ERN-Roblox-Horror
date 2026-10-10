"""Read-only repeatable actual helper and native-template compiler ports.

The receipt directory must be new. Runtime/native calls and canonical file
mutations are not available through this entry point.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import subprocess
import sys
import tempfile

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("exit_literal_scoped_review",HERE/"apply_exit_literal_cleanup.py")
app=importlib.util.module_from_spec(spec);spec.loader.exec_module(app)


def main(destination):
    assert not destination.exists(),"Preserve immutable prior review receipt"
    before,after,old,_,request,template=app.scope()
    originals=[{**row,"sha256":row["sourceSHA256"],"bytes":len(before)} for row in old["originals"]]
    compiles=[]
    with tempfile.TemporaryDirectory(prefix="mongotv-exit-scoped-template-review-") as folder:
        for operation in ("capture","observe","target","verify","apply","rollback","compile"):
            code=app.native_code(template,request,operation,originals if operation in ("verify","apply","rollback","compile") else None,
                                 pageFirst=1,pageCount=20,expectedTargetSHA256=app.sha(before),
                                 compileSources={"before":before.decode(),"candidate":after.decode()})
            path=Path(folder)/(operation+".luau");path.write_bytes(code.encode())
            for opt in (0,1):
                run=subprocess.run([str(app.helpers.COMPILER),"--binary","-g0",f"-O{opt}",str(path)],capture_output=True,timeout=20)
                assert run.returncode==0,run.stderr.decode(errors="replace")
                compiles.append({"operation":operation,"optimization":opt,"pass":True,"inputSHA256":app.sha(code.encode())})
    helper=app.offline_gate(app.ROOT,destination/"offline-helper",False,before,after)
    result={"schema":"mongotv-exit-scoped-review-v1","pass":True,"templateCompiles":compiles,"helper":helper,
            "beforeSHA256":app.sha(before),"candidateSHA256":app.sha(after),"bytesRemoved":73,
            "nativeCalls":0,"productionWrites":0,"manifestWrites":0,
            "wrapperSHA256":app.sha(Path(app.__file__).read_bytes()),"templateSHA256":app.sha(template.encode()),
            "limits":"Actual pure-literal proof, canonical O1 equivalence, paired50/reentry50, two semantic mutants, and existing neighboring92 offline ports. Native-template compilation alone does not bind all213 native originals or execute real ScriptEditorService. Root owns native parser/CAS/export/after parity."}
    app.save(destination/"result.json",app.encoded(result))
    print(json.dumps({"pass":True,"templateCompiles":len(compiles),"pairedChecksPerVersion":50,"reentryChecksPerVersion":50,"neighborChecksPerVersion":92,"nativeCalls":0}))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--receipt-directory",type=Path,required=True)
    main(parser.parse_args().receipt_directory)
