#!/usr/bin/env python3
"""Checks that every string of ChordUI's interface has its French and Spanish.

    app/scripts/check-localizations.py                 # the catalog alone
    app/scripts/check-localizations.py --build <dir>   # and the strings a build found

Reads app/ChordUI/Localizable.xcstrings. Fails when a string has no translation, one
that isn't marked translated, or one whose placeholders (%@, %d, %1$@…) don't match
the English. Xcode adds new strings to the catalog when it builds, xcodebuild doesn't:
with --build, the strings the compiler extracted (*.stringsdata under <dir>) must all
be in the catalog too.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

LANGUAGES = ["fr", "es"]
CATALOG = Path(__file__).resolve().parent.parent / "ChordUI" / "Localizable.xcstrings"
# A printf placeholder: position, flags, width, precision, length, conversion.
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDuUxXoOfeEgGcCsSpaA])")


def placeholders(text):
    return Counter(PLACEHOLDER.findall(text.replace("%%", "")))


def units(localization):
    """Every string unit of a localization, plurals and device variations included."""
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for cases in localization.get("variations", {}).values():
        for case in cases.values():
            yield from units(case)


def problems(key, entry):
    if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
        return
    localizations = entry.get("localizations", {})
    english = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
    for language in LANGUAGES:
        localization = localizations.get(language)
        if localization is None:
            yield f"no {language}"
            continue
        found = list(units(localization))
        if not found:
            yield f"{language} is empty"
        for unit in found:
            value = unit.get("value", "")
            if unit.get("state") != "translated" or not value.strip():
                yield f"{language} not translated ({unit.get('state', 'no state')})"
            elif "stringUnit" in localization and placeholders(value) != placeholders(english):
                yield f"{language} placeholders differ: {value!r}"


def extracted(build):
    """The keys of ChordUI's Localizable table that the compiler found in the code."""
    keys = set()
    for data in Path(build).rglob("*.stringsdata"):
        content = json.loads(data.read_text())
        # Left over from a source file that no longer exists.
        if not Path(content.get("source", "")).exists():
            continue
        keys.update(item["key"] for item in content.get("tables", {}).get("Localizable", []))
    return keys


def main():
    args = sys.argv[1:]
    build = None
    if args[:1] == ["--build"]:
        build, args = args[1], args[2:]
    catalog = Path(args[0]) if args else CATALOG
    strings = json.loads(catalog.read_text())["strings"]
    failures = [(key, problem) for key, entry in strings.items() for problem in problems(key, entry)]
    if build:
        failures += [(key, "used in the code, missing from the catalog (open it in Xcode, or add it by hand)")
                     for key in sorted(extracted(build) - strings.keys())]
    for key, problem in failures:
        print(f"{catalog.name}: {key!r}: {problem}")
    if failures:
        print(f"\n{len(failures)} problem(s). Every visible string needs its French and Spanish "
              "(Xcode's string catalog editor, or by hand).")
        return 1
    print(f"{len(strings)} strings, all in {', '.join(LANGUAGES)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
