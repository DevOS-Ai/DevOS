"""DevOS Agent branding of the engine's user-facing text (applied by packaging/devos-agent).

    python engine-branding.py FILE...

Rewrites only prose, never code:
  "Hermes Agent"                     -> "DevOS Agent"
  "Hermes" + space + lowercase word   -> "DevOS Agent"   ("Hermes could not…", "Hermes is…")
  "Hermes" before punctuation, "(", "RPC" or "#" in messages -> "DevOS Agent"
  "`hermes <command>"                -> "`devos-agent <command>"   (commands the user is told to run)
  the terminal UI's "Nous Research" taglines -> DevOS
Identifiers (HermesCommand, hermes_cli, …) and the "Hey Hermes" wake word (a real audio
trigger) are left alone. Prints how many replacements each file got; fails if none at all.
"""
import re
import sys

RULES = [
    (re.compile(r"\bHermes Agent\b"), "DevOS Agent"),
    (re.compile(r"(?<!Hey )\bHermes(?= [a-z])"), "DevOS Agent"),
    (re.compile(r"`hermes (?=[a-z])"), "`devos-agent "),
    (re.compile(r"background hermes process"), "background devos-agent process"),
    # "…did not reach Hermes.", "inside Hermes (…)", "running Hermes\"", "Hermes RPC failed", "Hermes #2"
    (re.compile(r"(?<!Hey )\bHermes(?=[.,!?\"'’]| \(| \\x| RPC| #)"), "DevOS Agent"),
]
# The terminal UI's taglines (the bundle keeps \xB7 as an escape in its source).
JS_RULES = [
    (re.compile(r'"Nous Research \\xB7 Messenger of the Digital Gods"'), r'"DevOS \\xB7 the agent of your system"'),
    (re.compile(r'tagMid: "Messenger of the Digital Gods"'), 'tagMid: "the agent of your system"'),
    (re.compile(r'TAG_TINY = "Nous Research"'), 'TAG_TINY = "DevOS"'),
    (re.compile(r'children: " \\xB7 Nous Research"'), r'children: " \\xB7 DevOS"'),
]


def main(paths: list[str]) -> None:
    total = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        count = 0
        # Python sources: prose rules only, so no string a program compares is touched.
        rules = RULES[:4] if path.endswith(".py") else RULES + JS_RULES
        for pattern, repl in rules:
            text, n = pattern.subn(repl, text)
            count += n
        if count:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        total += count
        print(f"{count:4d}  {path}")
    if total == 0:
        sys.exit("engine-branding: nothing replaced; the engine's wording changed")


if __name__ == "__main__":
    main(sys.argv[1:])
