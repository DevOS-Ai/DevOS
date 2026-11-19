# DevOS Agent branding of the engine's own process name and service banner
# (applied by packaging/devos-agent prepare(); the build fails if a line moved).
s|setproctitle.setproctitle("hermes")|setproctitle.setproctitle("devos-agent")|
s|libc.prctl(15, b"hermes", 0, 0, 0)|libc.prctl(15, b"devos-agent", 0, 0, 0)|
s|│           ☤ Hermes Gateway Starting...                 │|│           DevOS Agent starting...                       │|
s|│  Messaging platforms + cron scheduler                    │|│  Local API for the DevOS shell + task scheduler         │|
s|base = f"Hermes Agent v{get_version_info().derived_version} ({RELEASE_DATE})"|base = f"DevOS Agent · engine {get_version_info().derived_version}"|
s|nous_str = _dim_sep("Nous Research")|nous_str = ""|
