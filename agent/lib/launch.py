"""Start the DevOS Agent engine from its packaged tree (see /usr/bin/devos-agent)."""
import os
import sys

ROOT = "/usr/lib/devos/agent"
paths = [f"{ROOT}/site", f"{ROOT}/src"]
sys.path[:0] = paths
# Child processes the engine starts with sys.executable need the same import path.
os.environ["PYTHONPATH"] = os.pathsep.join(paths + [p for p in os.environ.get("PYTHONPATH", "").split(os.pathsep) if p])
sys.argv[0] = "devos-agent"

from hermes_cli.main import main  # noqa: E402

main()
