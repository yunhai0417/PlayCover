Pod::Spec.new do |s|
  s.name         = 'PlayTools'
  s.version      = '1.0.0'
  s.summary      = 'Local PlayTools payload for PlayCover'
  s.description  = <<-DESC
  Script-only pod that embeds the locally built PlayTools.xcframework
  into the PlayCover app bundle and post-processes it (vtool maccatalyst
  conversion, deep framework rebundle). The framework is never linked
  at compile time; it is injected into IPAs at install time.
  Rebuild it with scripts/build-playtools.sh from the local PlayTools repo.
                       DESC
  s.homepage     = 'https://playcover.github.io/'
  s.license      = { :type => 'GPLv3' }
  s.author       = { 'PlayCover' => 'playcover@github.com' }
  s.source       = { :git => 'https://github.com/PlayCover/PlayTools.git' }
  s.platform     = :osx, '12.0'

  # Payload kept inside the pod directory; declared so the spec is not empty.
  # Never copied or linked by CocoaPods — the script_phase below embeds it.
  s.preserve_paths = ['PlayTools.xcframework', 'PlayTools.commit']

  s.script_phase = {
    :name => 'Copy PlayTools framework',
    :shell_path => '/bin/zsh',
    :execution_position => :after_compile,
    # Paths must resolve in the Pods project context (the phase runs on the pod's
    # aggregate target there): PODS_TARGET_SRCROOT points at Vendor/, and
    # PODS_CONFIGURATION_BUILD_DIR is the shared products dir holding PlayCover.app.
    :input_files => ['${PODS_TARGET_SRCROOT}/PlayTools.xcframework/ios-arm64/PlayTools.framework'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/PlayCover.app/Contents/Frameworks/PlayTools.framework'],
    :script => <<-'SCRIPT'
set -euo pipefail

if [ ! -d "${SCRIPT_INPUT_FILE_0}" ]; then
  echo "error: PlayTools.xcframework not found at ${SCRIPT_INPUT_FILE_0}" >&2
  echo "error: run scripts/build-playtools.sh to build it from the local PlayTools repository" >&2
  exit 1
fi

echo "Copying PlayTools"
mkdir -p "$(dirname "${SCRIPT_OUTPUT_FILE_0}")"
rm -rf "${SCRIPT_OUTPUT_FILE_0}"
ditto "${SCRIPT_INPUT_FILE_0}" "${SCRIPT_OUTPUT_FILE_0}"

echo "Handling AKInterface files"
mkdir -p "${SCRIPT_OUTPUT_FILE_0}/PlugIns"
rm -rf   "${SCRIPT_OUTPUT_FILE_0}/PlugIns/AKInterface.bundle"
cp -R    "${SCRIPT_INPUT_FILE_0}/PlugIns/AKInterface.bundle" "${SCRIPT_OUTPUT_FILE_0}/PlugIns/AKInterface.bundle"

echo "Converting to maccatalyst"
vtool \
  -set-build-version maccatalyst 11.0 14.0 \
  -replace -output \
  "${SCRIPT_OUTPUT_FILE_0}/PlayTools" \
  "${SCRIPT_OUTPUT_FILE_0}/PlayTools" || true

echo "Converting component bundles to maccatalyst"
for bundle in "${SCRIPT_OUTPUT_FILE_0}"/PlugIns/*.bundle; do
  [ -d "$bundle" ] || continue
  name="$(basename "$bundle" .bundle)"
  if [ "$name" = "AKInterface" ]; then
    continue
  fi
  exe="$bundle/$name"
  if [ -f "$exe" ]; then
    vtool -set-build-version maccatalyst 11.0 14.0 -replace -output "$exe" "$exe" || true
  fi
done

echo "Rebundling shadow framework to deep framework structure"
FRAME="${SCRIPT_OUTPUT_FILE_0}"
NAME="PlayTools"

if [ -d "$FRAME" ] && [ ! -d "$FRAME/Versions" ]; then
  echo "Rebundling $NAME as macOS deep framework…"

  PARENT="$(dirname "$FRAME")"
  BASENAME="$(basename "$FRAME")"
  TMP="$PARENT/.${BASENAME}.rebundle"

  rm -rf "$TMP"
  mkdir -p "$TMP/Versions/A/Resources" "$TMP/Versions/A/Modules" "$TMP/Versions/A/PlugIns"

  echo "moving shallow content to tmp A"
  [ -f "$FRAME/$NAME" ]      && cp -p "$FRAME/$NAME"      "$TMP/Versions/A/$NAME"
  [ -d "$FRAME/Headers" ]    && cp -Rp "$FRAME/Headers"   "$TMP/Versions/A/Headers"
  [ -d "$FRAME/Modules" ]    && cp -Rp "$FRAME/Modules"   "$TMP/Versions/A/Modules"
  [ -f "$FRAME/Info.plist" ] && cp -p "$FRAME/Info.plist" "$TMP/Versions/A/Resources/Info.plist"

  if [ -d "$FRAME/Resources" ]; then
    ditto "$FRAME/Resources" "$TMP/Versions/A/Resources"
  fi

  for lproj in "$FRAME"/*.lproj; do
    cp -Rp "$lproj" "$TMP/Versions/A/Resources"
  done

  if [ -d "$FRAME/PlugIns" ]; then
    ditto "$FRAME/PlugIns" "$TMP/Versions/A/PlugIns"
  fi

  echo "symlinking playtools"
  ln -s A "$TMP/Versions/Current"
  ln -s Versions/Current/Resources "$TMP/Resources"
  [ -d "$TMP/Versions/A/Headers" ] && ln -s Versions/Current/Headers "$TMP/Headers"
  [ -d "$TMP/Versions/A/Modules" ] && ln -s Versions/Current/Modules "$TMP/Modules"
  ln -s Versions/Current/$NAME "$TMP/$NAME"
  [ -d "$TMP/Versions/A/PlugIns" ] && ln -s Versions/Current/PlugIns "$TMP/PlugIns"

  rm -rf "$FRAME"
  mv "$TMP" "$FRAME"

  echo "Rebundle done."
fi
SCRIPT
  }
end
