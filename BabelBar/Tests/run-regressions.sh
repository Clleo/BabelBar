#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
review_dir="$(mktemp -d /private/tmp/babelbar-tests.XXXXXX)"
trap 'rm -rf "$review_dir"' EXIT
python3 - "$repo_dir" "$review_dir" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1])/'BabelBar'; dst=Path(sys.argv[2])
speech=(src/'LiveDictation.swift').read_text()
core=speech[speech.index('struct LiveSpeechWord'):speech.index('/// All lifecycle')]
settings=(src/'SettingsStore.swift').read_text().split('// Lang Codable conformance')[0]
voice=(src/'VoiceInput.swift').read_text()
modifier=voice[voice.index('struct ModifierCombo'):voice.index('enum VoiceAction')]
(dst/'Core.swift').write_text('import Foundation\n'+core+'\n'+modifier+'\n'+settings+'\nenum Lang: String, Codable { case ru, en }\n')
PY
swiftc -parse-as-library -module-cache-path "$review_dir/cache" \
  "$repo_dir/BabelBar/LiveTyper.swift" "$repo_dir/BabelBar/Dictionaries.swift" \
  "$repo_dir/BabelBar/Localization.swift" "$repo_dir/BabelBar/KeyCombo.swift" "$repo_dir/BabelBar/VoiceCommands.swift" \
  "$review_dir/Core.swift" "$repo_dir/Tests/DictationRegressionTests.swift" \
  -o "$review_dir/regressions"
"$review_dir/regressions"
