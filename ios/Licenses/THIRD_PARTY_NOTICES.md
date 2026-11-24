# Native OCR dependencies

NativeOCR.cpp adapts preprocessing and postprocessing from RapidAI/RapidOCR 1.4.4 and its PaddleOCR-derived modules (PaddlePaddle Authors, copyright 2020, Apache-2.0). Modifications include the C++/iOS integration, explicit validation and error propagation. The three model files are copied unchanged from rapidocr-onnxruntime 1.4.4 and verified against Models/ocr-manifest.json. The dictionary comes from the recognition model metadata, with CTC blank and trailing space added as in the Python reference.

- RapidOCR/PaddleOCR: https://github.com/RapidAI/RapidOCR and https://github.com/PaddlePaddle/PaddleOCR . See Apache-2.0.txt.
- OpenCV 4.12.0: https://github.com/opencv/opencv/releases/tag/4.12.0 . Apache-2.0. Official iOS archive SHA256: 86b42c9f141cd9169b91be2fc380b0e556a88a95c98ccc8e7aef8349ab74cf70.
- ONNX Runtime 1.24.2: Microsoft Corporation, MIT License. See ONNX-Runtime.txt. The official C/C++ Apple archive and checksum are listed in https://github.com/microsoft/onnxruntime-swift-package-manager/blob/1.24.2/Package.swift . SHA256: f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54.
- Clipper 6.4.2: Angus Johnson, copyright 2010–2017, Boost Software License 1.0. See Boost-1.0.txt and the attribution in the source headers. Unmodified clipper.cpp/clipper.hpp were extracted from pyclipper 1.4.0's source archive (SHA256 9882bd889f27da78add4dd6f881d25697efc740bf840274e749988d25496c8e1). The pyclipper distribution's separate MIT license is retained as pyclipper-MIT.txt.

Native inference uses the CPU provider, two intra-op threads and one inter-op thread. The Mac reference currently uses different ONNX Runtime/OpenCV library versions. Identical weights do not establish numerical equivalence; comparison results and versions are recorded separately. No Apple Vision substitution is made.
