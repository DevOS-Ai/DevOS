# Fixes to the pinned engine (applied by packaging/devos-agent prepare()).
# GET /v1/skills: the handler passes an argument _find_all_skills() no longer accepts, so
# the skills listing always failed with HTTP 500.
s|skip_disabled=False, include_editorial=True|skip_disabled=False|
