# SentencePiece's iOS CLI targets expect this toolchain helper at configure time.
# We build only sentencepiece-static; no CLI executable is installed on the phone.
function(set_xcode_property TARGET XCODE_PROPERTY XCODE_VALUE XCODE_RELVERSION)
  set_property(TARGET ${TARGET} PROPERTY XCODE_ATTRIBUTE_${XCODE_PROPERTY} ${XCODE_VALUE})
endfunction()
